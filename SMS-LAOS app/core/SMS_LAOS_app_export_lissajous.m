function manifest = SMS_LAOS_app_export_lissajous(previews, folder, options)
%SMS_LAOS_APP_EXPORT_LISSAJOUS Export measured loops at requested strain levels.
% TargetStrainPercent and TolerancePercent are strain-amplitude percentage
% points (target 10 and tolerance 0.5 selects 9.5--10.5% measured strain).
% Empty TargetStrainPercent exports all supplied previews. No interpolation
% between strain amplitudes, phase averaging, or synthetic loop is used.
if nargin<3,options=struct();end
defaults=struct('TargetStrainPercent',[],'TolerancePercent',0.5,'Mode','per_file', ...
    'CycleMode','last_n','LastNCycles',1,'FormatPNG',true,'FormatPDF',true,'FormatFIG',false);
options=merge_options(defaults,options);validate_options(options);
if isstruct(previews),previews=num2cell(previews);end
if ~iscell(previews)||isempty(previews),error('MergedLAOS:LissajousEmpty','Load and preview data before exporting Lissajous curves.');end
folder=absolute_path(char(folder));assert_empty(folder);
required={'time','strain','stress','strainRate','frequencyHz','strainAmplitudePercent','source'};
selected=[]; masks={};
for k=1:numel(previews)
    P=previews{k};
    if ~isstruct(P)||~isscalar(P)||~all(isfield(P,required)),error('MergedLAOS:LissajousPreview','Supply complete SMS_LAOS_app_preview results.');end
    if isempty(options.TargetStrainPercent)||any(abs(P.strainAmplitudePercent-options.TargetStrainPercent(:))<=options.TolerancePercent)
        check_source(P);selected(end+1)=k; %#ok<AGROW>
        if strcmp(options.CycleMode,'all')
            mask=true(size(P.time));
        else
            seconds=options.LastNCycles/P.frequencyHz;
            if P.time(end)-P.time(1)<seconds*(1-1e-7)
                error('MergedLAOS:LissajousWindow','%s has fewer than %d estimated periods. Reduce Last N cycles or use all data.',P.source.name,options.LastNCycles);
            end
            mask=P.time>=P.time(end)-seconds;
        end
        if nnz(mask)<3,error('MergedLAOS:LissajousWindow','The requested loop window contains fewer than 3 acquired samples.');end
        masks{end+1}=mask; %#ok<AGROW>
    end
end
if isempty(selected)
    error('MergedLAOS:LissajousNoMatch','No measured file amplitude falls within the requested strain tolerance. Choose an available amplitude or widen the tolerance.');
end
parent=fileparts(folder);if ~isfolder(parent),[ok,msg]=mkdir(parent);if ~ok,error('MergedLAOS:LissajousFolder','%s',msg);end,end
stage=tempname(parent);mkdir(stage);cleanup=onCleanup(@()cleanup_stage(stage));
records=repmat(struct('inputIndex',0,'sourcePath','','sourceName','','measuredStrainAmplitudePercent',NaN, ...
    'frequencyHz',NaN,'startTime_s',NaN,'endTime_s',NaN,'sampleCount',0,'curveCSV','','figures',{{}}, ...
    'sourceSignature',struct(),'previewOptions',struct(),'unitConversion',struct()),numel(selected),1);
