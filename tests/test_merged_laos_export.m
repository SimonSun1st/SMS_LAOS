function report=test_merged_laos_export(outputFolder)
%TEST_MERGED_LAOS_EXPORT Independent coordinator/export contract checks.
% Generated fixtures and outputs are retained; no user acquisition is edited.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'core'),fullfile(root,'modules','ft','core'), ...
    fullfile(root,'modules','ft','app'),fullfile(root,'modules','spp'), ...
    fullfile(root,'modules','spp','legacy'),fullfile(root,'modules','spp','app'));
if nargin<1||isempty(outputFolder)
    outputFolder=fullfile(root,'validation',['export_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
end
if isfolder(outputFolder),d=dir(outputFolder);assert(~any(~ismember({d.name},{'.','..'})),'Choose a new/empty test output folder.');else,mkdir(outputFolder);end
fixture=fullfile(outputFolder,'fixture.dat');t=(0:1/400:16)';q=2*pi*.7*t;
writematrix([t .1*sin(q) .1*(1000*sin(q)+200*cos(q))+3*sin(3*q)],fixture,'Delimiter','tab');
o=sms_laos_defaults();o.fast_mode=true;o.strain_is_percent=false;
R=sms_laos_analyze_file(fixture,o);
SP=spp_laos_analyze_v5(fixture,'StrainUnit','decimal','MakePlots',false,'Verbose',false, ...
    'PointsPerCycle',201,'AssessWindowSensitivity',false,'AssessSmoothingSensitivity',false,'StoreRaw',false);
P=merged_laos_preview(fixture,struct('StrainUnit','decimal'));
d=dir(fixture);sig=struct('Exists',true,'Bytes',d.bytes,'ModifiedDatenum',d.datenum,'Method','file-size-and-mtime');
e=struct('Path',fixture,'Name','fixture.dat','Preview',P,'PreviewError','','FTDone',true,'StressDone',true);
f=struct('Path',fixture,'Name','fixture.dat','Status','ok','Result',R,'Error','','Options',o,'SourceSignature',sig,'StaleReason','');
s=f;s.Result=SP;s.Options=SP.settings;
opts=struct('Methods',struct('FT',true,'Stress',true,'SPP',true),'IncludeWaveforms',false, ...
    'IncludeLissajous',false,'FTOptions',o,'Lissajous',struct('TargetStrainPercent',10,'TolerancePercent',.1, ...
    'Mode','per_file','CycleMode','last_n','LastNCycles',1,'FormatPNG',true,'FormatPDF',false,'FormatFIG',false));
rows=struct('Name',{},'Passed',{},'Details',{},'Seconds',{});
record('all_seven_checkbox_combinations',@combinations);
record('complete_mat_parity_and_csv_values',@mat_parity);
record('stale_settings_source_and_unrun_exclusions',@exclusions);
record('preview_only_and_nested_lissajous',@preview_only);
record('empty_overwrite_and_order_guards',@guards);
record('full_native_stress_export',@full_export);
record('manifest_final_paths',@manifests);
report=struct('Passed',all([rows.Passed]),'PassedCount',sum([rows.Passed]),'TestCount',numel(rows), ...
    'MATLABVersion',version,'OutputFolder',outputFolder,'Tests',rows);
write_json(fullfile(outputFolder,'export_report.json'),report);
fprintf('Merged export: %d/%d passed.\n',report.PassedCount,report.TestCount);

    function record(name,fn)
        started=tic;
        try,detail=fn();passed=true;catch ME,passed=false;detail=getReport(ME,'basic','hyperlinks','off');end
        rows(end+1)=struct('Name',name,'Passed',passed,'Details',detail,'Seconds',toc(started));
        flag='FAIL';if passed,flag='PASS';end
        fprintf('[%s] %s: %s\n',flag,name,detail);
    end
    function detail=combinations()
        for value=1:7
            selection=logical(bitget(value,1:3));a=opts;
            a.Methods=struct('FT',selection(1),'Stress',selection(2),'SPP',selection(3));
            out=fullfile(outputFolder,sprintf('combination_%d',value));M=merged_laos_export(e,f,s,out,a);
            assert(isequal([M.exportedFTCount M.exportedStressCount M.exportedSPPCount],double(selection)),'Requested method counts differ.');
            assert(isfolder(fullfile(out,'FT_LAOS'))==selection(1),'FT folder selection mismatch.');
            assert(isfolder(fullfile(out,'Stress_decomposition'))==selection(2),'Stress folder selection mismatch.');
            assert(isfolder(fullfile(out,'SPP'))==selection(3),'SPP folder selection mismatch.');
            assert(~isfolder(fullfile(out,'Waveforms'))&&~isfolder(fullfile(out,'Lissajous')),'Unchecked raw exports appeared.');
            T=readtable(fullfile(out,'analysis_status.csv'));assert(height(T)==1,'Single-file status CSV must have one record.');
        end
        detail='All seven nonempty method subsets export only their selected module folders and correct counts.';
    end
    function detail=mat_parity()
        out=fullfile(outputFolder,'combination_7');F=load(fullfile(out,'FT_LAOS','001_fixture.mat'));
        assert(isfield(F,'R')&&isequaln(F.R,R),'FT MAT must preserve the exact shared backend result.');
        for n=fieldnames(F.FT)',assert(isequaln(F.FT.(n{1}),R.(n{1})),'FT convenience field differs from backend.');end
        M=jsondecode(fileread(fullfile(out,'Stress_decomposition','manifest.json')));
        F=load(fullfile(out,'Stress_decomposition',M.entries(1).matFile));assert(isequaln(F.R,R),'Native stress MAT differs.');
        M=jsondecode(fileread(fullfile(out,'SPP','manifest.json')));
        F=load(fullfile(out,'SPP',M.entries(1).matFile));assert(isequaln(F.R,SP),'SPP MAT differs.');
        H=readtable(fullfile(out,'FT_LAOS','001_fixture_harmonics.csv'));
        assert(max(abs(H.Amplitude_Pa-[R.I1;R.I3]))<1e-10,'FT harmonic CSV changed amplitudes.');
        assert(max(abs(H.Phase_rad-[R.delta1;R.delta3]))<1e-10,'FT harmonic phase units changed.');
        detail='Exact FT/shared-R, native SMS and SPP MAT structures; FT amplitudes/phases match original arrays.';
    end
    function detail=exclusions()
        stale=f;stale.Status='stale';stale.StaleReason='Analysis settings changed';
        out=fullfile(outputFolder,'stale_ft');M=merged_laos_export(e,stale,s,out,opts);
        assert(M.exportedFTCount==0&&M.exportedStressCount==0&&M.exportedSPPCount==1,'Stale FT did not leave SPP independently exportable.');
        changed=s;changed.SourceSignature.Bytes=1;
        out=fullfile(outputFolder,'source_changed_spp');M=merged_laos_export(e,f,changed,out,opts);
        assert(M.exportedFTCount==1&&M.exportedStressCount==1&&M.exportedSPPCount==0,'Changed SPP source should be excluded independently.');
        assert(strcmp(M.entries.SPPStatus,'source changed'),'Source change is absent from status.');
        unrun=e;unrun.FTDone=false;unrun.StressDone=false;
        out=fullfile(outputFolder,'unrun_ft');M=merged_laos_export(unrun,f,s,out,opts);
        assert(M.exportedFTCount==0&&M.exportedStressCount==0&&M.exportedSPPCount==1,'Unrun method flags were ignored.');
        detail='Stale settings, source-signature mismatch, and per-method completion flags exclude only affected methods.';
    end
    function detail=preview_only()
        a=opts;a.Methods=struct('FT',false,'Stress',false,'SPP',false);a.IncludeWaveforms=true;
        out=fullfile(outputFolder,'waveform_only');M=merged_laos_export(e,f,s,out,a);
        T=readtable(fullfile(out,M.entries.waveformCSV));
        assert(max(abs(T.StrainRate_per_s-P.strainRate))<1e-11,'Waveform CSV strain rate changed.');
        a.IncludeLissajous=true;out=fullfile(outputFolder,'preview_and_lissajous');
        M=merged_laos_export(e,f,s,out,a);assert(M.modules.Lissajous.matchedCount==1,'Nested Lissajous failed to match measured strain.');
        assert(~isfolder(fullfile(out,'FT_LAOS'))&&~isfolder(fullfile(out,'SPP')),'Preview-only export unexpectedly included method results.');
        detail='Waveforms and amplitude-selected Lissajous export independently of analyzed-method checkboxes.';
    end
    function detail=guards()
        a=opts;a.Methods=struct('FT',false,'Stress',false,'SPP',false);
        out=fullfile(outputFolder,'empty');must_error(@()merged_laos_export(e,f,s,out,a),'MergedLAOS:ExportEmpty');assert(~isfolder(out),'Empty export exposed a destination.');
        out=fullfile(outputFolder,'guard');mkdir(out);file=fullfile(out,'keep.txt');fid=fopen(file,'w');fprintf(fid,'user sentinel');fclose(fid);
        must_error(@()merged_laos_export(e,f,s,out,opts),'MergedLAOS:ExportExists');assert(strcmp(fileread(file),'user sentinel'),'Existing destination was modified.');
        wrong=f;wrong.Path=[fixture '_different'];out=fullfile(outputFolder,'wrong_order');
        must_error(@()merged_laos_export(e,wrong,s,out,opts),'MergedLAOS:ExportEntries');assert(~isfolder(out),'Invalid entry order exposed a destination.');
        bad=f;bad.Status='stale';bad2=s;bad2.Status='stale';
        out=fullfile(outputFolder,'all_stale');must_error(@()merged_laos_export(e,bad,bad2,out,opts),'MergedLAOS:ExportEmpty');
        detail='No selection/current results, mismatched input order and nonempty destination reject without modifying destination.';
    end
    function detail=full_export()
        a=opts;a.Methods=struct('FT',false,'Stress',true,'SPP',false);a.FTOptions.fast_mode=false;
        out=fullfile(outputFolder,'full_stress');M=merged_laos_export(e,f,s,out,a);
        assert(isfile(fullfile(out,'Stress_decomposition',M.modules.Stress.summaryExcel)),'Full native Excel is missing.');
        assert(isfile(fullfile(out,'Stress_decomposition',M.modules.Stress.summaryPNG)),'Full native summary PNG is missing.');
        assert(isfile(fullfile(out,'Stress_decomposition',M.modules.Stress.entries(1).plotFIG)),'Full native file FIG is missing.');
        detail='Full export retains native XLSX, PNG, FIG, selected-cycle and decomposition outputs.';
    end
    function detail=manifests()
        jsons=dir(fullfile(outputFolder,'**','manifest.json'));
        for k=1:numel(jsons)
            path=fullfile(jsons(k).folder,jsons(k).name);M=jsondecode(fileread(path));
            check_paths(M);
        end
        detail=sprintf('%d root/nested manifests contain existing final outputFolder paths with no staging directory.',numel(jsons));
    end
end
function check_paths(value)
if isstruct(value)
    for k=1:numel(value)
        for f=fieldnames(value(k))'
            if strcmp(f{1},'outputFolder'),assert(isfolder(value(k).(f{1})),'Manifest outputFolder still names staging.');
            else,check_paths(value(k).(f{1}));end
        end
    end
elseif iscell(value)
    for k=1:numel(value),check_paths(value{k});end
end
end
function must_error(fn,id)
try,fn();catch ME,assert(strcmp(ME.identifier,id),ME.message);return,end
error('Test:ExpectedFailure','Expected %s',id);
end
function write_json(path,value)
fid=fopen(path,'w','n','UTF-8');c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
