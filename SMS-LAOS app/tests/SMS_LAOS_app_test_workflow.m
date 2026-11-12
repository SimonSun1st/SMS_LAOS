function report=SMS_LAOS_app_test_workflow(outputFolder)
%SMS_LAOS_APP_TEST_WORKFLOW Independent methods, shared units and export UI.
% Uses generated fixtures only and preserves every acquired input file.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
if nargin<1||isempty(outputFolder)
    outputFolder=fullfile(root,'validation',['revision_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
end
assert(~isfolder(outputFolder),'Choose a new report folder.');mkdir(outputFolder);
fixtureFolder=fullfile(outputFolder,'fixtures');mkdir(fixtureFolder);
F=make_fixtures(fixtureFolder);
app=SMS_LAOS_app('Visible','off');clean=onCleanup(@()delete_app(app)); %#ok<NASGU>
baseInput=app.currentInputSettings();
baseFT=app.FT.currentOptions();baseSD=app.SD.currentOptions();baseSPP=app.SPP.currentOptions();
tests=struct('Name',{},'Passed',{},'Details',{},'Seconds',{});
record('layout_and_export_control_ownership',@layout_test);
record('preview_units_frequency_and_strain_rate',@preview_units_test);
record('equivalent_units_all_methods',@method_units_test);
record('default_units_preserve_original_sms_numerics',@legacy_parity_test);
record('frequency_unit_selectors_preserve_physical_values',@frequency_units_test);
record('independent_ft_sd_settings_and_invalidation',@independent_test);
record('unit_changes_invalidate_all_methods',@unit_stale_test);
record('column_mapping_and_non_dat_inputs',@mapping_test);
record('input_settings_are_atomic',@atomic_input_test);
record('central_export_is_independent_of_calculation',@export_test);
record('specific_strain_lissajous_uses_si_data',@lissajous_test);
record('source_changes_and_failed_input_are_isolated',@source_test);
record('busy_state_locks_shared_units_and_all_methods',@busy_test);
record('english_screenshots_and_clear',@screenshot_test);
report=struct('Passed',all([tests.Passed]),'PassedCount',sum([tests.Passed]),'TestCount',numel(tests), ...
    'MATLABVersion',version,'CreatedUTC',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')), ...
    'Tests',tests,'Scope','Shared unit conversion, independent method configuration, revised English layout and central exports. Synthetic fixtures only.');
write_json(fullfile(outputFolder,'revision_report.json'),report);
fprintf('SMS-LAOS revision: %d/%d groups passed.\n',report.PassedCount,report.TestCount);

    function record(name,fn)
        started=tic;
        try,details=fn();passed=true;
        catch ME
            passed=false;details=[ME.identifier ': ' ME.message];
            if ~isempty(ME.stack),details=sprintf('%s [%s:%d]',details,ME.stack(1).name,ME.stack(1).line);end
        end
        tests(end+1)=struct('Name',name,'Passed',passed,'Details',details,'Seconds',toc(started)); %#ok<AGROW>
        flag='FAIL';if passed,flag='PASS';end
        fprintf('[%s] %s: %s\n',flag,name,details);
        write_json(fullfile(outputFolder,'revision_progress.json'),tests);
    end

    function reset(path,units)
        app.clearFiles();
        s=baseInput;s.TimeUnit='s';s.StrainUnit='decimal';s.StressUnit='Pa';
        s.TimeColumn=1;s.StrainColumn=2;s.StressColumn=3;s.HeaderLines=0;s.Delimiter='auto';s.Sheet=1;
        if nargin>1,for n=fieldnames(units)',s.(n{1})=units.(n{1});end,end
        app.setInputSettings(s);
        app.FT.applySettings(struct('FrequencyUnit','Hz'));app.SD.applySettings(struct('FrequencyUnit','Hz'));
        app.FT.applySettings(baseFT);app.SD.applySettings(baseSD);
        opts=baseSPP;
        for n={'MakePlots','Verbose','StoreRaw','StrainUnit','TimeColumn','StrainColumn','StressColumn','HeaderLines','Delimiter','Sheet'}
            if isfield(opts,n{1}),opts=rmfield(opts,n{1});end
        end
        app.SPP.applySettings(struct('FrequencyUnit','rad/s'));
        app.SPP.applySettings(opts);
        app.SPP.applySettings(struct('AnalysisMode','average','AveragingPolicy','manual', ...
            'SelectionMode','average','TrimCycles',[1 1],'PointsPerCycle',301, ...
            'AssessWindowSensitivity',false,'AssessSmoothingSensitivity',false));
        app.setMethods(struct('FT',true,'Stress',true,'SPP',true));
        app.Controls.ExportMode.Value='fast';app.Controls.ExportCurves.Value=true;
        app.Controls.ExportWaveforms.Value=false;app.Controls.ExportLissajous.Value=false;
        if nargin>0&&~isempty(path),app.addFiles(path);end
    end

    function text=layout_test()
        assert(strcmp(app.Figure.Name,'SMS-LAOS'),'The window must use the SMS-LAOS title.');
        assert(strcmp(app.Controls.InputTab.Title,'Data & units'),'Input configuration needs one shared tab.');
        assert(strcmp(app.Controls.FTTab.Title,'FT-LAOS'),'FT tab title changed.');
        assert(strcmp(app.Controls.StressTab.Title,'Stress decomposition'),'Stress tab should not be labelled as shared FT settings.');
        assert(~isequal(app.FT,app.SD),'FT and SD must have independent setting/result instances.');
        for name={'TimeUnit','StrainUnit','StressUnit','TimeColumn','StrainColumn','StressColumn','HeaderLines','Delimiter','Sheet'}
            assert(under(app.Controls.(name{1}),app.Controls.InputTab),'A shared input control is outside Data & units: %s',name{1});
        end
        for name={'ExportMode','ExportCurves','ExportWaveforms','ExportLissajous','PNG','PDF','FIG','TargetStrain','StrainTolerance','LissajousMode','CycleMode','LastNCycles'}
            assert(under(app.Controls.(name{1}),app.Controls.ExportTab),'An export option is outside Export: %s',name{1});
        end
        assert(~isfield(app.Axes,'Harmonics')&&~isfield(app.Axes,'Moduli'),'FT bar-chart axes remain in the app.');
        assert(isfield(app.Axes,'StrainSpectrum')&&isfield(app.Axes,'StressSpectrum'),'FT spectra were lost.');
        for module={app.FT,app.SD}
            assert(~visible_in_host(module{1}.Controls.fast_mode,app.Figure),'A method still shows Fast export.');
            assert(~visible_in_host(module{1}.Controls.save_curve_csv,app.Figure),'A method still shows the curve CSV option.');
        end
        text='Shared input controls and all export options belong to their own tabs; independent FT/SD modules; FT bar axes removed.';
    end

    function text=preview_units_test()
        cases={{F.Base,struct('TimeUnit','s','StrainUnit','decimal','StressUnit','Pa')}, ...
            {F.Milli,struct('TimeUnit','ms','StrainUnit','percent','StressUnit','kPa')}, ...
            {F.Minute,struct('TimeUnit','min','StrainUnit','microstrain','StressUnit','MPa')}};
        for j=1:numel(cases)
            reset(cases{j}{1},cases{j}{2});P=app.Entries(1).Preview;
            assert(~isempty(P),'Input did not produce a preview.');
            assert(isempty(app.FT.Entries(1).Result)&&isempty(app.SD.Entries(1).Result)&&isempty(app.SPP.Entries(1).Result),'Loading data ran a method.');
            near(P.time,F.Time,1e-12,'SI time');near(P.strain,F.Strain,1e-12,'decimal strain');near(P.stress,F.Stress,1e-12,'Pa stress');
            near(P.strainRate,gradient(P.strain,P.time),1e-12,'SI strain rate');
            assert(abs(P.frequencyHz-.5)<1e-6,'Input time unit affected physical frequency.');
            assert(abs(P.strainAmplitudePercent-20)<.01,'Input strain unit affected amplitude.');
        end
        text='Equivalent s/decimal/Pa, ms/percent/kPa and min/microstrain/MPa files yield the same SI waveforms, rate, frequency and amplitude before analysis.';
    end

    function text=method_units_test()
        paths={F.Base,F.Milli,F.Minute};units={struct('TimeUnit','s','StrainUnit','decimal','StressUnit','Pa'), ...
            struct('TimeUnit','ms','StrainUnit','percent','StressUnit','kPa'),struct('TimeUnit','min','StrainUnit','microstrain','StressUnit','MPa')};
        saved=cell(1,3);
        for j=1:3
            reset(paths{j},units{j});app.analyze('all');assert_all_current();
            saved{j}=struct('FT',app.FT.Entries(1).Result,'SD',app.SD.Entries(1).Result,'SPP',app.SPP.Entries(1).Result);
        end
        for j=2:3
            compare_sms(saved{1}.FT,saved{j}.FT);compare_sms(saved{1}.SD,saved{j}.SD);
            A=saved{1}.SPP;B=saved{j}.SPP;
            near(A.omega,B.omega,1e-8,'SPP omega');assert(~isempty(A.average)&&~isempty(B.average),'Manual SPP average unavailable.');
            near(A.average.proc.gamma,B.average.proc.gamma,1e-7,'SPP strain');near(A.average.proc.sigma,B.average.proc.sigma,1e-7,'SPP stress');
            near(A.average.Gt_storage,B.average.Gt_storage,1e-6,'SPP storage');near(A.average.Gt_loss,B.average.Gt_loss,1e-6,'SPP loss');
        end
        text='Unit-equivalent inputs agree across all three methods, including FT frequency/moduli, SD curves/viscosity and SPP local moduli.';
    end

    function text=legacy_parity_test()
        reset(F.Base);app.analyze('all');
        options=app.FT.currentOptions();options.strain_is_percent=false;
        reference=SMS_LAOS_app_analyze_FT_SD_file(F.Base,options);
        compare_sms(reference,app.FT.Entries(1).Result);compare_sms(reference,app.SD.Entries(1).Result);
        text='Default seconds/decimal/Pa preserves the original SMS numerical outputs; unit provenance may add metadata.';
    end

    function text=frequency_units_test()
        reset(F.Base);
        app.FT.applySettings(struct('use_freq_range',true,'freq_min',.25,'freq_max',1));
        app.SD.applySettings(struct('use_freq_range',true,'freq_min',.25,'freq_max',1));
        app.SPP.applySettings(struct('Omega',pi));app.analyze('all');assert_all_current();
        for module={app.FT,app.SD}
            before=module{1}.currentOptions();module{1}.applySettings(struct('FrequencyUnit','rad/s'));after=module{1}.currentOptions();
            near(before.freq_min,after.freq_min,1e-12,'FT/SD physical minimum frequency');near(before.freq_max,after.freq_max,1e-12,'FT/SD physical maximum frequency');
            near(module{1}.Controls.freq_min.Value,2*pi*before.freq_min,1e-12,'FT/SD rad/s display');
        end
        before=app.SPP.currentOptions();app.SPP.applySettings(struct('FrequencyUnit','Hz'));after=app.SPP.currentOptions();
        near(before.Omega,after.Omega,1e-12,'SPP physical frequency');near(str2double(app.SPP.Controls.Omega.Value),.5,1e-12,'SPP Hz display');
        assert_all_current();
        text='FT/SD frequency ranges and SPP manual frequency switch between Hz and rad/s without changing physical values or result freshness.';
    end

    function text=independent_test()
        reset(F.Base);app.analyze('all');sd=app.SD.Entries(1).Result;sp=app.SPP.Entries(1).Result;
        app.FT.applySettings(struct('remove_first_cycles',2));
        assert(strcmp(app.FT.Entries(1).Status,'stale'),'FT setting change did not invalidate FT.');
        assert(current(app.SD.Entries(1))&&current(app.SPP.Entries(1)),'FT setting change invalidated SD or SPP.');
        assert(isequaln(sd,app.SD.Entries(1).Result)&&isequaln(sp,app.SPP.Entries(1).Result),'FT settings mutated another method result.');
        app.setMethods(struct('FT',true,'Stress',false,'SPP',false));app.analyze('selected');
        assert(current(app.FT.Entries(1))&&current(app.SD.Entries(1)),'FT-only reanalysis discarded valid SD.');
        assert(app.FT.Entries(1).Result.n_cycles_used~=app.SD.Entries(1).Result.n_cycles_used,'Independent cycle settings did not affect separate results.');
        app.SD.applySettings(struct('last_n_cycles',4,'cycle_selection_mode','last_n_cycles'));
        assert(strcmp(app.SD.Entries(1).Status,'stale')&&current(app.FT.Entries(1))&&current(app.SPP.Entries(1)),'SD change invalidated the wrong methods.');
        text='FT and SD keep their own settings, cycles, cached results and stale state; changing or rerunning one leaves the others intact.';
    end

    function text=unit_stale_test()
        reset(F.Base);app.analyze('all');
        app.setInputSettings(struct('StressUnit','kPa'));
        assert(all(strcmp({app.FT.Entries.Status,app.SD.Entries.Status,app.SPP.Entries.Status},'stale')),'Changing input stress units must invalidate every method.');
        near(app.Entries(1).Preview.stress,1000*F.Stress,1e-12,'changed input stress unit');
        app.setInputSettings(struct('StressUnit','Pa'));assert_all_current();
        app.setInputSettings(struct('TimeUnit','ms'));
        assert(all(strcmp({app.FT.Entries.Status,app.SD.Entries.Status,app.SPP.Entries.Status},'stale')),'Changing input time units must invalidate every method.');
        near(app.Entries(1).Preview.frequencyHz,500,1e-6,'time-scaled frequency');
        text='Shared time/stress changes refresh previews and invalidate all methods; restoring exact prior units recovers matching results.';
    end

    function text=mapping_test()
        reset(F.Mapped,struct('TimeColumn',3,'StrainColumn',4,'StressColumn',2));app.analyze('all');assert_all_current();
        P=app.Entries(1).Preview;near(P.time,F.Time,1e-12,'mapped time');near(P.stress,F.Stress,1e-12,'mapped stress');
        options=app.FT.currentOptions();options.strain_is_percent=false;R=SMS_LAOS_app_analyze_FT_SD_file(F.Base,options);
        compare_sms(R,app.FT.Entries(1).Result);compare_sms(R,app.SD.Entries(1).Result);
        text='CSV input with reordered columns uses the shared mapping consistently for preview, FT, SD and SPP.';
    end

    function text=atomic_input_test()
        reset(F.Base);before=app.currentInputSettings();P=app.Entries(1).Preview;
        must_throw(@()app.setInputSettings(struct('TimeUnit','ms','StressUnit','invalid-pressure')));
        assert(isequaln(before,app.currentInputSettings()),'Invalid unit update partially changed input controls.');
        assert(isequaln(P,app.Entries(1).Preview),'Rejected input update mutated preview.');
        must_throw(@()app.setInputSettings(struct('TimeColumn',2,'StrainColumn',2)));
        assert(isequaln(before,app.currentInputSettings()),'Duplicate column update partially changed settings.');
        text='Unknown units and duplicate column mappings are rejected atomically.';
    end

    function text=export_test()
        reset(F.Base);app.FT.applySettings(struct('remove_first_cycles',2));app.SD.applySettings(struct('cycle_selection_mode','last_n_cycles','last_n_cycles',4));
        app.analyze('all');assert_all_current();Rft=app.FT.Entries(1).Result;Rsd=app.SD.Entries(1).Result;Rsp=app.SPP.Entries(1).Result;
        app.Controls.ExportMode.Value='fast';app.Controls.ExportCurves.Value=true;
        app.refresh();assert_all_current();
        folder=fullfile(outputFolder,'all_methods_export');M=app.exportResults(folder);
        assert(M.exportedFTCount==1&&M.exportedStressCount==1&&M.exportedSPPCount==1,'Wrong method export counts.');
        assert(has_exact_result(fullfile(folder,'FT_LAOS'),Rft),'FT export lost its own exact result.');
        assert(has_exact_result(fullfile(folder,'Stress_decomposition'),Rsd),'SD export used the FT result or lost its own result.');
        assert(has_exact_result(fullfile(folder,'SPP'),Rsp),'SPP export lost exact result.');
        assert(~has_exact_result(fullfile(folder,'FT_LAOS'),Rsd),'Independent SD result leaked into FT export.');
        app.Controls.ExportMode.Value='full';app.Controls.ExportCurves.Value=false;app.refresh();assert_all_current();
        assert(isequaln(Rft,app.FT.Entries(1).Result)&&isequaln(Rsd,app.SD.Entries(1).Result),'Export options changed calculated values.');
        must_throw(@()app.exportResults(folder));assert(~app.Busy,'Rejected overwrite left app busy.');
        text='Central export switches do not invalidate calculation; each method exports its own exact result and existing folders are protected.';
    end

    function text=lissajous_test()
        reset(F.Milli,struct('TimeUnit','ms','StrainUnit','percent','StressUnit','kPa'));
        options=struct('TargetStrainPercent',20,'TolerancePercent',.01,'Mode','per_file','CycleMode','last_n', ...
            'LastNCycles',2,'FormatPNG',true,'FormatPDF',false,'FormatFIG',false);
        folder=fullfile(outputFolder,'lissajous_si');M=app.exportLissajous(folder,options);assert(M.matchedCount==1);
        P=app.Entries(1).Preview;mask=P.time>=P.time(end)-2/P.frequencyHz;T=readtable(fullfile(folder,M.entries(1).curveCSV));
        near(T.Time_s,P.time(mask),1e-12,'Lissajous SI time');near(T.Stress_Pa,P.stress(mask),1e-12,'Lissajous SI stress');
        near(T.StrainRate_per_s,P.strainRate(mask),1e-12,'Lissajous SI rate');
        assert(numel(dir(fullfile(folder,'*.png')))==2,'Missing elastic or viscous Lissajous image.');
        text='A specific strain exported from ms/percent/kPa input uses seconds, decimal/s strain rate and Pa consistently.';
    end

    function text=source_test()
        mutable=fullfile(fixtureFolder,'source_change.dat');copyfile(F.Base,mutable);
        reset({mutable,F.Bad});app.analyze('all');
        assert(current(app.FT.Entries(1))&&current(app.SD.Entries(1))&&current(app.SPP.Entries(1)),'Bad file blocked valid input.');
        assert(all(strcmp({app.FT.Entries(2).Status,app.SD.Entries(2).Status,app.SPP.Entries(2).Status},'error')),'Malformed input was not isolated for every method.');
        fid=fopen(mutable,'a');fprintf(fid,'\n# test-owned source mutation\n');fclose(fid);app.refresh();
        assert(all(strcmp({app.FT.Entries(1).Status,app.SD.Entries(1).Status,app.SPP.Entries(1).Status},'stale')),'Changed source did not invalidate all methods.');
        text='Failed inputs remain isolated; source changes invalidate FT, SD and SPP independently.';
    end

    function text=busy_test()
        reset(F.Base);seen=false;blocked=false(1,4);
        probeTimer=timer('ExecutionMode','fixedSpacing','Period',.01,'StartDelay',.01,'TimerFcn',@probe);
        cleanTimer=onCleanup(@()dispose_timer(probeTimer)); %#ok<NASGU>
        start(probeTimer);app.analyze('all');stop(probeTimer);
        assert(seen&&all(blocked),'A shared input or method parameter was writable while analysis was busy.');
        assert(~app.Busy,'Busy state was not released.');
        text='Shared input units and all three method settings are locked during a run and restored afterwards.';
        function probe(~,~)
            if ~app.Busy,return;end
            seen=true;
            try,app.setInputSettings(struct('StressUnit','kPa'));catch,blocked(1)=true;end
            try,app.FT.applySettings(struct('remove_first_cycles',2));catch,blocked(2)=true;end
            try,app.SD.applySettings(struct('remove_first_cycles',2));catch,blocked(3)=true;end
            try,app.SPP.applySettings(struct('MinStableCycles',6));catch,blocked(4)=true;end
            stop(probeTimer);
        end
    end

    function text=screenshot_test()
        reset(F.Base);app.analyze('all');assert(isempty(findall(app.Controls.FTTab,'Type','bar')),'FT contains a bar chart.');
        tabs={'InputTab','FTTab','StressTab','SPPTab','ExportTab'};
        for j=1:numel(tabs)
            app.Tabs.SelectedTab=app.Controls.(tabs{j});drawnow;
            app.saveView(fullfile(outputFolder,sprintf('%02d_%s.png',j,tabs{j})));
        end
        app.clearFiles();assert(isempty(app.FT.Entries)&&isempty(app.SD.Entries)&&isempty(app.SPP.Entries),'Clear left a method list behind.');
        assert(isfile(F.Base)&&isfile(F.Milli)&&isfile(F.Minute),'Clear removed test input files.');
        text='Five revised English tabs captured; no FT bar objects; clearing removes only workspace entries.';
    end

    function assert_all_current()
        assert(current(app.FT.Entries(1))&&current(app.SD.Entries(1))&&current(app.SPP.Entries(1)), ...
            'A method is not current: FT=%s, SD=%s, SPP=%s',app.FT.Entries(1).Status,app.SD.Entries(1).Status,app.SPP.Entries(1).Status);
    end
end

function F=make_fixtures(folder)
t=(0:5999)'/256;g=.2*sin(pi*t);stress=15000*g+700*cos(pi*t)+65*sin(3*pi*t);
F=struct('Time',t,'Strain',g,'Stress',stress,'Base',fullfile(folder,'seconds_decimal_pa.dat'), ...
    'Milli',fullfile(folder,'milliseconds_percent_kpa.dat'),'Minute',fullfile(folder,'minutes_microstrain_mpa.dat'), ...
    'Mapped',fullfile(folder,'reordered.csv'),'Bad',fullfile(folder,'bad_time.dat'));
writematrix([t g stress],F.Base,'Delimiter','tab');
writematrix([1000*t 100*g stress/1000],F.Milli,'Delimiter','tab');
writematrix([t/60 1e6*g stress/1e6],F.Minute,'Delimiter','tab');
writematrix([zeros(size(t)) stress t g],F.Mapped);
bad=t;bad(200)=bad(199);writematrix([bad g stress],F.Bad,'Delimiter','tab');
end
function compare_sms(a,b)
names={'time_raw','strain_raw','stress_raw','selected_mask','time','strain','stress','gammadot','stress_elastic', ...
    'stress_viscous','stress_reconstructed','freq_hz','omega','n_cycles_used','I1','I3','I3_I1','Gp1','Gpp1','Gp3','Gpp3', ...
    'e1','e3','v1','v3','G_M_prime','G_L_prime','eta_M_prime','eta_L_prime','S','T'};
for n=names,near(a.(n{1}),b.(n{1}),1e-8,['SMS ' n{1}]);end
end
function near(a,b,tolerance,label)
assert(isequal(size(a),size(b)),'%s shape differs.',label);
assert(isequal(isfinite(a),isfinite(b)),'%s finite mask differs.',label);
good=isfinite(a)&isfinite(b);aa=double(a(good));bb=double(b(good));
if isempty(aa),return;end
scale=max(1,max(abs([aa(:);bb(:)])));err=max(abs(aa-bb));
assert(err<=tolerance*scale,'%s differs: absolute error %.6g, allowed %.6g.',label,err,tolerance*scale);
end
function tf=current(entry),tf=ismember(entry.Status,{'ok','warning'});end
function must_throw(f)
caught=false;try,f();catch,caught=true;end;assert(caught,'Expected this invalid/stale operation to be rejected.');
end
function tf=under(h,parent)
tf=false;
while ~isempty(h)&&isgraphics(h)
    if isequal(h,parent),tf=true;return;end
    if ~isprop(h,'Parent'),return;end;h=h.Parent;
end
end
function tf=visible_in_host(h,host)
tf=true;
while ~isempty(h)&&isgraphics(h)&&~isequal(h,host)
    if isprop(h,'Visible')&&strcmp(char(h.Visible),'off'),tf=false;return;end
    h=h.Parent;
end
end
function tf=has_exact_result(folder,expected)
tf=false;files=dir(fullfile(folder,'**','*.mat'));
for j=1:numel(files)
    S=load(fullfile(files(j).folder,files(j).name));
    for n=fieldnames(S)',if isequaln(S.(n{1}),expected),tf=true;return;end,end
end
end
function dispose_timer(t),if isvalid(t),stop(t);delete(t);end,end
function delete_app(a),if ~isempty(a)&&isvalid(a),delete(a);end,end
function write_json(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
