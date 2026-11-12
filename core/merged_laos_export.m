function manifest=merged_laos_export(entries,ftEntries,varargin)
%MERGED_LAOS_EXPORT Export requested, current analyses without rerunning.
% Native SMS/SPP exports retain their original numerical result structures.
if numel(varargin)==4
    sdEntries=varargin{1};sppEntries=varargin{2};folder=varargin{3};options=varargin{4};
elseif numel(varargin)==3
    % Compatibility with archived first-release validation scripts.
    sdEntries=ftEntries;sppEntries=varargin{1};folder=varargin{2};options=varargin{3};
else,error('MergedLAOS:ExportArguments','Supply separate FT, SD and SPP entries, output folder and options.');end
if isempty(entries),error('MergedLAOS:ExportEmpty','Load data before exporting.');end
if numel(entries)~=numel(ftEntries)||numel(entries)~=numel(sdEntries)||numel(entries)~=numel(sppEntries)
    error('MergedLAOS:ExportEntries','The shared file list and method results do not match.');
end
folder=absolute_path(char(folder));assert_empty(folder);
parent=fileparts(folder);if ~isfolder(parent),mkdir(parent);end
stage=tempname(parent);mkdir(stage);cleanup=onCleanup(@()cleanup_stage(stage)); %#ok<NASGU>
n=numel(entries);m=options.Methods;records=repmat(struct( ...
    'inputIndex',0,'sourcePath','','sourceName','','previewStatus','','previewError','', ...
    'measuredStrainAmplitudePercent',NaN,'previewFrequencyHz',NaN, ...
    'FTStatus','','StressStatus','','SPPStatus','','FTError','','StressError','','SPPError','', ...
    'FTIncluded',false,'StressIncluded',false,'SPPIncluded',false,'waveformCSV',''),n,1);
ftInclude=false(1,n);sdInclude=false(1,n);spInclude=false(1,n);previews={};sources={};
for k=1:n
    e=entries(k);f=ftEntries(k);d=sdEntries(k);s=sppEntries(k);r=records(k);
    if ~strcmp(e.Path,f.Path)||~strcmp(e.Path,d.Path)||~strcmp(e.Path,s.Path),error('MergedLAOS:ExportEntries','Input order does not match method entries.');end
    r.inputIndex=k;r.sourcePath=e.Path;r.sourceName=e.Name;r.previewError=e.PreviewError;
    r.FTStatus=f.Status;r.StressStatus=d.Status;r.SPPStatus=s.Status;r.FTError=f.Error;r.StressError=d.Error;r.SPPError=s.Error;
    if ~e.FTDone&&ismember(f.Status,{'ok','warning'}),r.FTStatus='not run';end
    if ~e.StressDone&&ismember(d.Status,{'ok','warning'}),r.StressStatus='not run';end
    freshF=is_current(f);freshD=is_current(d);freshS=is_current(s);
    if ismember(f.Status,{'ok','warning'})&&~freshF,r.FTStatus='source changed';end
    if ismember(d.Status,{'ok','warning'})&&~freshD,r.StressStatus='source changed';end
    if ismember(s.Status,{'ok','warning'})&&~freshS,r.SPPStatus='source changed';end
    ftInclude(k)=m.FT&&e.FTDone&&freshF;
    sdInclude(k)=m.Stress&&e.StressDone&&freshD;
    spInclude(k)=m.SPP&&freshS;
    r.FTIncluded=ftInclude(k);r.StressIncluded=sdInclude(k);r.SPPIncluded=spInclude(k);
    P=e.Preview;r.previewStatus='unavailable';
    if ~isempty(P)
        r.measuredStrainAmplitudePercent=P.strainAmplitudePercent;r.previewFrequencyHz=P.frequencyHz;
        if merged_laos_source_current(P.source)
            r.previewStatus='current';previews{end+1}=P; %#ok<AGROW>
            if options.IncludeWaveforms
                if ~isfolder(fullfile(stage,'Waveforms')),mkdir(fullfile(stage,'Waveforms'));end
                base=safe_base(k,e.Name);r.waveformCSV=fullfile('Waveforms',[base '_waveforms.csv']);
                T=table(P.time,P.strain,100*P.strain,P.strainRate,P.stress, ...
                    'VariableNames',{'Time_s','Strain','Strain_percent','StrainRate_per_s','Stress_Pa'});
                writetable(T,fullfile(stage,r.waveformCSV));sources{end+1}=P.source; %#ok<AGROW>
            end
        else,r.previewStatus='source changed';end
    end
    if ftInclude(k),sources{end+1}=entry_source(f);end %#ok<AGROW>
    if sdInclude(k),sources{end+1}=entry_source(d);end %#ok<AGROW>
    if spInclude(k),sources{end+1}=entry_source(s);end %#ok<AGROW>
    records(k)=r;
