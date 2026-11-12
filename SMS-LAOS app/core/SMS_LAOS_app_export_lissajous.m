function manifest = SMS_LAOS_app_export_lissajous(previews, folder, options, sdResults)
%SMS_LAOS_APP_EXPORT_LISSAJOUS Export selected stress loops and their samples.
% Each SD result must correspond to its preview and its current input settings.
% Total-only plots use the preview. Requesting any component puts every plot
% on the native SD window and uses its measured, mean-centered total stress.
if nargin<3,options=struct();end
defaults=struct('TargetStrainPercent',[],'TolerancePercent',0.5,'SelectedSourcePaths',{{}}, ...
    'Mode','per_file','CycleMode','last_n','LastNCycles',1, ...
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

n=numel(selected);curves=cell(1,n);bases=cell(1,n);labels=cell(1,n);csvNames=cell(1,n);
specs=plot_specs(options);
records=repmat(struct('inputIndex',0,'sourcePath','','sourceName','','measuredStrainAmplitudePercent',NaN, ...
    'frequencyHz',NaN,'startTime_s',NaN,'endTime_s',NaN,'sampleCount',0,'curveCSV','','decompositionCSV','', ...
    'figures',{{}},'sourceSignature',struct(),'previewOptions',struct(),'unitConversion',struct(), ...
    'dataSource','','window',struct(),'decompositionSettings',struct()),n,1);
for j=1:n
    k=selected(j);P=previews{k};row=k;
    if isfield(P,'inputIndex'),row=P.inputIndex;end
    if ~isscalar(row)||~isnumeric(row)||~isfinite(row)||row<1||row~=fix(row)
        error('MergedLAOS:LissajousPreview','Preview inputIndex must be a positive integer.');
    end
    [~,stem]=fileparts(P.source.name);stem=regexprep(stem,'[^A-Za-z0-9._-]','_');if isempty(stem),stem='data';end
    bases{j}=sprintf('%03d_%s_%spercent',row,stem(1:min(80,numel(stem))),number_slug(P.strainAmplitudePercent));
    labels{j}=sprintf('%.5g%% | %s',P.strainAmplitudePercent,P.source.name);
    r=records(j);r.inputIndex=row;r.sourcePath=P.source.path;r.sourceName=P.source.name;
    r.measuredStrainAmplitudePercent=P.strainAmplitudePercent;r.sourceSignature=P.source.signature;
    if isfield(P,'options'),r.previewOptions=P.options;end
    if isfield(P,'unit_conversion'),r.unitConversion=P.unit_conversion;end
    if useSD
        R=sdResults{k};validate_sd(P,R);
        mask=window_mask(R.time,R.freq_hz,options,P.source.name,R.n_cycles_used);
        sourceTime=R.time_raw(R.selected_mask);
        curves{j}=table(R.time(mask),R.strain(mask),100*R.strain(mask),R.gammadot(mask),R.stress(mask), ...
            R.stress_elastic(mask),R.stress_viscous(mask),sourceTime(mask), ...
            'VariableNames',{'Time_s','Strain','Strain_percent','StrainRate_per_s','Stress_Pa','ElasticStress_Pa','ViscousStress_Pa','SourceTime_s'});
        csvNames{j}=[bases{j} '_decomposition_curves.csv'];
        r.decompositionCSV=csvNames{j};r.frequencyHz=R.freq_hz;r.dataSource='stress_decomposition';
        r.window=struct('cycleMode',options.CycleMode,'requestedLastNCycles',options.LastNCycles, ...
            'analysisStart_s',R.t_start_use,'analysisEnd_s',R.t_end_use,'analysisCycles',R.n_cycles_used, ...
            'sourceStart_s',sourceTime(find(mask,1,'first')),'sourceEnd_s',sourceTime(find(mask,1,'last')), ...
            'timeOrigin','Time_s is elapsed from the first SD sample; SourceTime_s preserves acquisition time.');
        r.decompositionSettings=R.settings;
    else
        mask=window_mask(P.time,P.frequencyHz,options,P.source.name,[]);
        curves{j}=table(P.time(mask),P.strain(mask),100*P.strain(mask),P.strainRate(mask),P.stress(mask), ...
            'VariableNames',{'Time_s','Strain','Strain_percent','StrainRate_per_s','Stress_Pa'});
        csvNames{j}=[bases{j} '_curves.csv'];r.frequencyHz=P.frequencyHz;r.dataSource='preview';
        r.window=struct('cycleMode',options.CycleMode,'requestedLastNCycles',options.LastNCycles, ...
            'timeOrigin','Time_s preserves acquisition time.');
    end
    times=curves{j}.Time_s;r.startTime_s=times(1);r.endTime_s=times(end);r.sampleCount=numel(times);
    if useTotal,r.curveCSV=csvNames{j};end
    records(j)=r;
end

parent=fileparts(folder);if ~isfolder(parent),[ok,msg]=mkdir(parent);if ~ok,error('MergedLAOS:LissajousFolder','%s',msg);end,end
stage=tempname(parent);mkdir(stage);cleanup=onCleanup(@()cleanup_stage(stage));
for j=1:n,writetable(curves{j},fullfile(stage,csvNames{j}));end
allFiles=csvNames;
if strcmp(options.Mode,'overlay')
    figFiles=render_plots(curves,labels,stage,'overlay',options,specs);
    allFiles=[allFiles figFiles];
    for j=1:n,records(j).figures=figFiles;end
else
    for j=1:n
        figFiles=render_plots(curves(j),labels(j),stage,bases{j},options,specs);
        records(j).figures=figFiles;allFiles=[allFiles figFiles]; %#ok<AGROW>
    end
end
for k=selected,check_source(previews{k});end
manifest=struct('schemaVersion',2,'application','SMS-LAOS', ...
    'createdUTC',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')), ...
    'outputFolder',folder,'options',options,'selectionMode',selectionMode,'inputCount',numel(previews), ...
    'matchedCount',n,'plots',specs,'entries',records,'files',{[allFiles {'manifest.json'}]}, ...
    'notes',{{ ...
    'File selection uses checked source paths or measured preview amplitudes within the specified absolute percentage-point tolerance.', ...
    'Total-only plots retain measured offsets, original timestamps and preview strain rate.', ...
    'If an SD component is selected, all curves for that file share its SD analysis samples and frequency. Total stress and strain are the mean-centered measured values on the SD window.', ...
    'Component stresses are SD first- and third-order reconstructions. The viscous abscissa is the physical strain rate in s^-1.', ...
    'Last N uses the end of the active preview or SD window; no loop is forcibly closed. CSV columns contain the plotted samples.'}});
write_json(fullfile(stage,'manifest.json'),manifest);
assert_empty(folder);
if ~isfolder(folder),[ok,msg]=mkdir(folder);if ~ok,error('MergedLAOS:LissajousFolder','%s',msg);end,end
for k=1:numel(manifest.files)
    target=fullfile(folder,manifest.files{k});
    if exist(target,'file')~=0,error('MergedLAOS:LissajousExists','Output appeared during export: %s',target);end
    [ok,msg]=movefile(fullfile(stage,manifest.files{k}),target);
    if ~ok,error('MergedLAOS:LissajousWrite','Cannot publish %s: %s',manifest.files{k},msg);end
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
specs=specs(logical([o.IncludeStressStrain o.IncludeStressRate o.IncludeElasticStrain o.IncludeViscousRate]));
end

function files=render_plots(curves,labels,folder,base,o,specs)
files={};colors=lines(numel(curves));
for spec=specs
    fig=figure('Visible','off','Color','w','Position',[100 100 850 650]);
    c=onCleanup(@()delete(fig));
    ax=axes(fig,'Position',[.14 .17 .8 .73],'FontName','Arial','FontSize',12,'Box','on','LineWidth',1,'NextPlot','add');
    for j=1:numel(curves)
        T=curves{j};plot(ax,T.(spec.xColumn),T.(spec.yColumn),'LineWidth',1.4,'Color',colors(j,:),'DisplayName',labels{j});
    end
    xlabel(ax,spec.xLabel);ylabel(ax,spec.yLabel);title(ax,spec.title);
    grid(ax,'on');ax.GridAlpha=.12;legend(ax,'Location','best','Interpreter','none','FontSize',10);axis(ax,'padded');
    for format={'PNG','PDF','FIG'}
        if ~o.(['Format' format{1}]),continue,end
        filename=[base '_' spec.suffix '.' lower(format{1})];path=fullfile(folder,filename);
        if strcmp(format{1},'PNG')
            exportgraphics(fig,path,'Resolution',300);
        elseif strcmp(format{1},'PDF')
            exportgraphics(fig,path,'ContentType','vector');
        else
            savefig(fig,path);
        end
        files{end+1}=filename; %#ok<AGROW>
    end
    clear c
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
