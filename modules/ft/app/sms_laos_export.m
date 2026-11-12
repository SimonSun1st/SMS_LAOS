function manifest = sms_laos_export(entries, outputFolder, exportOptions, progressCallback)
%SMS_LAOS_EXPORT Export current GUI results without recalculating them.
% Full mode preserves original CSV/XLSX, selected-cycle CSV, curve CSV,
% twelve-panel PNG/FIG and six-panel summary PNG/FIG functionality. Fast mode
% preserves the original result CSV and optional curve CSV behavior.
% Both modes additionally save exact MAT results, settings and a manifest.
% Destination must be absent or empty. Source data are never written.
% Optional progressCallback receives Stage, FileIndex, FileCount, Filename.
% A failing observer is disabled; it cannot change the calculation or save.
if nargin<3, exportOptions=struct(); end
if nargin<4, progressCallback=[]; end
if ~isempty(progressCallback) && ~isa(progressCallback,'function_handle')
    error('SMSApp:ProgressCallback','The progress callback must be a function handle.');
end
progressEnabled=~isempty(progressCallback);
% Explicit FIG MAT versions became public in R2024b. Keep the legacy call
% on older releases; this choice changes serialization, not plotted data.
useV73Figures=~verLessThan('matlab','24.2');
if ~isstruct(exportOptions) || ~isscalar(exportOptions) || ...
        ~all(ismember(fieldnames(exportOptions),{'fast_mode','save_curve_csv'}))
    error('SMSApp:ExportOptions','Export settings may contain only fast_mode and save_curve_csv.');
end
options=sms_laos_validate_options(exportOptions);
exportOptions=struct('fast_mode',options.fast_mode,'save_curve_csv',options.save_curve_csv);
required={'Path','Name','Status','Result','Error','Options'};
if ~isstruct(entries) || isempty(entries) || ~all(isfield(entries,required))
    error('SMSApp:ExportEmpty','No result entries are available to export.');
end
outputFolder=absolute_path(scalar_text(outputFolder));
assert_empty_target(outputFolder);
n=numel(entries);
notify_progress('Checking files',0,n,'');
record=struct('inputIndex',0,'sourcePath','','sourceName','','status','', ...
    'included',false,'exclusionReason','','recordedError','','staleReason','', ...
    'sourceSignature',struct(),'outputBase','','matFile','','selectedCSV','', ...
    'curveCSV','','plotPNG','','plotFIG','');
records=repmat(record,n,1);
included=false(n,1);
for j=1:n
    e=entries(j);
    records(j).inputIndex=j; records(j).sourcePath=char(e.Path);
    records(j).sourceName=char(e.Name); records(j).status=char(e.Status);
    records(j).recordedError=char(string(e.Error));
    if isfield(e,'StaleReason'), records(j).staleReason=char(string(e.StaleReason)); end
    if isfield(e,'SourceSignature'), records(j).sourceSignature=e.SourceSignature; end
    if ~any(strcmp(e.Status,{'ok','warning'}))
        records(j).exclusionReason=['Status is ' char(e.Status) '; only current ok/warning results are exportable.'];
        continue;
    end
    [valid,reason]=validate_result(e.Result);
    if ~valid
        records(j).exclusionReason=['Invalid result: ' reason];
        continue;
    end
    [fresh,reason]=source_is_current(e);
    if ~fresh
        records(j).exclusionReason=['Source is not current: ' reason];
        continue;
    end
    [~,stem]=fileparts(e.Name);
    stem=regexprep(stem,'[^A-Za-z0-9._-]','_');
    if isempty(stem) || all(stem=='.'), stem='result'; end
    stem=stem(1:min(100,numel(stem)));
    base=sprintf('%03d_%s',j,stem);
    records(j).included=true; included(j)=true;
    records(j).outputBase=base;
    records(j).matFile=[base '.mat'];
    if ~options.fast_mode
        records(j).selectedCSV=fullfile('SMS_LAOS_SelectedCSV',[base '_selected_cycles.csv']);
        records(j).plotPNG=fullfile('SMS_LAOS_Plots',[base '_SMS_LAOS.png']);
        records(j).plotFIG=fullfile('SMS_LAOS_Plots',[base '_SMS_LAOS.fig']);
    end
    if options.save_curve_csv
        records(j).curveCSV=fullfile('SMS_LAOS_CurveCSV',[base '_LAOS_decomposed_curves.csv']);
    end
end
if ~any(included)
    error('SMSApp:ExportEmpty','There are no current, structurally valid results. Analyze pending or stale files first.');
