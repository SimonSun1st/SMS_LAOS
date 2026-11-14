function manifest = SMS_LAOS_app_export_SPP_v5(entries, outputFolder, progress)
%SMS_LAOS_APP_EXPORT_SPP_V5 Export current averaged or evolving responses, without reruns.
% Writes complete MAT results, cycle/harmonic CSVs, available average/continuous
% phase CSVs, sensitivity CSVs, settings and a manifest. A warning result with
% no stable average remains exportable as diagnostics. Never overwrites files.
% Optional progress(fraction,message) may throw to cancel before publishing.
if nargin<3,progress=[];end
if ~isempty(progress)&&~isa(progress,'function_handle'),error('SPPApp:ExportProgress','Progress must be a function handle.');end
required={'Path','Name','Status','Result','Error','Options'};
if ~isstruct(entries)||isempty(entries)||~all(isfield(entries,required))
    error('SPPApp:ExportEmpty','Supply nonempty analysis entries.');
end
outputFolder=absolute_path(char(outputFolder)); assert_empty(outputFolder);
n=numel(entries);
template=struct('inputIndex',0,'sourcePath','','sourceName','','status','', ...
    'included',false,'exclusionReason','','recordedError','','outputBase','', ...
    'matFile','','cycleCSV','','harmonicsCSV','','phaseCSV','','evolutionPhaseCSV','', ...
    'sensitivityCSV','','sourceSignature',struct(),'staleReason','');
records=repmat(template,n,1); included=false(n,1);sensitivity=cell(n,1);
for j=1:n
    notify(.05*(j-1)/n,sprintf('Checking SPP file %d of %d · %s',j,n,entries(j).Name));
    e=entries(j); r=template; r.inputIndex=j; r.sourcePath=absolute_path(char(e.Path));
    r.sourceName=char(e.Name); r.status=char(e.Status); r.recordedError=char(string(e.Error));
    if isfield(e,'SourceSignature'), r.sourceSignature=e.SourceSignature; end
    if isfield(e,'StaleReason'), r.staleReason=char(e.StaleReason); end
    if ~ismember(r.status,{'ok','warning'})
        r.exclusionReason=['Status is ' r.status '; reanalyze before exporting.'];
    else
        [valid,reason]=valid_result(e.Result);
        if ~valid, r.exclusionReason=reason;
        else
            [~,stem]=fileparts(r.sourceName); stem=regexprep(stem,'[^A-Za-z0-9._-]','_');
            if isempty(stem), stem='result'; end
            r.outputBase=sprintf('%03d_%s',j,stem(1:min(100,numel(stem))));
            r.matFile=[r.outputBase '.mat']; r.cycleCSV=[r.outputBase '_cycles.csv'];
            r.harmonicsCSV=[r.outputBase '_harmonics.csv'];
            if ~isempty(e.Result.average), r.phaseCSV=[r.outputBase '_average_phase.csv']; end
            if ~isempty(e.Result.evolution.Gt_storage), r.evolutionPhaseCSV=[r.outputBase '_evolution_phase.csv']; end
            sensitivity{j}=sensitivity_table(e.Result);
            if ~isempty(sensitivity{j}), r.sensitivityCSV=[r.outputBase '_sensitivity.csv']; end
            r.included=true; included(j)=true;
        end
    end
    records(j)=r;