end
if ~any(ftInclude|sdInclude|spInclude)&&~(options.IncludeWaveforms&&~isempty(sources))&&~options.IncludeLissajous
    error('MergedLAOS:ExportEmpty','No current results for the checked methods. Analyze first, or enable a waveform / Lissajous export.');
end
modules=struct();
if any(ftInclude)
    out=fullfile(stage,'FT_LAOS');mkdir(out);
    modules.FT=export_ft(ftEntries,ftInclude,out);
end
if any(sdInclude)
    exportEntries=exclude_entries(sdEntries,sdInclude);
    if isfield(options,'SDOptions'),settings=options.SDOptions;else,settings=options.FTOptions;end
    eo=struct('fast_mode',settings.fast_mode,'save_curve_csv',settings.save_curve_csv);
    modules.Stress=sms_laos_export(exportEntries,fullfile(stage,'Stress_decomposition'),eo);
end
if any(spInclude)
    exportEntries=exclude_entries(sppEntries,spInclude);
    modules.SPP=spp_app_export_v5(exportEntries,fullfile(stage,'SPP'));
end
if options.IncludeLissajous
    modules.Lissajous=merged_laos_export_lissajous(previews,fullfile(stage,'Lissajous'),options.Lissajous);
    for k=1:numel(previews)
        if isempty(options.Lissajous.TargetStrainPercent)||any(abs(previews{k}.strainAmplitudePercent-options.Lissajous.TargetStrainPercent(:))<=options.Lissajous.TolerancePercent)
            sources{end+1}=previews{k}.source; %#ok<AGROW>
        end
    end
end
for k=1:numel(sources)
    if ~merged_laos_source_current(sources{k}),error('MergedLAOS:SourceChanged','A source changed during export: %s. Export again after reanalysis.',sources{k}.path);end
end
T=struct2table(records,'AsArray',true);writetable(T,fullfile(stage,'analysis_status.csv'));
previewSnapshots=cellfun(@preview_snapshot,previews,'UniformOutput',false);
methodSnapshots=struct('FT',{input_snapshots(ftEntries,ftInclude)},'Stress',{input_snapshots(sdEntries,sdInclude)},'SPP',{input_snapshots(sppEntries,spInclude)});
write_json(fullfile(stage,'settings_snapshot.json'),struct('exportOptions',options,'previews',{previewSnapshots},'methods',methodSnapshots));
manifest=struct('schemaVersion',2,'application','SMS-LAOS', ...
    'createdUTC',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')), ...
    'outputFolder',folder,'methodsRequested',m,'inputCount',n, ...
    'exportedFTCount',sum(ftInclude),'exportedStressCount',sum(sdInclude),'exportedSPPCount',sum(spInclude), ...
    'entries',records,'modules',modules,'statusCSV','analysis_status.csv','settingsSnapshot','settings_snapshot.json', ...
    'notes',{{'Only requested methods with current successful results are exported. Pending, stale and failed methods remain listed in analysis_status.csv.', ...
    'FT-LAOS and stress decomposition have independent settings, runs and results, using the unchanged SMS v2 calculation. The native stress export contains supporting Fourier quantities.', ...
    'Input time, strain and stress are converted to seconds, decimal strain and Pa. Original input units and conversion factors are retained in MAT results and settings snapshots.', ...
    'FT harmonic tables report orders 1 and 3 using the original v2 sign convention; S/T and reconstruction are not arbitrary-order estimates.', ...
    'SPP uses the measured input directly, including even and higher components; no SMS reconstructed stress is passed to SPP.', ...
    'Preview strain rate uses gradient(strain,time). The analysis engines retain their own derivatives, frequency estimates and selected cycles.', ...
    'A stable-tail failure exports SPP diagnostics without fabricating an average curve.', ...
    'File freshness is checked using size and modification time, not content hashes.'}});
