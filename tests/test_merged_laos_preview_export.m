function report=test_merged_laos_preview_export
root=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(root,'core'));
d=tempname;mkdir(d); t=(0:.002:8.4)';q=2*pi*1.7*t;
a=fullfile(d,'percent.dat');b=fullfile(d,'decimal.csv');h=fullfile(d,'header.tsv');
writematrix([t 10*sin(q) 20*sin(q)+4*cos(q)],a,'Delimiter','tab');
writematrix([t .1*sin(q) 20*sin(q)+4*cos(q)],b);
T=array2table([t 10*sin(q) 20*sin(q)+4*cos(q)],'VariableNames',{'Time','Strain','Stress'});writetable(T,h,'FileType','text','Delimiter','tab');
P=merged_laos_preview(a);D=merged_laos_preview(b,struct('StrainUnit','decimal'));H=merged_laos_preview(h);H0=merged_laos_preview(h,struct('HeaderLines',0));
assert(max(abs(P.strain-D.strain))<1e-14);assert(max(abs(P.strain-H.strain))<1e-14);assert(max(abs(P.strain-H0.strain))<1e-14);
assert(abs(P.frequencyHz-1.7)<1e-5);assert(abs(P.strainAmplitudePercent-10)<.005);
assert(max(abs(P.strainRate(2:end-1)-.1*2*pi*1.7*cos(q(2:end-1))))<1e-3);
out=fullfile(d,'overlay');M=merged_laos_export_lissajous({P,D},out,struct('TargetStrainPercent',10,'TolerancePercent',.01,'Mode','overlay','LastNCycles',2,'FormatPDF',false));
assert(M.matchedCount==2);assert(numel(M.files)==5);
C=readtable(fullfile(out,M.entries(1).curveCSV));mask=P.time>=P.time(end)-2/P.frequencyHz;
assert(max(abs(C.Time_s-P.time(mask)))<1e-12);assert(max(abs(C.StrainRate_per_s-P.strainRate(mask)))<1e-12);assert(max(abs(C.Stress_Pa-P.stress(mask)))<1e-12);
must_error(@()merged_laos_export_lissajous({P},out,struct()),'MergedLAOS:LissajousExists');
must_error(@()merged_laos_export_lissajous({P},fullfile(d,'nomatch'),struct('TargetStrainPercent',100,'TolerancePercent',.1)),'MergedLAOS:LissajousNoMatch');assert(~isfolder(fullfile(d,'nomatch')));
must_error(@()merged_laos_export_lissajous({P},fullfile(d,'short'),struct('LastNCycles',100)),'MergedLAOS:LissajousWindow');
stale=P;stale.source.signature.Bytes=1;must_error(@()merged_laos_export_lissajous({stale},fullfile(d,'stale'),struct()),'MergedLAOS:SourceChanged');
dup=fullfile(d,'duplicate.dat');bad=t;bad(4)=bad(3);writematrix([bad 10*sin(q) sin(q)],dup,'Delimiter','tab');must_error(@()merged_laos_preview(dup),'MergedLAOS:PreviewTime');
constant=fullfile(d,'constant.dat');writematrix([t ones(size(t)) sin(q)],constant,'Delimiter','tab');must_error(@()merged_laos_preview(constant),'MergedLAOS:PreviewFrequency');
shift=fullfile(d,'columns.csv');writematrix([20*sin(q)+4*cos(q) t 10*sin(q)],shift);S=merged_laos_preview(shift,struct('TimeColumn',2,'StrainColumn',3,'StressColumn',1));assert(isequal(S.strain,P.strain));
report=struct('passed',true,'MATLAB',version,'directory',d,'checks',{{'percent_decimal_parity','header_auto_and_zero','known_frequency','known_rate','amplitude','overlay','csv_plotted_array_parity','non_overwrite','no_match','short_window','stale_source','duplicate_time_rejection','constant_strain_rejection','column_mapping'}});
fid=fopen(fullfile(d,'report.json'),'w');fprintf(fid,'%s',jsonencode(report,'PrettyPrint',true));fclose(fid);disp(jsonencode(report,'PrettyPrint',true));
a=checkcode('merged_laos_preview.m','-id');b=checkcode('merged_laos_export_lissajous.m','-id');for j=1:numel(a),disp(a(j));end;for j=1:numel(b),disp(b(j));end
end
function must_error(f,id)
try,f();catch ME,assert(strcmp(ME.identifier,id),ME.message);return,end
error('Test:ExpectedFailure','Expected failure %s',id);
end
