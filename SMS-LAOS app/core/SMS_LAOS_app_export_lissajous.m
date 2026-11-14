function manifest = SMS_LAOS_app_export_lissajous(previews, folder, options, sdResults, progress)
%SMS_LAOS_APP_EXPORT_LISSAJOUS Export selected stress loops and their samples.
% Each SD result must correspond to its preview and its current input settings.
% Total-only plots use the preview. Requesting any component puts every plot
% on the native SD window and uses its measured, mean-centered total stress.
% AxisScale selects dimensional, normalised or both. Each file's plotted
% samples define its peak-absolute strain, rate and total stress references.
% progress(fraction,message) can raise an error to cancel before publication.
if nargin<3,options=struct();end
if nargin<5,progress=[];end
if ~isempty(progress)&&~isa(progress,'function_handle')
    error('MergedLAOS:LissajousOptions','Progress must be a function handle.');
end
defaults=struct('TargetStrainPercent',[],'TolerancePercent',0.5,'SelectedSourcePaths',{{}}, ...
    'Mode','per_file','AxisScale','dimensional','CycleMode','last_n','LastNCycles',1, ...
    'FormatPNG',true,'FormatPDF',true,'FormatFIG',false, ...
    'IncludeStressStrain',true,'IncludeStressRate',true,'IncludeElasticStrain',false,'IncludeViscousRate',false);
options=merge_options(defaults,options);validate_options(options);
if isstruct(previews),previews=num2cell(previews);end
if isempty(previews)&&~isempty(options.SelectedSourcePaths)
    error('MergedLAOS:LissajousSelection','The checked files have no available previews. Reload or retry their previews.');
end
if ~iscell(previews)||isempty(previews)
    error('MergedLAOS:LissajousEmpty','Load and preview data before exporting Lissajous curves.');
end
useSD=options.IncludeElasticStrain||options.IncludeViscousRate;
useTotal=options.IncludeStressStrain||options.IncludeStressRate;
if nargin<4||isempty(sdResults),sdResults=cell(size(previews));end
if useSD && (~iscell(sdResults)||numel(sdResults)~=numel(previews))
    error('MergedLAOS:LissajousSD','Supply a Stress decomposition result for each selected file. Run Stress decomposition and retry.');
end
folder=absolute_path(char(folder));assert_empty(folder);
if ~isempty(progress),progress(0,'Checking Lissajous selections');end
selected=[];paths={};
explicit=~isempty(options.SelectedSourcePaths);
selectionMode='amplitude_tolerance';
if explicit,selectionMode='selected_files';elseif isempty(options.TargetStrainPercent),selectionMode='all_previews';end
required={'time','strain','stress','strainRate','frequencyHz','strainAmplitudePercent','source'};
for k=1:numel(previews)
    P=previews{k};
    if ~isstruct(P)||~isscalar(P)||~all(isfield(P,required))||~isfield(P.source,'path')
        error('MergedLAOS:LissajousPreview','Supply complete SMS_LAOS_app_preview results.');
    end
    if explicit
        match=ismember({P.source.path},options.SelectedSourcePaths) && ~ismember({P.source.path},paths);
    else
        match=isempty(options.TargetStrainPercent)||any(abs(P.strainAmplitudePercent-options.TargetStrainPercent(:))<=options.TolerancePercent);
    end
    if match
        check_source(P);selected(end+1)=k;paths{end+1}=P.source.path; %#ok<AGROW>
    end
end
if explicit
    missing=setdiff(options.SelectedSourcePaths,paths,'stable');
    if ~isempty(missing)
        error('MergedLAOS:LissajousSelection','Selected file has no available preview: %s. Reload or retry its preview.',missing{1});
    end
end
if isempty(selected)
    error('MergedLAOS:LissajousNoMatch','No measured file amplitude falls within the requested strain tolerance. Choose an available amplitude or widen the tolerance.');
end