end
if ~isfolder(outputFolder)
    [ok,msg]=mkdir(outputFolder);
    if ~ok, error('SMSApp:ExportFolder','Cannot create output folder: %s',msg); end
end
assert_empty_target(outputFolder);
stage=tempname(outputFolder);
[ok,msg]=mkdir(stage);
if ~ok, error('SMSApp:ExportFolder','Cannot create export staging folder: %s',msg); end
cleanup=onCleanup(@() cleanup_stage(stage)); %#ok<NASGU>
if ~options.fast_mode
    mkdir(fullfile(stage,'SMS_LAOS_SelectedCSV'));
    mkdir(fullfile(stage,'SMS_LAOS_Plots'));
end
if options.save_curve_csv, mkdir(fullfile(stage,'SMS_LAOS_CurveCSV')); end
total=sum(included);
snapshots=cell(total,1); qualityRows=cell(total,1);
files=cell(0,1); count=0;
plotState=[]; figureCleanup=[];
for j=find(included)'
    count=count+1; e=entries(j); R=e.Result; rec=records(j);
    notify_progress('Saving MAT',count,total,e.Name);
    save(fullfile(stage,rec.matFile),'R','-v7.3');
    files{end+1,1}=rec.matFile; %#ok<AGROW>
    if ~options.fast_mode || options.save_curve_csv
        [selected,curve]=sms_laos_curve_tables(R);
        if ~options.fast_mode
            notify_progress('Writing selected CSV',count,total,e.Name);
            writetable(selected,fullfile(stage,rec.selectedCSV));
            files{end+1,1}=rec.selectedCSV; %#ok<AGROW>
        end
        if options.save_curve_csv
            notify_progress('Writing curve CSV',count,total,e.Name);
            writetable(curve,fullfile(stage,rec.curveCSV));
            files{end+1,1}=rec.curveCSV; %#ok<AGROW>
        end
    end
    if ~options.fast_mode
        [~,displayName]=fileparts(e.Name);
        notify_progress('Rendering figures',count,total,e.Name);
        plotState=sms_laos_export_plot(plotState,R,displayName,R.settings.cycle_selection_mode);
        if isempty(figureCleanup)
            figureCleanup=onCleanup(@() close_figure(plotState.Figure));
        end
        notify_progress('Saving PNG',count,total,e.Name);
        saveas(plotState.Figure,fullfile(stage,rec.plotPNG));
        notify_progress('Saving FIG',count,total,e.Name);
        save_figure(plotState.Figure,fullfile(stage,rec.plotFIG),useV73Figures);
        files(end+1:end+2,1)={rec.plotPNG;rec.plotFIG};
    end
    snapshots{count}=struct('inputIndex',j,'sourcePath',rec.sourcePath, ...
        'sourceName',rec.sourceName,'settings',R.settings,'source',R.source, ...
        'sourceSignature',rec.sourceSignature,'quality',R.quality);
    qualityRows{count}=struct('InputIndex',j,'Filename',string(rec.sourceName), ...
        'Status',string(rec.status),'ResidualRMS_Pa',R.residual_rms, ...
        'ResidualRMS_over_I1',R.residual_rms_over_I1, ...
        'WarningCount',numel(R.quality.messages), ...
        'Messages',string(strjoin(R.quality.messages,' | ')));
end
clear figureCleanup plotState;
notify_progress('Writing summaries',total,total,'');
results=sms_laos_result_table(entries(included));
if options.fast_mode, resultCSV='SMS_LAOS_results_fast.csv';
else, resultCSV='SMS_LAOS_results_full.csv'; end
writecell(results,fullfile(stage,resultCSV)); files{end+1,1}=resultCSV;
resultExcel=''; summaryPNG=''; summaryFIG='';
if ~options.fast_mode
    resultExcel='SMS_LAOS_results_full.xlsx';
    writecell(results,fullfile(stage,resultExcel)); files{end+1,1}=resultExcel;
    fig=sms_laos_summary_plot_v2(entries(included));
    figCleanup=onCleanup(@() close_figure(fig));
    summaryPNG=fullfile('SMS_LAOS_Plots','SMS_LAOS_summary.png');
    summaryFIG=fullfile('SMS_LAOS_Plots','SMS_LAOS_summary.fig');
    saveas(fig,fullfile(stage,summaryPNG));
    save_figure(fig,fullfile(stage,summaryFIG),useV73Figures);
    clear figCleanup;
    files(end+1:end+2,1)={summaryPNG;summaryFIG};