end
if ~any(included), error('SPPApp:ExportEmpty','No current valid results are available; analyze pending or stale entries first.'); end
if ~isfolder(outputFolder), [ok,msg]=mkdir(outputFolder); if ~ok,error('SPPApp:ExportFolder','%s',msg);end,end
assert_empty(outputFolder); stage=tempname(outputFolder); mkdir(stage);
cleanup=onCleanup(@() cleanup_stage(stage)); %#ok<NASGU>
files={}; rows={}; snapshots={}; allcycles={}; allharmonics={};
rowsToWrite=find(included);total=numel(rowsToWrite);
for k=1:total
    j=rowsToWrite(k);R=entries(j).Result;rec=records(j);
    fileMessage=sprintf('%d of %d · %s',k,total,rec.sourceName);
    notify(.05+.84*(k-1)/total,['SPP result · ' fileMessage]);
    save(fullfile(stage,rec.matFile),'R','-v7.3');
    notify(.05+.84*(k-.7)/total,['SPP tables · ' fileMessage]);
    write_csv(R.evolution.cycle_table,fullfile(stage,rec.cycleCSV));
    write_csv(R.evolution.harmonics,fullfile(stage,rec.harmonicsCSV));
    files=[files;{rec.matFile;rec.cycleCSV;rec.harmonicsCSV}]; %#ok<AGROW>
    T=R.evolution.cycle_table;
    allcycles{end+1}=with_source(T,rec); %#ok<AGROW>
    allharmonics{end+1}=with_source(R.evolution.harmonics,rec); %#ok<AGROW>
    if ~isempty(rec.phaseCSV)
        write_csv(average_phase(R.average),fullfile(stage,rec.phaseCSV)); files{end+1,1}=rec.phaseCSV;
    end
    if ~isempty(rec.evolutionPhaseCSV)
        notify(.05+.84*(k-.4)/total,['SPP evolution · ' fileMessage]);
        write_csv(evolution_phase(R),fullfile(stage,rec.evolutionPhaseCSV)); files{end+1,1}=rec.evolutionPhaseCSV;
    end
    if ~isempty(rec.sensitivityCSV)
        notify(.05+.84*(k-.2)/total,['SPP sensitivity · ' fileMessage]);
        write_csv(sensitivity{j},fullfile(stage,rec.sensitivityCSV)); files{end+1,1}=rec.sensitivityCSV;
    end
    rows{end+1}=struct('InputIndex',j,'SourcePath',string(rec.sourcePath),'SourceName',string(rec.sourceName), ...
        'AnalysisMode',string(R.analysis_mode),'Status',string(rec.status), ...
        'Omega_rad_s',R.omega,'StrainAmplitudePercent',median(T.StrainPercent,'omitnan'), ...
        'AvailableCycles',height(T),'AnalyzedCycles',numel(R.selection.analyzed_cycles), ...
        'AverageAvailable',~isempty(R.average),'AverageCycleNumbers',string(mat2str(R.selection.average_cycles)), ...
        'StationarityScreenPassed',logical(R.selection.stationarity_pass), ...
        'SelectionStatus',string(R.selection.status),'QualityWarningCount',numel(R.quality.messages), ...
        'Messages',strjoin(string(R.quality.messages),' | '),'MATFile',string(rec.matFile), ...
        'CycleCSV',string(rec.cycleCSV),'HarmonicsCSV',string(rec.harmonicsCSV), ...
        'AveragePhaseCSV',string(rec.phaseCSV),'EvolutionPhaseCSV',string(rec.evolutionPhaseCSV)); %#ok<AGROW>
    snapshots{end+1}=struct('inputIndex',j,'sourcePath',rec.sourcePath, ...
        'settings',R.settings,'selection',json_safe(R.selection),'sourceSignature',rec.sourceSignature); %#ok<AGROW>
end
notify(.90,'Writing SPP batch summaries');
write_csv(struct2table(vertcat(rows{:})),fullfile(stage,'summary.csv'));
write_csv(vertcat(allcycles{:}),fullfile(stage,'cycles_all_files.csv'));
write_csv(vertcat(allharmonics{:}),fullfile(stage,'harmonics_all_files.csv'));
write_json(fullfile(stage,'settings_snapshot.json'),struct('schemaVersion',5,'results',{snapshots}));
manifest=struct('schemaVersion',5,'application','SPP LAOS v5', ...
    'createdUTC',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')), ...
    'outputFolder',outputFolder,'inputCount',n,'exportedCount',sum(included),'excludedCount',sum(~included), ...
    'summaryCSV','summary.csv','cyclesCSV','cycles_all_files.csv','harmonicsCSV','harmonics_all_files.csv', ...
    'settingsSnapshot','settings_snapshot.json','entries',records, ...
    'notes',{{'Current ok/warning entries only. No-stable-average results export diagnostics without an invented average.', ...
    'MAT files retain exact results and all phase-aligned waveforms. Original acquisition files remain the raw-data archive.', ...
    'CSV strain is dimensionless; stress/moduli are Pa; cycle work is mechanical input work in J/m^3, not necessarily heat.', ...
    'ElapsedTime_s is relative to the first valid cycle of each file, not a common loading-onset time across files.', ...
    'CycleIndex numbers valid detected cycles. OriginalCycleLabel retains missing-cycle spacing.', ...
    'Non-finite numeric CSV entries are blank. Valid/Included/InAverage fields specify applicability.', ...
    'Continuous evolution SPP does not wrap cycle ends; insufficient-support edges are masked.', ...
    'Cycle Fourier coefficients describe each observed interval; evolving intervals need not be steady nonlinear harmonics.', ...
    'Stable repeats and numerical validity do not establish material origin, statistical confidence or a unique relaxation time.', ...
    'File signatures are recorded size/time metadata only. The GUI checks them before export; these are not content hashes.'}});