n=numel(selected);
overlay=strcmp(options.Mode,'overlay');
if overlay,overlayCurves=cell(1,n);end
labels=cell(1,n);specs=plot_specs(options);
formats={'PNG','PDF','FIG'};
formats=formats(logical([options.FormatPNG options.FormatPDF options.FormatFIG]));
groups=n;if overlay,groups=1;end
totalSteps=2*n+groups*numel(specs)*numel(formats)+1;
done=0;
parent=fileparts(folder);if ~isfolder(parent),[ok,msg]=mkdir(parent);if ~ok,error('MergedLAOS:LissajousFolder','%s',msg);end,end
stage=tempname(parent);mkdir(stage);cleanup=onCleanup(@()cleanup_stage(stage)); %#ok<NASGU>
fig=[];plotLines=[];ax=[];
allFiles={};

records=repmat(struct('inputIndex',0,'sourcePath','','sourceName','','measuredStrainAmplitudePercent',NaN, ...
    'frequencyHz',NaN,'startTime_s',NaN,'endTime_s',NaN,'sampleCount',0,'curveCSV','','decompositionCSV','', ...
    'figures',{{}},'sourceSignature',struct(),'previewOptions',struct(),'unitConversion',struct(), ...
    'dataSource','','window',struct(),'decompositionSettings',struct(),'scaleFactors',struct()),n,1);
for j=1:n
    k=selected(j);P=previews{k};row=k;
    advance(sprintf('Preparing curves %d/%d: %s',j,n,P.source.name));
    if isfield(P,'inputIndex'),row=P.inputIndex;end
    if ~isscalar(row)||~isnumeric(row)||~isfinite(row)||row<1||row~=fix(row)
        error('MergedLAOS:LissajousPreview','Preview inputIndex must be a positive integer.');
    end
    [~,stem]=fileparts(P.source.name);stem=regexprep(stem,'[^A-Za-z0-9._-]','_');if isempty(stem),stem='data';end
    base=sprintf('%03d_%s_%spercent',row,stem(1:min(80,numel(stem))),number_slug(P.strainAmplitudePercent));
    labels{j}=sprintf('%.5g%% | %s',P.strainAmplitudePercent,P.source.name);
    r=records(j);r.inputIndex=row;r.sourcePath=P.source.path;r.sourceName=P.source.name;
    r.measuredStrainAmplitudePercent=P.strainAmplitudePercent;r.sourceSignature=P.source.signature;
    if isfield(P,'options'),r.previewOptions=P.options;end
    if isfield(P,'unit_conversion'),r.unitConversion=P.unit_conversion;end
    if useSD
        R=sdResults{k};validate_sd(P,R);
        mask=window_mask(R.time,R.freq_hz,options,P.source.name,R.n_cycles_used);
        sourceTime=R.time_raw(R.selected_mask);
        T=table(R.time(mask),R.strain(mask),100*R.strain(mask),R.gammadot(mask),R.stress(mask), ...
            R.stress_elastic(mask),R.stress_viscous(mask),sourceTime(mask), ...
            'VariableNames',{'Time_s','Strain','Strain_percent','StrainRate_per_s','Stress_Pa','ElasticStress_Pa','ViscousStress_Pa','SourceTime_s'});
        csvName=[base '_decomposition_curves.csv'];
        r.decompositionCSV=csvName;r.frequencyHz=R.freq_hz;r.dataSource='stress_decomposition';
        r.window=struct('cycleMode',options.CycleMode,'requestedLastNCycles',options.LastNCycles, ...
            'analysisStart_s',R.t_start_use,'analysisEnd_s',R.t_end_use,'analysisCycles',R.n_cycles_used, ...
            'sourceStart_s',sourceTime(find(mask,1,'first')),'sourceEnd_s',sourceTime(find(mask,1,'last')), ...
            'timeOrigin','Time_s is elapsed from the first SD sample; SourceTime_s preserves acquisition time.');
        r.decompositionSettings=R.settings;
    else
        mask=window_mask(P.time,P.frequencyHz,options,P.source.name,[]);
        T=table(P.time(mask),P.strain(mask),100*P.strain(mask),P.strainRate(mask),P.stress(mask), ...
            'VariableNames',{'Time_s','Strain','Strain_percent','StrainRate_per_s','Stress_Pa'});
        csvName=[base '_curves.csv'];r.frequencyHz=P.frequencyHz;r.dataSource='preview';
        r.window=struct('cycleMode',options.CycleMode,'requestedLastNCycles',options.LastNCycles, ...
            'timeOrigin','Time_s preserves acquisition time.');
    end
    if ~strcmp(options.AxisScale,'dimensional')
        [T,r.scaleFactors]=normalise_curves(T,options,P.source.name);
    end
    r.startTime_s=T.Time_s(1);r.endTime_s=T.Time_s(end);r.sampleCount=height(T);
    if useTotal,r.curveCSV=csvName;end
    advance(sprintf('Writing curve data %d/%d: %s',j,n,P.source.name));
    writetable(T,fullfile(stage,csvName));allFiles{end+1}=csvName; %#ok<AGROW>
    if j==1
        fig=figure('Visible','off','Color','w','Position',[100 100 850 650]);
        figureCleanup=onCleanup(@()delete(fig)); %#ok<NASGU>
        ax=axes(fig,'Position',[.14 .17 .8 .73],'FontName','Arial','FontSize',12,'Box','on','LineWidth',1,'NextPlot','add');
        lineCount=1;if overlay,lineCount=n;end
        colors=lines(lineCount);plotLines=gobjects(1,lineCount);
        for i=1:lineCount
            plotLines(i)=line(ax,NaN,NaN,'LineWidth',1.4,'Color',colors(i,:));
        end
        grid(ax,'on');ax.GridAlpha=.12;axis(ax,'padded');
    end
    if overlay
        overlayCurves{j}=T;
    else
        r.figures=render_plots({T},labels(j),base);
        allFiles=[allFiles r.figures]; %#ok<AGROW>
    end
    records(j)=r;