end
writetable(struct2table(vertcat(qualityRows{:})),fullfile(stage,'quality.csv'));
snapshot=struct('schemaVersion',1,'description','Settings and diagnostics actually saved with each result.', ...
    'exportOptions',exportOptions,'results',{snapshots});
write_json(fullfile(stage,'settings_snapshot.json'),snapshot);
files(end+1:end+2,1)={'quality.csv';'settings_snapshot.json'};
manifest=struct('schemaVersion',1,'application','SMS LAOS MATLAB GUI', ...
    'createdUTC',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')), ...
    'outputFolder',outputFolder,'inputCount',n,'exportedCount',sum(included), ...
    'excludedCount',sum(~included),'exportOptions',exportOptions, ...
    'summaryCSV',resultCSV,'summaryExcel',resultExcel,'summaryPNG',summaryPNG, ...
    'summaryFIG',summaryFIG,'settingsSnapshot','settings_snapshot.json', ...
    'qualityCSV','quality.csv','entries',records,'files',{[files;{'manifest.json'}]}, ...
    'notes',{{ ...
    'Original v2 result columns, curve columns and plotting functions are preserved; no calculation is rerun during export.', ...
    'Only current ok/warning entries are exported. All excluded entries and their status are listed.', ...
    'List-index prefixes prevent collisions between same-name input files.', ...
    'MAT files retain complete numerical arrays and exact NaN/Inf states; CSV/XLSX handling of non-finite values follows MATLAB writers.', ...
    'Full-mode FIG files use MAT-file v7.3 on R2024b and later, and the default FIG format on earlier releases; plotted numerical data are unchanged.', ...
    'Source path, file size and modification time were checked before export; metadata checks are not content hashes.', ...
    'Numerical agreement with the original script does not establish physical validity or steady state.'}});
write_json(fullfile(stage,'manifest.json'),manifest);
notify_progress('Publishing',total,total,'');
% Progress callbacks yield to the UI. Recheck provenance after the final
% yield, before exposing any result file, so mid-export changes cannot pass.
for j=find(included)'
    [fresh,reason]=source_is_current(entries(j));
    if ~fresh
        error('SMSApp:SourceChanged','The source changed during export: %s (%s).',entries(j).Name,reason);
    end
end
% Publish directories and data first, and the manifest only after success.
listing=dir(stage); listing=listing(~ismember({listing.name},{'.','..','manifest.json'}));
for j=1:numel(listing)
    publish(fullfile(stage,listing(j).name),fullfile(outputFolder,listing(j).name));
end
publish(fullfile(stage,'manifest.json'),fullfile(outputFolder,'manifest.json'));
notify_progress('Complete',total,total,'');

    function notify_progress(stageName,index,fileCount,filename)
        if ~progressEnabled, return; end
        event=struct('Stage',char(stageName),'FileIndex',index, ...
            'FileCount',fileCount,'Filename',char(filename));
        try
            progressCallback(event);
        catch ME
            progressEnabled=false;
            warning('SMSApp:ProgressCallback','Export progress updates were disabled: %s',ME.message);
        end
    end
end

function [valid,reason]=validate_result(R)
valid=false; reason='Expected a scalar structure with all original output fields.';
required={'time','strain','gammadot','gammadot_over_omega','stress','stress_elastic', ...
    'stress_viscous','stress_reconstructed','stress_residual','x_cheb','y_cheb', ...
    'freq_hz','omega','n_cycles_used','I1','I3','I3_I1','delta1','delta3', ...
    'Gp1','Gpp1','Gp3','Gpp3','e1','v1','e3','v3','e3_e1','v3_v1', ...
    'G_M_prime','G_L_prime','S','eta_M_prime','eta_L_prime','T', ...
    'residual_rms','residual_rms_over_I1','settings','quality','source'};
if ~isstruct(R) || ~isscalar(R) || ~all(isfield(R,required)), return; end
if ~isstruct(R.settings) || ~isfield(R.settings,'cycle_selection_mode') || ...
        ~isstruct(R.quality) || ~isfield(R.quality,'messages')
    reason='Missing result settings or quality messages.'; return;
end
if isempty(R.time) || ~isnumeric(R.time) || ~isvector(R.time)
    reason='Result time vector is empty or invalid.'; return;
end
arrays={'strain','gammadot','gammadot_over_omega','stress','stress_elastic', ...
    'stress_viscous','stress_reconstructed','stress_residual','x_cheb','y_cheb'};
