function report=SMS_LAOS_app_test_units
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'core'),fullfile(root,'modules','ft','core'),fullfile(root,'modules','spp'));
% Avoid placing an exact legacy trim threshold on an acquired sample.
% A unit-rounding ULP can otherwise move that unchanged strict threshold.
folder=tempname;mkdir(folder);t=(0:5999)'/257;w=2*pi*.73;g=.25*sin(w*t);s=12000*g+350*cos(w*t)+40*sin(3*w*t)+15*cos(2*w*t);
units={ ...
 's','decimal','Pa',1,1,1; ...
 'ms','percent','kPa',1e-3,.01,1e3; ...
 'min','microstrain','MPa',60,1e-6,1e6; ...
 'us','millistrain','bar',1e-6,1e-3,1e5; ...
 'h','decimal','mPa',3600,1,.001; ...
 's','percent','psi',1,.01,.45359237*9.80665/.0254^2; ...
 's','percent','dyn/cm^2',1,.01,.1};
opts=SMS_LAOS_app_FT_SD_defaults();opts.use_alternating_odd_sign=false;
sppOpts=struct('MakePlots',false,'Verbose',false,'StoreRaw',true,'PointsPerCycle',301, ...
 'AnalysisMode','cycle_evolution','AssessWindowSensitivity',false,'AssessSmoothingSensitivity',false);
rows=struct('TimeUnit',{},'StrainUnit',{},'StressUnit',{},'PreviewMaxRelativeError',{},'SMSMaxRelativeError',{},'SPPMaxRelativeError',{});
for k=1:size(units,1)
 path=fullfile(folder,sprintf('case_%02d.dat',k));
 input=struct('TimeUnit',units{k,1},'StrainUnit',units{k,2},'StressUnit',units{k,3});
 z=[t/units{k,4},g/units{k,5},s/units{k,6}];write_data(path,z);
 P=SMS_LAOS_app_preview(path,input);R=SMS_LAOS_app_analyze_FT_SD(path,opts,input);S=SMS_LAOS_app_analyze_SPP(path,sppOpts,input);
 assert(strcmp(R.input_settings.TimeUnit,input.TimeUnit)&&strcmp(S.input_settings.StressUnit,input.StressUnit));
 assert(strcmp(R.source.path,path)&&strcmp(S.source.path,path)&&strcmp(S.import_info.source,path));
 if k==1,P0=P;R0=R;S0=S;end
 pe=max([rel(P.time,P0.time),rel(P.strain,P0.strain),rel(P.stress,P0.stress),rel(P.strainRate,P0.strainRate),rel(P.frequencyHz,P0.frequencyHz)]);
 re=max([rel(R.time,R0.time),rel(R.strain,R0.strain),rel(R.stress,R0.stress),rel(R.stress_reconstructed,R0.stress_reconstructed),rel([R.Gp1 R.Gpp1 R.I3_I1 R.S R.T],[R0.Gp1 R0.Gpp1 R0.I3_I1 R0.S R0.T])]);
 se=max([rel(S.omega,S0.omega),rel(S.evolution.gamma,S0.evolution.gamma),rel(S.evolution.sigma,S0.evolution.sigma),rel(S.evolution.Gt_storage,S0.evolution.Gt_storage),rel(S.evolution.Gt_loss,S0.evolution.Gt_loss)]);
 assert(pe<1e-7,'Preview unit-equivalence failure.');assert(re<1e-7,'SMS unit-equivalence failure.');assert(se<1e-6,'SPP unit-equivalence failure.');
 rows(end+1)=struct('TimeUnit',input.TimeUnit,'StrainUnit',input.StrainUnit,'StressUnit',input.StressUnit,'PreviewMaxRelativeError',pe,'SMSMaxRelativeError',re,'SPPMaxRelativeError',se); %#ok<AGROW>