end
if overlay
    figFiles=render_plots(overlayCurves,labels,'overlay');
    allFiles=[allFiles figFiles];
    for j=1:n,records(j).figures=figFiles;end
end
advance('Checking sources and finalising Lissajous export');
for k=selected,check_source(previews{k});end
manifest=struct('schemaVersion',3,'application','SMS-LAOS', ...
    'createdUTC',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')), ...
    'outputFolder',folder,'options',options,'selectionMode',selectionMode,'inputCount',numel(previews), ...
    'matchedCount',n,'plots',specs,'entries',records,'files',{[allFiles {'manifest.json'}]}, ...
    'notes',{{ ...
    'File selection uses checked source paths or measured preview amplitudes within the specified absolute percentage-point tolerance.', ...
    'Total-only plots retain measured offsets, original timestamps and preview strain rate.', ...
    'If an SD component is selected, all curves for that file share its SD analysis samples and frequency. Total stress and strain are the mean-centered measured values on the SD window.', ...
    'Component stresses are SD first- and third-order reconstructions. The viscous abscissa is the physical strain rate in s^-1.', ...
    'Normalised coordinates use the peak absolute values in each file''s plotted window. scaleFactors.strain is decimal strain, strainRate_per_s is physical rate, and totalStress_Pa is the common reference for all stress components. A reference for an unused horizontal axis is left empty.', ...
    'Last N uses the end of the active preview or SD window; no loop is forcibly closed. CSV columns contain the plotted samples.'}});
write_json(fullfile(stage,'manifest.json'),manifest);
if ~isempty(progress),progress(1,'Publishing Lissajous figures and data');end
assert_empty(folder);
if ~isfolder(folder),[ok,msg]=mkdir(folder);if ~ok,error('MergedLAOS:LissajousFolder','%s',msg);end,end
for k=1:numel(manifest.files)
    target=fullfile(folder,manifest.files{k});
    if exist(target,'file')~=0,error('MergedLAOS:LissajousExists','Output appeared during export: %s',target);end
    [ok,msg]=movefile(fullfile(stage,manifest.files{k}),target);
    if ~ok,error('MergedLAOS:LissajousWrite','Cannot publish %s: %s',manifest.files{k},msg);end