manifest=remap_folders(manifest,stage,folder);write_json(fullfile(stage,'manifest.json'),manifest);
% Sub-exporters wrote staging paths. Publish manifests with the real location.
jsons=dir(fullfile(stage,'**','manifest.json'));
for k=1:numel(jsons)
    path=fullfile(jsons(k).folder,jsons(k).name);
    value=jsondecode(fileread(path));write_json(path,remap_folders(value,stage,folder));
end
assert_empty(folder);if ~isfolder(folder),mkdir(folder);end
files=dir(stage);files=files(~ismember({files.name},{'.','..'}));
% A manifest is a completion marker: publish it after every required file.
files=[files(~strcmp({files.name},'manifest.json'));files(strcmp({files.name},'manifest.json'))];
for k=1:numel(files)
    target=fullfile(folder,files(k).name);
    if exist(target,'file')~=0,error('MergedLAOS:ExportExists','Destination appeared during export: %s',target);end
    [ok,msg]=movefile(fullfile(stage,files(k).name),target);
    if ~ok,error('MergedLAOS:ExportWrite','Cannot publish output: %s',msg);end
end
end

function m=export_ft(entries,included,out)
summary={};files={};
for k=find(included)
    e=entries(k);R=e.Result;base=safe_base(k,e.Name);
    names={'freq_hz','omega','n_cycles_used','I1','I3','I3_I1','delta1','delta3','Gp1','Gpp1','Gp3','Gpp3', ...
        'freqs_plot','strain_amp_plot','stress_amp_plot','settings','source','quality'};
    FT=struct();for j=1:numel(names),FT.(names{j})=R.(names{j});end
    for name={'input_settings','unit_conversion'},if isfield(R,name{1}),FT.(name{1})=R.(name{1});end,end
    % Keep the exact backend snapshot as well as the focused FT report.
    save(fullfile(out,[base '.mat']),'FT','R','-v7.3');
    H=table([1;3],[R.I1;R.I3],[1;R.I3_I1],[R.delta1;R.delta3],[R.Gp1;R.Gp3],[R.Gpp1;R.Gpp3], ...
        'VariableNames',{'HarmonicOrder','Amplitude_Pa','AmplitudeOverI1','Phase_rad','GStorage_Pa','GLoss_Pa'});
    writetable(H,fullfile(out,[base '_harmonics.csv']));
    S=table(R.freqs_plot(:),R.strain_amp_plot(:),R.stress_amp_plot(:), ...
        'VariableNames',{'Frequency_Hz','StrainAmplitude','StressAmplitude_Pa'});
    writetable(S,fullfile(out,[base '_spectra.csv']));
    summary{end+1}=table(k,string(e.Path),string(e.Name),R.freq_hz,R.omega,R.n_cycles_used,R.I1,R.I3,R.I3_I1, ...
        R.Gp1,R.Gpp1,R.Gp3,R.Gpp3,'VariableNames',{'InputIndex','SourcePath','SourceName','Frequency_Hz','Omega_rad_s', ...
        'SelectedCycles','I1_Pa','I3_Pa','I3OverI1','G1Storage_Pa','G1Loss_Pa','G3Storage_Pa','G3Loss_Pa'}); %#ok<AGROW>
    files=[files {[base '.mat'],[base '_harmonics.csv'],[base '_spectra.csv']}]; %#ok<AGROW>