write_json(fullfile(stage,'manifest.json'),manifest);
files=[files;{'summary.csv';'cycles_all_files.csv';'harmonics_all_files.csv';'settings_snapshot.json';'manifest.json'}];
notify(1,'Publishing SPP files');
for j=1:numel(files)
    target=fullfile(outputFolder,files{j});
    if exist(target,'file')~=0,error('SPPApp:ExportExists','Destination appeared during export: %s',target);end
    [ok,msg]=movefile(fullfile(stage,files{j}),target);
    if ~ok,error('SPPApp:ExportWrite','Cannot publish %s: %s',files{j},msg);end
end
    function notify(fraction,message)
        if ~isempty(progress),progress(fraction,message);end
    end
end

function [ok,reason]=valid_result(R)
ok=false; reason='Expected a complete v5 result.';
if ~isstruct(R)||~isscalar(R)||~all(isfield(R,{'analysis_mode','settings','omega','average','evolution','selection','quality'})),return,end
if ~isscalar(R.omega)||~isfinite(R.omega)||R.omega<=0,reason='Invalid frequency.';return,end
e=R.evolution;
if ~isstruct(e)||~all(isfield(e,{'cycle_table','harmonics','phase','gamma','sigma','time','Gt_storage','Gt_loss','valid'})),return,end
if ~istable(e.cycle_table)||isempty(e.cycle_table)||~istable(e.harmonics),return,end
names={'CycleIndex','OriginalCycleLabel','StartTime_s','StrainPercent','Included','InAverage'};
if ~all(ismember(names,e.cycle_table.Properties.VariableNames)),return,end
sz=[numel(e.phase),height(e.cycle_table)];
if ~isequal(size(e.gamma),sz)||~isequal(size(e.sigma),sz)||~isequal(size(e.time),sz),reason='Waveform dimensions do not match cycles.';return,end
if ~isempty(e.Gt_storage)&&(~isequal(size(e.Gt_storage),sz)||~isequal(size(e.Gt_loss),sz)||~isequal(size(e.valid),sz))
    reason='Evolution SPP dimensions do not match cycles.';return
end
if ~isstruct(R.selection)||~all(isfield(R.selection,{'analyzed_cycles','average_cycles','stationarity_pass','status'})),return,end
if ~isstruct(R.quality)||~isfield(R.quality,'messages'),return,end
if ~isempty(R.average)&&(~isstruct(R.average)||~all(isfield(R.average,{'proc','Gt_storage','Gt_loss','sigma_d'}))),return,end
ok=true;reason='';
end

function T=with_source(T,rec)
T.InputIndex=repmat(rec.inputIndex,height(T),1);
T.SourceName=repmat(string(rec.sourceName),height(T),1);
T.SourcePath=repmat(string(rec.sourcePath),height(T),1);
T=movevars(T,{'InputIndex','SourceName','SourcePath'},'Before',1);
end

function T=average_phase(A)
p=A.proc;
T=table(p.t(:),p.phase(:),p.gamma(:),p.gammadot(:),p.x(:),p.sigma(:), ...
    A.Gt_storage(:),A.Gt_loss(:),A.sigma_d(:),logical(p.mask_valid(:)), ...
    p.fit_condition(:),p.fit_residual_rms(:),p.center_reconstruction_residual(:), ...
    'VariableNames',{'Time_s','Phase_rad','Strain','StrainRate_per_s','StrainRate_over_Omega', ...
    'Stress_Pa','GtStorage_Pa','GtLoss_Pa','DisplacementStress_Pa','Valid', ...
    'ScaledDesignCondition','FitResidualRMS_Pa','CenterReconstructionResidual_Pa'});
T.StrainCycleSD=A.analysis_cycle.gamma_std(:); T.StressCycleSD_Pa=A.analysis_cycle.sigma_std(:);
end