end

    function advance(message)
        if ~isempty(progress),progress(done/totalSteps,message);end
        done=done+1;
    end

    function files=render_plots(data,names,prefix)
        % Reuse one invisible figure, axes and set of lines for the whole
        % export. Per-file figures can be saved and released one file at a time.
        for lineIndex=1:numel(data),plotLines(lineIndex).DisplayName=names{lineIndex};end
        legend(ax,plotLines,'Location','best','Interpreter','none','FontSize',10);
        files={};
        for spec=specs
            for lineIndex=1:numel(data)
                sample=data{lineIndex};
                set(plotLines(lineIndex),'XData',sample.(spec.xColumn),'YData',sample.(spec.yColumn));
            end
            xlabel(ax,spec.xLabel);ylabel(ax,spec.yLabel);title(ax,spec.title);
            for index=1:numel(formats)
                fmt=formats{index};filename=[prefix '_' spec.suffix '.' lower(fmt)];
                advance(sprintf('Writing %s: %s',fmt,filename));
                path=fullfile(stage,filename);
                switch fmt
                    case 'PNG', exportgraphics(fig,path,'Resolution',300);
                    case 'PDF', exportgraphics(fig,path,'ContentType','vector');
                    case 'FIG', savefig(fig,path);
                end
                files{end+1}=filename; %#ok<AGROW>
            end
        end
    end

end

function validate_sd(P,R)
required={'source','settings','time','time_raw','selected_mask','strain','gammadot','stress','stress_elastic','stress_viscous', ...
    'freq_hz','n_cycles_used','t_start_use','t_end_use'};
if isempty(R)||~isstruct(R)||~isscalar(R)||~all(isfield(R,required))||~SMS_LAOS_app_source_current(R.source)|| ...
        ~strcmp(R.source.path,P.source.path)||R.source.bytes~=P.source.signature.Bytes||R.source.datenum~=P.source.signature.ModifiedDatenum
    error('MergedLAOS:LissajousSD','%s needs a current Stress decomposition result. Select the file, run Stress decomposition, then export again.',P.source.name);
end
if isfield(R,'input_settings')&&isfield(P,'options')
    for field=fieldnames(R.input_settings)'
        key=field{1};
        if ~isfield(P.options,key)||~isequaln(R.input_settings.(key),P.options.(key))
            error('MergedLAOS:LissajousSD','Input settings for %s no longer match its Stress decomposition result. Run Stress decomposition again.',P.source.name);
        end
    end
end
end

function mask=window_mask(t,frequency,o,name,sdCycles)
if strcmp(o.CycleMode,'all')
    mask=true(size(t));
elseif ~isempty(sdCycles)&&o.LastNCycles==sdCycles
    % An integral SD selection can end one sample short of its nominal duration.
    mask=true(size(t));
else
    seconds=o.LastNCycles/frequency;
    if (~isempty(sdCycles)&&o.LastNCycles>sdCycles)||t(end)-t(1)<seconds*(1-1e-7)
        error('MergedLAOS:LissajousWindow','%s has fewer than %d periods in its active window. Reduce Last N cycles or use all data.',name,o.LastNCycles);
    end
    mask=t>=t(end)-seconds;
end
if nnz(mask)<3,error('MergedLAOS:LissajousWindow','The requested loop window contains fewer than 3 samples.');end
end

function specs=plot_specs(o)
specs=struct('option',{'IncludeStressStrain','IncludeStressRate','IncludeElasticStrain','IncludeViscousRate'}, ...
    'suffix',{'elastic','viscous','elastic_stress_strain','viscous_stress_strain_rate'}, ...
    'title',{'Total stress vs strain','Total stress vs strain rate','Elastic stress vs strain','Viscous stress vs strain rate'}, ...
    'xColumn',{'Strain_percent','StrainRate_per_s','Strain_percent','StrainRate_per_s'}, ...
    'yColumn',{'Stress_Pa','Stress_Pa','ElasticStress_Pa','ViscousStress_Pa'}, ...
    'xLabel',{'Strain (%)','Strain rate (s^{-1})','Strain (%)','Strain rate (s^{-1})'}, ...
    'yLabel',{'Total stress (Pa)','Total stress (Pa)','Elastic stress (Pa)','Viscous stress (Pa)'});
if o.IncludeElasticStrain||o.IncludeViscousRate
    % Native SD total and separated stress should be distinguishable by filename.
    specs(1).suffix='total_stress_strain';
    specs(2).suffix='total_stress_strain_rate';