end
writetable(vertcat(summary{:}),fullfile(out,'summary.csv'));
m=struct('application','FT-LAOS (SMS v2)','outputFolder',out,'exportedCount',sum(included), ...
    'summaryCSV','summary.csv','files',{[files {'summary.csv','manifest.json'}]});write_json(fullfile(out,'manifest.json'),m);
end
function e=exclude_entries(e,included)
for k=find(~included),e(k).Status='excluded';end
end
function snapshots=input_snapshots(entries,included)
snapshots={};
for k=find(included)
    R=entries(k).Result;s=struct('inputIndex',k,'sourcePath',entries(k).Path,'analysisSettings',entries(k).Options);
    if isfield(R,'input_settings'),s.inputSettings=R.input_settings;end
    if isfield(R,'unit_conversion'),s.unitConversion=R.unit_conversion;end
    snapshots{end+1}=s; %#ok<AGROW>
end
end
function s=preview_snapshot(P)
s=struct('source',P.source,'options',P.options, ...
    'frequencyEstimate',rmfield(P.frequencyEstimate,{'fftFrequencyHz','fftAmplitude'}), ...
    'amplitudeMethod',P.amplitudeMethod,'quality',P.quality);
if isfield(P,'unit_conversion'),s.unitConversion=P.unit_conversion;end
end
function current=is_current(e)
current=~isempty(e.Result)&&ismember(e.Status,{'ok','warning'});
if current,current=merged_laos_source_current(entry_source(e));end
end
function s=entry_source(e)
s=struct('path',e.Path,'bytes',NaN,'datenum',NaN);
if isfield(e,'SourceSignature')&&isfield(e.SourceSignature,'Bytes')
    s.bytes=e.SourceSignature.Bytes;s.datenum=e.SourceSignature.ModifiedDatenum;
end
end
function b=safe_base(k,name)
[~,stem]=fileparts(name);stem=regexprep(stem,'[^A-Za-z0-9._-]','_');if isempty(stem),stem='data';end
b=sprintf('%03d_%s',k,stem(1:min(100,numel(stem))));
end
function result=remap_folders(result,old,new)
if isstruct(result)
    for k=1:numel(result)
        for f=fieldnames(result(k))'
            if strcmp(f{1},'outputFolder')&&startsWith(string(result(k).(f{1})),string(old))
                result(k).(f{1})=strrep(result(k).(f{1}),old,new);
            else,result(k).(f{1})=remap_folders(result(k).(f{1}),old,new);end
        end
    end
elseif iscell(result)
    for k=1:numel(result),result{k}=remap_folders(result{k},old,new);end
end
end
function p=absolute_path(p)
if isempty(p),error('MergedLAOS:ExportFolder','Choose an output folder.');end
if ispc,absolute=~isempty(regexp(p,'^[A-Za-z]:[\\/]|^\\\\','once'));
else,absolute=startsWith(p,'/');end
if ~absolute,p=fullfile(pwd,p);end
if isfolder(p),[ok,a]=fileattrib(p);if ok,p=a.Name;end,end
end
function assert_empty(p)
if isfile(p),error('MergedLAOS:ExportExists','Output is an existing file.');end
if isfolder(p),d=dir(p);if any(~ismember({d.name},{'.','..'})),error('MergedLAOS:ExportExists','Choose a new or empty output folder.');end,end
end
function write_json(path,value)
fid=fopen(path,'w','n','UTF-8');if fid<0,error('MergedLAOS:ExportWrite','Cannot open: %s',path);end
c=onCleanup(@()fclose(fid));fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true)); %#ok<NASGU>
end
function cleanup_stage(p),if isfolder(p),rmdir(p,'s');end,end