for k=1:numel(arrays)
    if ~isnumeric(R.(arrays{k})) || ~isvector(R.(arrays{k})) || numel(R.(arrays{k}))~=numel(R.time)
        reason=['Inconsistent result vector: ' arrays{k}]; return;
    end
end
valid=true; reason='';
end

function [fresh,reason]=source_is_current(entry)
% Public export calls require the same freshness guard as the GUI. Always
% compare against provenance saved with R, not a mutable entry signature.
fresh=false; reason='The saved result has no complete source provenance.';
source=entry.Result.source;
if ~isstruct(source) || ~isscalar(source) || ~all(isfield(source,{'path','bytes','datenum'}))
    return;
end
if ~(ischar(source.path) && isrow(source.path)) && ...
        ~(isstring(source.path) && isscalar(source.path))
    reason='The saved source path is invalid.'; return;
end
if ~isnumeric(source.bytes) || ~isscalar(source.bytes) || ~isfinite(source.bytes) || ...
        ~isnumeric(source.datenum) || ~isscalar(source.datenum) || ~isfinite(source.datenum)
    reason='The saved source metadata are invalid.'; return;
end
try
    entryPath=canonical_file_path(entry.Path);
    resultPath=canonical_file_path(source.path);
catch ME
    reason=ME.message; return;
end
if ispc, samePath=strcmpi(entryPath,resultPath);
else, samePath=strcmp(entryPath,resultPath); end
if ~samePath
    reason='The entry path does not match the source path saved with its result.'; return;
end
current=dir(entryPath);
if numel(current)~=1 || current.isdir
    reason='The source file is missing or inaccessible.'; return;
end
if current.bytes~=source.bytes || current.datenum~=source.datenum
    reason='The source file size or modification time changed after analysis.'; return;
end
fresh=true; reason='';
end

function path=canonical_file_path(path)
if ~(ischar(path) && isrow(path)) && ~(isstring(path) && isscalar(path))
    error('SMSApp:ExportSource','The source path is invalid.');
end
path=char(path);
if ~isfile(path), error('SMSApp:ExportSource','The source file is missing or inaccessible: %s',path); end
[ok,attributes]=fileattrib(path);
if ~ok, error('SMSApp:ExportSource','The source file cannot be inspected: %s',path); end
path=attributes.Name;
% Normalize relative components and symlinks where a JVM is available. The
% GUI already requires a graphics-capable MATLAB session; the fallback also
% supports this exporter from a MATLAB session started without a JVM.
if usejava('jvm')
    file=java.io.File(path);
    path=char(file.getCanonicalPath());
end
end

function value=scalar_text(value)
if ~(ischar(value) && isrow(value)) && ~(isstring(value) && isscalar(value))
    error('SMSApp:ExportFolder','Output folder must be scalar text.');
end
value=char(value);
if isempty(strtrim(value)), error('SMSApp:ExportFolder','Choose an output folder.'); end
end

function p=absolute_path(p)
if ispc
    absolute=~isempty(regexp(p,'^[A-Za-z]:[\\/]|^[\\/]{2}','once'));
else
    absolute=startsWith(p,filesep);
end
if ~absolute, p=fullfile(pwd,p); end
end

function assert_empty_target(folder)
if exist(folder,'file')~=0 && ~isfolder(folder)
    error('SMSApp:ExportExists','The output path exists and is not a folder.');
end
if isfolder(folder)
    items=dir(folder); items=items(~ismember({items.name},{'.','..'}));
    if ~isempty(items)
        error('SMSApp:ExportExists','Output folder is not empty. Choose a new folder; existing files will not be overwritten.');
    end
end
end

function publish(source,target)
if exist(target,'file')~=0 || isfolder(target)
    error('SMSApp:ExportExists','A destination appeared during export and was not overwritten: %s',target);
end
[ok,msg]=movefile(source,target);
if ~ok, error('SMSApp:ExportWrite','Cannot publish output: %s',msg); end
end

function write_json(path,value)
[fid,msg]=fopen(path,'w','n','UTF-8');
if fid<0, error('SMSApp:ExportWrite','Cannot write %s: %s',path,msg); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
text=jsonencode(value,'PrettyPrint',true);
if fprintf(fid,'%s\n',text)<0, error('SMSApp:ExportWrite','Failed writing JSON: %s',path); end
end

function close_figure(fig)
if isgraphics(fig), close(fig); end
end

function save_figure(fig,path,useV73)
if useV73
    savefig(fig,path,'-v7.3');
else
    savefig(fig,path);
end
end

function cleanup_stage(stage)
if isfolder(stage), rmdir(stage,'s'); end
end