end
selected=logical([o.IncludeStressStrain o.IncludeStressRate o.IncludeElasticStrain o.IncludeViscousRate]);
[specs.axisScale]=deal('dimensional');
if strcmp(o.AxisScale,'dimensional'),specs=specs(selected);return,end
normal=specs;
xCols={'Strain_normalised','StrainRate_normalised','Strain_normalised','StrainRate_normalised'};
yCols={'TotalStress_normalised','TotalStress_normalised','ElasticStress_normalised','ViscousStress_normalised'};
xLabels={'Strain / peak |strain|','Strain rate / peak |strain rate|','Strain / peak |strain|','Strain rate / peak |strain rate|'};
yLabels={'Total stress','Total stress','Elastic stress','Viscous stress'};
for j=1:numel(normal)
    normal(j).axisScale='normalised';normal(j).suffix=[specs(j).suffix '_normalised'];
    normal(j).title=['Normalised ' lower(specs(j).title)];normal(j).xColumn=xCols{j};normal(j).yColumn=yCols{j};
    normal(j).xLabel=xLabels{j};normal(j).yLabel=[yLabels{j} ' / peak |total stress|'];
end
if strcmp(o.AxisScale,'both'),specs=[specs(selected),normal(selected)];else,specs=normal(selected);end
end

function [T,factors]=normalise_curves(T,o,name)
factors=struct('strain',[],'strainRate_per_s',[],'totalStress_Pa',peak(T.Stress_Pa,'total stress',name));
T.TotalStress_normalised=T.Stress_Pa./factors.totalStress_Pa;
if o.IncludeStressStrain||o.IncludeElasticStrain
    factors.strain=peak(T.Strain,'strain',name);
    T.Strain_normalised=T.Strain./factors.strain;
end
if o.IncludeStressRate||o.IncludeViscousRate
    factors.strainRate_per_s=peak(T.StrainRate_per_s,'strain rate',name);
    T.StrainRate_normalised=T.StrainRate_per_s./factors.strainRate_per_s;
end
if o.IncludeElasticStrain
    T.ElasticStress_normalised=T.ElasticStress_Pa./factors.totalStress_Pa;
    check_finite(T.ElasticStress_normalised,'elastic stress',name);
end
if o.IncludeViscousRate
    T.ViscousStress_normalised=T.ViscousStress_Pa./factors.totalStress_Pa;
    check_finite(T.ViscousStress_normalised,'viscous stress',name);
end
end

function value=peak(data,quantity,name)
check_finite(data,quantity,name);
value=max(abs(data));
if value==0
    error('MergedLAOS:LissajousScale','Cannot normalise %s: peak absolute %s is zero in the plotted window. Choose a different window or dimensional axes.',name,quantity);
end
end

function check_finite(data,quantity,name)
if any(~isfinite(data))
    error('MergedLAOS:LissajousScale','Cannot normalise %s: %s contains nonfinite values in the plotted window.',name,quantity);
end
end

function o=merge_options(o,s)
if ~isstruct(s)||~isscalar(s),error('MergedLAOS:LissajousOptions','Options must be a scalar structure.');end
for f=fieldnames(s)'
    if ~isfield(o,f{1}),error('MergedLAOS:LissajousOptions','Unknown Lissajous setting: %s',f{1});end
    o.(f{1})=s.(f{1});
end
o.Mode=char(o.Mode);o.CycleMode=char(o.CycleMode);

paths=o.SelectedSourcePaths;
if isempty(paths)
    paths={};
elseif isstring(paths)
    if any(ismissing(paths),'all'),error('MergedLAOS:LissajousSelection','Choose valid source paths.');end
    paths=cellstr(paths);
elseif ischar(paths)&&isrow(paths)
    paths={paths};
end
if ~iscellstr(paths)||(~isempty(paths)&&~isvector(paths))||any(cellfun(@isempty,paths))
    error('MergedLAOS:LissajousSelection','SelectedSourcePaths must list source file paths.');
