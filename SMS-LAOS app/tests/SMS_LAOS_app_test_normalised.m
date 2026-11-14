function report = SMS_LAOS_app_test_normalised(outputFolder)
% Check persisted normalised axes and scale factors on individual and overlay exports.
if nargin<1, outputFolder=tempname; end
assert(~isfolder(outputFolder),'Choose a new output folder.');
mkdir(outputFolder);
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'core'),fullfile(root,'modules','ft','core'));
t=(0:3300)'/170;
previews=cell(1,2);results=cell(1,2);
for j=1:2
    g=(0.05*j+.014).*(1+.3*cos(.5*t)).*sin(2*pi*t)+.01;
    s=(120*j+15*sin(.1*t)).*(sin(2*pi*t+.4)+.1*cos(6*pi*t))+17;
    file=fullfile(outputFolder,sprintf('sample_%d.csv',j));writematrix([t,g,s],file);
    input=struct('StrainUnit','decimal');
    previews{j}=SMS_LAOS_app_preview(file,input);
    results{j}=SMS_LAOS_app_analyze_FT_SD(file,SMS_LAOS_app_FT_SD_defaults(),input);
end
opts=struct('AxisScale','both','CycleMode','last_n','LastNCycles',2,'IncludeElasticStrain',true, ...
    'IncludeViscousRate',true,'FormatPNG',false,'FormatPDF',false,'FormatFIG',true);
fractions=[];messages={};folder=fullfile(outputFolder,'individual');
initialFigures=findall(groot,'Type','figure');
SMS_LAOS_app_export_lissajous(previews,folder,opts,results,@record);
assert(isequal(initialFigures,findall(groot,'Type','figure')),'Hidden figures leaked.');
m=jsondecode(fileread(fullfile(folder,'manifest.json')));
assert(all(diff(fractions)>=0) && fractions(1)==0 && fractions(end)==1);
assert(nnz(startsWith(messages,'Writing FIG:'))==16);
assert(numel(m.entries)==2 && numel(dir(fullfile(folder,'*.fig')))==16);
for j=1:2
    r=results{j};mask=r.time>=r.time(end)-2/r.freq_hz;
    expected=[max(abs(r.strain(mask))),max(abs(r.gammadot(mask))),max(abs(r.stress(mask)))];
    entry=m.entries(j);scales=entry.scaleFactors;
    same([scales.strain scales.strainRate_per_s scales.totalStress_Pa],expected);
    tab=readtable(fullfile(folder,entry.decompositionCSV));
    same(tab.ElasticStress_normalised,r.stress_elastic(mask)/expected(3));
    same(tab.ViscousStress_normalised,r.stress_viscous(mask)/expected(3));
    same(tab.TotalStress_normalised,r.stress(mask)/expected(3));
    same(tab.Strain_normalised,r.strain(mask)/expected(1));
    same(tab.StrainRate_normalised,r.gammadot(mask)/expected(2));
    for specIndex=1:numel(m.plots)
        spec=m.plots(specIndex);file=string(entry.figures);
        file=file(endsWith(file,['_',spec.suffix,'.fig']));
        check_saved(fullfile(folder,file),spec,tab,entry.sourceName);
    end
end
assert(m.entries(1).scaleFactors.totalStress_Pa~=m.entries(2).scaleFactors.totalStress_Pa);
opts.AxisScale='normalised';opts.Mode='overlay';opts.IncludeElasticStrain=false;opts.IncludeViscousRate=false;
folder=fullfile(outputFolder,'overlay');m=SMS_LAOS_app_export_lissajous(previews,folder,opts);
assert(numel(m.plots)==2 && numel(dir(fullfile(folder,'*.fig')))==2);
for j=1:2
    p=previews{j};entry=m.entries(j);
    mask=p.time>=p.time(end)-2/p.frequencyHz;
    tab=readtable(fullfile(folder,entry.curveCSV));
    same(tab.TotalStress_normalised,p.stress(mask)/max(abs(p.stress(mask))));
    for spec=m.plots
        check_saved(fullfile(folder,['overlay_',spec.suffix,'.fig']),spec,tab,entry.sourceName);
    end
end

% Zero on an unused axis is valid; subnormal but usable inputs need no cutoff.
p=previews{1};opts.IncludeStressRate=false;p.strainRate(:)=0;p.stress(:)=realmin/2;
folder=fullfile(outputFolder,'tiny');m=SMS_LAOS_app_export_lissajous(p,folder,opts);
assert(isempty(m.entries.scaleFactors.strainRate_per_s));
tab=readtable(fullfile(folder,m.entries.curveCSV));same(tab.TotalStress_normalised,ones(height(tab),1));
opts.IncludeStressRate=true;reject(@()SMS_LAOS_app_export_lissajous(p,fullfile(outputFolder,'zeroRate'),opts),'MergedLAOS:LissajousScale');
p=previews{1};p.stress(:)=NaN;
reject(@()SMS_LAOS_app_export_lissajous(p,fullfile(outputFolder,'nan'),opts),'MergedLAOS:LissajousScale');
p.stress(:)=0;
reject(@()SMS_LAOS_app_export_lissajous(p,fullfile(outputFolder,'zero'),opts),'MergedLAOS:LissajousScale');

% Cancellation discards pending staged outputs, even at the publish boundary.
for cancelAt={'Writing FIG:','Publishing'}
    stageBefore=sort(string({dir(outputFolder).name}));folder=fullfile(outputFolder,'cancelled');
    reject(@()SMS_LAOS_app_export_lissajous(previews,folder,opts,[],@cancel),'Test:Cancel');
    assert(isequal(stageBefore,sort(string({dir(outputFolder).name}))));
    assert(isequal(initialFigures,findall(groot,'Type','figure')));
end
report=struct('Passed',true,'OutputFolder',outputFolder,'MATLAB',version);

    function record(fraction,message)
        fractions(end+1)=fraction;
        messages{end+1}=message;
    end
    function cancel(~,message)
        if startsWith(message,cancelAt{1}),error('Test:Cancel','Cancelled test export.');end
    end
end

function check_saved(file,spec,tab,sourceName)
f=openfig(file,'new','invisible');cleanup=onCleanup(@()delete(f)); %#ok<NASGU>
ax=findobj(f,'Type','axes');trace=findobj(ax,'Type','line');
trace=trace(contains(string({trace.DisplayName}),sourceName));assert(isscalar(trace));
assert(strcmp(ax.XLabel.String,spec.xLabel) && strcmp(ax.YLabel.String,spec.yLabel));
same(trace.XData(:),tab.(spec.xColumn));
same(trace.YData(:),tab.(spec.yColumn));
end

function same(a,b)
assert(isequal(size(a),size(b)) && all(isfinite(a(:))) && max(abs(a(:)-b(:)))<=1e-12*max(1,max(abs(b(:)))));
end

function reject(f,id)
try, f();catch ME, assert(strcmp(ME.identifier,id),'Received %s: %s',ME.identifier,ME.message);return,end
error('Test:ExpectedError','Expected %s.',id);
end