end
% Frozen default scalar/array parity in both strain conventions.
for unit={'decimal','percent'}
 path=fullfile(folder,['baseline_' unit{1} '.dat']);factor=1;if strcmp(unit{1},'percent'),factor=100;end
 write_data(path,[t factor*g s]);o=opts;o.strain_is_percent=factor==100;
 R=SMS_LAOS_app_analyze_FT_SD(path,o,struct('StrainUnit',unit{1}));old=SMS_LAOS_app_analyze_FT_SD_file(path,o);
 fields=setdiff(fieldnames(old),{'quality'});
 for j=1:numel(fields),assert(isequaln(R.(fields{j}),old.(fields{j})),fields{j});end
 args=reshape([fieldnames(sppOpts) struct2cell(sppOpts)]',1,[]);
 legacy=SMS_LAOS_app_SPP_analyze_v5(path,args{:},'StrainUnit',unit{1});new=SMS_LAOS_app_analyze_SPP(path,sppOpts,struct('StrainUnit',unit{1}));
 for name={'omega','period','evolution','selection','cycles','raw','quality','frequency_info'}
  assert(isequaln(new.(name{1}),legacy.(name{1})),['SPP baseline: ' name{1}]);
 end
end
% Mapping, file formats and original NaN filtering stay explicit.
path=fullfile(folder,'mapped.csv');write_data(path,[s/1000 t*1000 g*1e6]);mapped=struct('TimeUnit','ms','StrainUnit','microstrain','StressUnit','kPa','TimeColumn',2,'StrainColumn',3,'StressColumn',1);
D=SMS_LAOS_app_read_input(path,mapped,'all_columns');assert(rel(D.data,[t g s])<1e-12);M=SMS_LAOS_app_analyze_FT_SD(path,opts,mapped);assert(rel(M.stress,R0.stress)<1e-7);
path=fullfile(folder,'extra_nan.dat');z=[t g s ones(size(t))];z(50,4)=NaN;write_data(path,z);
D=SMS_LAOS_app_read_input(path,struct('StrainUnit','decimal'),'all_columns');assert(D.source.rowsRemovedForExtraColumns==1&&numel(t)-size(D.data,1)==1);
D=SMS_LAOS_app_read_input(path,struct('StrainUnit','decimal'),'selected');assert(size(D.data,1)==numel(t));
% Retain an exact-boundary fixture as a diagnostic, without changing core trim.
tb=(0:6000)'/257;gb=.25*sin(w*tb);sb=12000*gb+350*cos(w*tb)+40*sin(3*w*tb)+15*cos(2*w*tb);
basePath=fullfile(folder,'boundary_base.dat');convertedPath=fullfile(folder,'boundary_mapped.csv');
write_data(basePath,[tb gb sb]);write_data(convertedPath,[sb/1000 tb*1000 gb*1e6]);
BD=SMS_LAOS_app_read_input(basePath,struct('StrainUnit','decimal'),'all_columns');CD=SMS_LAOS_app_read_input(convertedPath,mapped,'all_columns');
assert(rel(BD.data,CD.data)<1e-12,'Boundary fixture input conversion is wrong.');
BR=SMS_LAOS_app_analyze_FT_SD(basePath,opts,struct('StrainUnit','decimal'));CR=SMS_LAOS_app_analyze_FT_SD(convertedPath,opts,mapped);
rawCore=SMS_LAOS_app_FT_SD_core_v2(CD.data,opts.cycle_selection_mode,opts.remove_first_cycles,opts.remove_last_cycles, ...
 opts.last_n_cycles,false,opts.use_freq_range,opts.freq_min,opts.freq_max,opts.use_alternating_odd_sign);
assert(isequaln(rawCore.selected_mask,CR.selected_mask)&&isequaln(rawCore.stress,CR.stress),'Adapter changed the original trim rule.');
boundary=struct('InputSIValuesEquivalent',true,'MaxAbsoluteInputDifferences',max(abs(BD.data-CD.data)), ...
 'BaseFrequencyHz',BR.freq_hz,'ConvertedFrequencyHz',CR.freq_hz, ...
 'BaseSelectedSampleCount',nnz(BR.selected_mask),'ConvertedSelectedSampleCount',nnz(CR.selected_mask), ...
 'BaseFirstSelectedIndex',find(BR.selected_mask,1,'first'),'ConvertedFirstSelectedIndex',find(CR.selected_mask,1,'first'), ...
 'BaseLastSelectedIndex',find(BR.selected_mask,1,'last'),'ConvertedLastSelectedIndex',find(CR.selected_mask,1,'last'), ...
 'RetainedMaskDifferenceCount',nnz(BR.selected_mask~=CR.selected_mask),'AdapterMatchesFrozenCore',true, ...
 'Explanation','At an exactly sampled crop boundary, rounding during equivalent-unit conversion can shift a strict original SMS boundary by one sample. This is recorded rather than rounded away.');
% Average-response mode also receives the same normalized strain/stress.
avOpts=sppOpts;avOpts.AnalysisMode='average';avOpts.AveragingPolicy='manual';
A=SMS_LAOS_app_analyze_SPP(fullfile(folder,'case_01.dat'),avOpts,struct('StrainUnit','decimal'));
B=SMS_LAOS_app_analyze_SPP(fullfile(folder,'case_03.dat'),avOpts,struct('TimeUnit','min','StrainUnit','microstrain','StressUnit','MPa'));
assert(~isempty(A.average)&&~isempty(B.average));assert(rel(A.average.Gt_storage,B.average.Gt_storage)<1e-6);assert(rel(A.average.Gt_loss,B.average.Gt_loss)<1e-6);
% Numeric selectors and finite conversion overflow must fail explicitly.
failed=false;try,SMS_LAOS_app_input_defaults(struct('TimeColumn','1'));catch,failed=true;end;assert(failed);
failed=false;try,SMS_LAOS_app_input_defaults(struct('StrainColumn',2+1i));catch,failed=true;end;assert(failed);
path=fullfile(folder,'overflow.dat');write_data(path,[t g repmat(realmax/2,size(t))]);
failed=false;try,SMS_LAOS_app_read_input(path,struct('StrainUnit','decimal','StressUnit','MPa'));catch ME,failed=strcmp(ME.identifier,'MergedLAOS:UnitOverflow');end;assert(failed);
% Invalid units do not silently revert to SI.
failed=false;try,SMS_LAOS_app_input_defaults(struct('StressUnit','mPA'));catch,failed=true;end;assert(failed);
report=struct('Passed',true,'MATLABVersion',version,'EquivalentUnitCases',rows,'BoundarySensitiveDiagnostic',boundary,'DefaultSMSParity','All original fields except revised diagnostic text exactly equal in percent/decimal cases.', ...
 'DefaultSPPParity','omega, period, evolution, selection, cycles, raw, quality and frequency_info exactly equal in percent/decimal cases.', ...
 'NumericalLimit','As in the frozen SMS core, a strict crop boundary exactly on a sampled timestamp may move by one point after floating-point unit conversion; no rounding or core change is introduced.','MappingAndFilteringPassed',true,'AverageUnitParityPassed',true,'InvalidUnitsAndSelectorsRejected',true,'ConversionOverflowRejected',true,'Folder',folder);
fid=fopen(fullfile(folder,'units_report.json'),'w');
assert(fid>=0,'Could not write the unit test report in its output folder.');
cleanupReport=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));
disp(report);disp('SHARED_UNITS_ALL_PASSED');
end
function write_data(path,z)
fid=fopen(path,'w');assert(fid>=0);format=[repmat('%.17g\t',1,size(z,2)-1) '%.17g\n'];fprintf(fid,format,z');fclose(fid);
end
function e=rel(a,b)
assert(isequal(size(a),size(b)),'Array sizes differ.');assert(isequal(isnan(a),isnan(b)),'NaN masks differ.');
v=isfinite(a)&isfinite(b);d=abs(a(v)-b(v));if isempty(d),e=0;else,e=max(d)/max(1,max(abs(b(v))));end
end