end
o.SelectedSourcePaths=unique(reshape(paths,1,[]),'stable');
end
function validate_options(o)
value=o.AxisScale;
if ~((ischar(value)&&isrow(value))||(isstring(value)&&isscalar(value)&&~ismissing(value)))|| ...
        ~any(strcmp(value,{'dimensional','normalised','both'}))
    error('MergedLAOS:LissajousScale','AxisScale must be dimensional, normalised or both.');
end

if ~isnumeric(o.TargetStrainPercent)||any(~isfinite(o.TargetStrainPercent),'all')||any(o.TargetStrainPercent<=0,'all')
    error('MergedLAOS:LissajousTarget','Target strain amplitudes must be positive finite percentages, or empty for all files.');
end
if ~isnumeric(o.TolerancePercent)||~isscalar(o.TolerancePercent)||~isfinite(o.TolerancePercent)||o.TolerancePercent<0
    error('MergedLAOS:LissajousTolerance','Strain tolerance must be a nonnegative finite number of percentage points.');
end
if ~any(strcmp(o.Mode,{'per_file','overlay'}))||~any(strcmp(o.CycleMode,{'last_n','all'}))
    error('MergedLAOS:LissajousOptions','Mode must be per_file/overlay and CycleMode must be last_n/all.');
end
if ~isnumeric(o.LastNCycles)||~isscalar(o.LastNCycles)||~isfinite(o.LastNCycles)||o.LastNCycles<1||o.LastNCycles~=fix(o.LastNCycles)
    error('MergedLAOS:LissajousCycles','LastNCycles must be a positive integer.');
end
for field={'IncludeStressStrain','IncludeStressRate','IncludeElasticStrain','IncludeViscousRate'}
    v=o.(field{1});
    if ~(islogical(v)||isnumeric(v))||~isscalar(v)||~ismember(v,[0 1])
        error('MergedLAOS:LissajousPlots','Plot switches must be scalar true/false values.');
    end
end
if ~(o.IncludeStressStrain||o.IncludeStressRate||o.IncludeElasticStrain||o.IncludeViscousRate)
    error('MergedLAOS:LissajousPlots','Select at least one Lissajous plot.');
end
for field={'FormatPNG','FormatPDF','FormatFIG'}
    v=o.(field{1});
    if ~(islogical(v)||isnumeric(v))||~isscalar(v)||~ismember(v,[0 1])
        error('MergedLAOS:LissajousFormat','Format switches must be scalar true/false values.');
    end
end
if ~(o.FormatPNG||o.FormatPDF||o.FormatFIG),error('MergedLAOS:LissajousFormat','Choose at least one figure format.');end
end
function check_source(P)
if ~isfield(P.source,'path')||~isfield(P.source,'signature'),error('MergedLAOS:LissajousSource','Preview lacks source provenance.');end
d=dir(P.source.path);
if isempty(d)||d(1).isdir,error('MergedLAOS:SourceChanged','Source is missing: %s',P.source.path);end
s=struct('Exists',true,'Bytes',d(1).bytes,'ModifiedDatenum',d(1).datenum);
if ~isequal(P.source.signature,s),error('MergedLAOS:SourceChanged','Source changed after preview: %s. Reload it before exporting.',P.source.path);end
end
function assert_empty(path)
if isfile(path),error('MergedLAOS:LissajousExists','Output path is an existing file.');end
if isfolder(path)
    d=dir(path);d=d(~ismember({d.name},{'.','..'}));
    if ~isempty(d),error('MergedLAOS:LissajousExists','Choose a new or completely empty output folder; existing files are never overwritten.');end
end
end
function p=absolute_path(p)
if isempty(strtrim(p)),error('MergedLAOS:LissajousFolder','Choose an output folder.');end
if ispc,absolute=~isempty(regexp(p,'^[A-Za-z]:[\\/]|^\\\\','once'));else,absolute=p(1)=='/';end
if ~absolute,p=fullfile(pwd,p);end
end
function s=number_slug(x)
s=strrep(sprintf('%.6g',x),'.','p');s=strrep(s,'+','');
end
function write_json(path,value)
fid=fopen(path,'w','n','UTF-8');if fid<0,error('MergedLAOS:LissajousWrite','Cannot write %s',path);end
c=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
function cleanup_stage(stage)
if isfolder(stage),rmdir(stage,'s');end
end