function T=evolution_phase(R)
e=R.evolution; c=e.cycle_table; N=numel(e.phase); C=height(c);
T=table(repelem(c.CycleIndex,N),repelem(c.OriginalCycleLabel,N), ...
    repmat(e.phase(:),C,1),e.time(:),e.time(:)-c.StartTime_s(1), ...
    e.gamma(:),e.sigma(:),e.Gt_storage(:),e.Gt_loss(:),logical(e.valid(:)), ...
    repelem(logical(c.Included),N),repelem(logical(c.InAverage),N), ...
    'VariableNames',{'CycleIndex','OriginalCycleLabel','Phase_rad','Time_s','ElapsedTime_s', ...
    'Strain','Stress_Pa','GtStorage_Pa','GtLoss_Pa','ValidSPP','Included','InAverage'});
for pair={'sigma_d','DisplacementStress_Pa';'fit_condition','ScaledDesignCondition';'fit_residual_rms','FitResidualRMS_Pa'}'
    if isfield(e,pair{1})&&isequal(size(e.(pair{1})),[N C]),T.(pair{2})=reshape(e.(pair{1}),[],1);end
end
end

function T=sensitivity_table(R)
T=table(); if isempty(R.average),return,end
A=R.average; series={}; kinds={};
if isfield(A.proc,'window_sensitivity'),series{end+1}=A.proc.window_sensitivity;kinds{end+1}='Fit half-window';end
for k=1:numel(series)
    s=series{k};
    for j=1:numel(s)
        if ~all(isfield(s(j),{'Gt_storage','Gt_loss'})),continue,end
        n=numel(s(j).Gt_storage); fraction=NaN; count=NaN;
        if isfield(s(j),'fraction'),fraction=s(j).fraction;end
        if isfield(s(j),'half_window'),count=s(j).half_window;end
        if isfield(s(j),'window'),count=s(j).window;end
        part=table(repmat(string(kinds{k}),n,1),repmat(count,n,1),repmat(fraction,n,1), ...
            A.proc.phase(:),s(j).Gt_storage(:),s(j).Gt_loss(:), ...
            'VariableNames',{'Variation','WindowPoints','WindowFraction','Phase_rad','GtStorage_Pa','GtLoss_Pa'});
        T=[T;part]; %#ok<AGROW>
    end
end
if isfield(R,'smoothing_sensitivity') && isstruct(R.smoothing_sensitivity) && ...
        isfield(R.smoothing_sensitivity,'windows')
    s=R.smoothing_sensitivity; n=numel(s.phase);
    for j=1:numel(s.windows)
        part=table(repmat("Smoothing full-window",n,1),repmat(s.windows(j),n,1), ...
            repmat(s.fractions(j),n,1),s.phase(:),s.Gt_storage(:,j),s.Gt_loss(:,j), ...
            'VariableNames',{'Variation','WindowPoints','WindowFraction','Phase_rad','GtStorage_Pa','GtLoss_Pa'});
        T=[T;part]; %#ok<AGROW>
    end
end
end

function v=json_safe(v)
if istable(v),v=table2struct(v);end
if isstruct(v)
    for j=1:numel(v),for n=fieldnames(v)',v(j).(n{1})=json_safe(v(j).(n{1}));end,end
elseif iscell(v)
    for j=1:numel(v),v{j}=json_safe(v{j});end
end
end

function write_csv(T,path)
for n=T.Properties.VariableNames
    x=T.(n{1});
    if isnumeric(x)||islogical(x)
        y=strings(size(x));good=isfinite(x);y(good)=compose('%.17g',double(x(good)));T.(n{1})=y;
    end
end
writetable(T,path);
end

function write_json(path,v)
fid=fopen(path,'wt','n','UTF-8');if fid<0,error('SPPApp:ExportWrite','Cannot write %s',path);end
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(json_safe(v),'PrettyPrint',true));
end

function p=absolute_path(p)
if isempty(strtrim(p)),error('SPPApp:ExportFolder','An output/source path is empty.');end
if ~startsWith(p,filesep)&&isempty(regexp(p,'^[A-Za-z]:[\\/]|^\\\\','once')),p=fullfile(pwd,p);end
end

function assert_empty(folder)
if isfolder(folder)
    d=dir(folder);if any(~ismember({d.name},{'.','..'})),error('SPPApp:ExportExists','Choose a new or completely empty output folder. Nothing was overwritten.');end
elseif exist(folder,'file')~=0,error('SPPApp:ExportExists','Output path already exists as a file.');end
end

function cleanup_stage(folder)
if isfolder(folder),try,rmdir(folder,'s');catch,end,end
end