allFiles={};labels=cell(numel(selected),1);bases=cell(numel(selected),1);
for j=1:numel(selected)
    k=selected(j);P=previews{k};mask=masks{j};
    [~,stem]=fileparts(P.source.name);stem=regexprep(stem,'[^A-Za-z0-9._-]','_');if isempty(stem),stem='data';end
    base=sprintf('%03d_%s_%spercent',k,stem(1:min(80,numel(stem))),number_slug(P.strainAmplitudePercent));bases{j}=base;
    csv=[base '_curves.csv'];
    T=table(P.time(mask),P.strain(mask),100*P.strain(mask),P.strainRate(mask),P.stress(mask), ...
        'VariableNames',{'Time_s','Strain','Strain_percent','StrainRate_per_s','Stress_Pa'});
    writetable(T,fullfile(stage,csv));allFiles{end+1}=csv; %#ok<AGROW>
    r=records(j);r.inputIndex=k;r.sourcePath=P.source.path;r.sourceName=P.source.name;
    r.measuredStrainAmplitudePercent=P.strainAmplitudePercent;r.frequencyHz=P.frequencyHz;
    times=P.time(mask);r.startTime_s=times(1);r.endTime_s=times(end);r.sampleCount=nnz(mask);r.curveCSV=csv;
    r.sourceSignature=P.source.signature;if isfield(P,'options'),r.previewOptions=P.options;end
    if isfield(P,'unit_conversion'),r.unitConversion=P.unit_conversion;end
    records(j)=r;labels{j}=sprintf('%.5g%% | %s',P.strainAmplitudePercent,P.source.name);
end
if strcmp(options.Mode,'overlay')
    figFiles=render_pair(previews(selected),masks,labels,stage,'overlay',options);
    allFiles=[allFiles figFiles];
    for j=1:numel(records),records(j).figures=figFiles;end
else
    for j=1:numel(selected)
        figFiles=render_pair(previews(selected(j)),masks(j),labels(j),stage,bases{j},options);
        records(j).figures=figFiles;allFiles=[allFiles figFiles]; %#ok<AGROW>
    end
end
for k=selected,check_source(previews{k});end
manifest=struct('schemaVersion',1,'application','SMS-LAOS', ...
    'createdUTC',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')), ...
    'outputFolder',folder,'options',options,'inputCount',numel(previews),'matchedCount',numel(selected), ...
    'entries',records,'files',{[allFiles {'manifest.json'}]}, ...
    'notes',{{ ...
    'Only measured files matching the requested strain-amplitude tolerance are included; no interpolation between strain levels.', ...
    'TolerancePercent is an absolute strain-amplitude percentage-point tolerance, not a relative percentage.', ...
    'The file amplitude is the median half peak-to-peak amplitude across complete estimated periods; inspect variable-amplitude records separately.', ...
    'Last N cycles uses a frequency-estimated time window ending at the final measured sample. It is not a phase-aligned cycle average or a stationarity selection.', ...
    'Plots retain the measured DC offsets after shared unit conversion and are not forcibly closed; CSV contains the exact plotted sample arrays.', ...
    'Elastic plot x is measured strain in percent; viscous plot x is gradient(strain,time) in s^-1. Stress is Pa.', ...
    'Numerical strain rate is unsmoothed and may amplify measurement noise.', ...
    'Preview frequency and time windows are independent of the FT/stress-decomposition and SPP method selections.'}});
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

function files=render_pair(previews,masks,labels,folder,base,o)
files={};colors=lines(numel(previews));
for kind={'elastic','viscous'}
    fig=figure('Visible','off','Color','w','Position',[100 100 850 650]);
    c=onCleanup(@()delete(fig));
    ax=axes(fig,'Position',[.14 .17 .8 .73],'FontName','Arial','FontSize',12,'Box','on','LineWidth',1,'NextPlot','add');
    for j=1:numel(previews)
        P=previews{j};mask=masks{j};
        if strcmp(kind{1},'elastic'),x=100*P.strain(mask);else,x=P.strainRate(mask);end
        plot(ax,x,P.stress(mask),'LineWidth',1.4,'Color',colors(j,:),'DisplayName',labels{j});
    end
    if strcmp(kind{1},'elastic'),xlabel(ax,'Strain (%)');title(ax,'Elastic Lissajous');
    else,xlabel(ax,'Strain rate (s^{-1})');title(ax,'Viscous Lissajous');end
    ylabel(ax,'Stress (Pa)');grid(ax,'on');ax.GridAlpha=.12;
    legend(ax,'Location','best','Interpreter','none','FontSize',10);axis(ax,'padded');
    for format={'PNG','PDF','FIG'}
        if ~o.(['Format' format{1}]),continue,end
        filename=[base '_' kind{1} '.' lower(format{1})];path=fullfile(folder,filename);
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
