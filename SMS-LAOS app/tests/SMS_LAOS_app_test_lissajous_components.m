function report = SMS_LAOS_app_test_lissajous_components(outputFolder)
% Reopen saved figures and check every line against the selected method's samples.
if nargin < 1, outputFolder = tempname; end
assert(~isfolder(outputFolder), 'Choose a new output folder.');
mkdir(outputFolder);
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
app = SMS_LAOS_app('Visible','off');
cleanupApp = onCleanup(@()delete(app)); %#ok<NASGU>

% Nonzero offsets, a drifting stress amplitude and nonunit omega distinguish
% measured, centered, decomposed and omega-normalized coordinates.
t = 10.37 + (0:3190)'/161.47;
phase = 2*pi*(t-t(1));
paths = cell(1,4);
paths{1} = fullfile(outputFolder,'invalid_time.csv');
writematrix(ones(20,3),paths{1});
names = {'sample_A','sample_B','outside_target'};
amplitudes = [10,10,4];
for j = 1:3
    stress = 70*j + (140+20*j+t).*sin(phase+.2*j) + 20*cos(3*phase);
    paths{j+1} = fullfile(outputFolder,[names{j} '.csv']);
    writematrix([t,1+amplitudes(j)*sin(phase),stress],paths{j+1});
end
app.addFiles(paths);
assert(isempty(app.Entries(1).Preview));
assert(~isempty(app.Entries(2).Preview) && ~isempty(app.Entries(3).Preview));
c = app.Controls;
assert(c.IncludeStressStrain.Value && c.IncludeStressRate.Value);
assert(~c.IncludeElasticStrain.Value && ~c.IncludeViscousRate.Value);
c.TargetStrain.Value = 10;
c.StrainTolerance.Value = .1;
c.CycleMode.Value = 'all';
c.LissajousMode.Value = 'per_file';
c.PNG.Value = false;
c.PDF.Value = false;
c.FIG.Value = true;

% Only FT is available; component export must never substitute its result.
app.setMethods(struct('FT',true,'Stress',false,'SPP',false));
app.FT.applySettings(struct('cycle_selection_mode','last_n_cycles','last_n_cycles',3));
app.selectFiles([2 3]); app.analyze('selected');
c.IncludeElasticStrain.Value = true;
c.IncludeViscousRate.Value = true;
folder = fullfile(outputFolder,'ft_only');
rejectExport(@()app.exportLissajous(folder),folder,'MergedLAOS:LissajousSD');

% The first matched row has SD, but the second does not.
app.setMethods(struct('FT',false,'Stress',true,'SPP',false));
app.selectFiles(2); app.analyze('selected');
folder = fullfile(outputFolder,'incomplete_sd');
rejectExport(@()app.exportLissajous(folder),folder,'MergedLAOS:LissajousSD');
app.selectFiles(3); app.analyze('selected');
previews = {app.Entries(2:3).Preview};
results = {app.SD.Entries(2:3).Result};
assert(numel(results{1}.time) ~= numel(app.FT.Entries(2).Result.time));
assert(isempty(app.SD.Entries(4).Result)); % unmatched file needs no SD

% With components selected, all four figures share the native SD samples.
individual = fullfile(outputFolder,'individual');
app.exportLissajous(individual);
manifest = jsondecode(fileread(fullfile(individual,'manifest.json')));
assert(manifest.matchedCount == 2 && numel(dir(fullfile(individual,'*.fig'))) == 8);
kinds = {'_total_stress_strain.fig','_total_stress_strain_rate.fig', ...
    '_elastic_stress_strain.fig','_viscous_stress_strain_rate.fig'};
for j = 1:2
    row = manifest.entries(j);
    assert(strcmp(row.sourceName,previews{j}.source.name) && row.inputIndex==j+1);
    assert(strcmp(row.curveCSV,row.decompositionCSV));
    checkCsv(individual,row,results{j},true(size(results{j}.time)));
    for kind = 1:4
        figNames = string(row.figures);
        file = figNames(endsWith(figNames,kinds{kind}));
        assert(isscalar(file),'Expected a single figure for each requested curve.');
        checkFigure(fullfile(individual,file),kind,previews(j),results(j),[],true);
    end
end

% The three requested plots together should all use identical coordinates
% even when an endpoint-exclusive SD grid is one sample short of N periods.
r = results{1};
options = struct('IncludeStressStrain',true,'IncludeStressRate',false, ...
    'IncludeElasticStrain',true,'IncludeViscousRate',true,'CycleMode','last_n', ...
    'LastNCycles',r.n_cycles_used,'FormatFIG',true,'FormatPNG',false,'FormatPDF',false);
three = fullfile(outputFolder,'three_curves');
one = SMS_LAOS_app_export_lissajous(previews(1),three,options,results(1));
figNames = string(one.entries.figures);
assert(numel(figNames)==3);
for kind = [1 3 4]
    filename = figNames(endsWith(figNames,kinds{kind}));
    assert(isscalar(filename));
    checkFigure(fullfile(three,filename),kind,previews(1),results(1),[],true);
end

% Full Export results uses the two cached SD entries even when the method
% is unchecked for full method-package export. Only real viscous lines
% should appear in this overlay, despite another valid preview outside target.
app.setMethods(struct('FT',true,'Stress',false,'SPP',false));
c.ExportLissajous.Value = true;
c.ExportWaveforms.Value = false;
c.IncludeStressStrain.Value = false;
c.IncludeStressRate.Value = false;
c.IncludeElasticStrain.Value = false;
c.LissajousMode.Value = 'overlay';
c.CycleMode.Value = 'last_n';
c.LastNCycles.Value = 2;
central = fullfile(outputFolder,'central');
app.exportResults(central);
manifest = jsondecode(fileread(fullfile(central,'manifest.json')));
assert(manifest.exportedStressCount == 0);
output = fullfile(central,'Lissajous');
manifest = jsondecode(fileread(fullfile(output,'manifest.json')));
assert(manifest.matchedCount == 2 && numel(dir(fullfile(output,'*.fig'))) == 1);
checkFigure(fullfile(output,['overlay' kinds{4}]),4,previews,results,c.LastNCycles.Value,true);
for j = 1:2
    row = manifest.entries(j);
    assert(strcmp(row.sourceName,previews{j}.source.name) && row.inputIndex==j+1 && isempty(row.curveCSV));
    r = results{j};
    mask = r.time >= r.time(end)-c.LastNCycles.Value/r.freq_hz;
    checkCsv(output,row,r,mask);
end

% Wrong SD row, old SD settings, and no plot selections must fail cleanly.
folder = fullfile(outputFolder,'wrong_source');
options = struct('IncludeStressStrain',false,'IncludeStressRate',false, ...
    'IncludeElasticStrain',true,'CycleMode','all','FormatFIG',true,'FormatPNG',false,'FormatPDF',false);
rejectExport(@()SMS_LAOS_app_export_lissajous(previews,folder,options,fliplr(results)),folder,'MergedLAOS:LissajousSD');
app.SD.applySettings(struct('cycle_selection_mode','last_n_cycles','last_n_cycles',4));
folder = fullfile(outputFolder,'stale_standalone');
rejectExport(@()app.exportLissajous(folder),folder,'MergedLAOS:LissajousSD');
folder = fullfile(outputFolder,'stale_central');
rejectExport(@()app.exportResults(folder),folder,'MergedLAOS:LissajousSD');
c.IncludeViscousRate.Value = false;
folder = fullfile(outputFolder,'no_plots');
rejectExport(@()app.exportLissajous(folder),folder,'MergedLAOS:LissajousPlots');

% A single requested measured plot still works without a current SD.
c.IncludeStressStrain.Value = true;
folder = fullfile(outputFolder,'only_measured');
app.exportLissajous(folder);
assert(numel(dir(fullfile(folder,'*.fig'))) == 1);
checkFigure(fullfile(folder,'overlay_elastic.fig'),1,previews,results,c.LastNCycles.Value,false);

% Select two nonadjacent source rows, including a 4% file that lies
% outside the target range, and leave one of the equal-amplitude files off.
c.StrainMatchMode.Value = 'checked';
if ~isempty(c.StrainMatchMode.ValueChangedFcn)
    c.StrainMatchMode.ValueChangedFcn(c.StrainMatchMode,[]);
end
tablePaths = string(c.StrainChoices.UserData(:));
assert(isequal(sort(tablePaths),sort(string({app.Entries(2:4).Path})')));
assert(tablePaths(1)==string(app.Entries(4).Path),'The lowest amplitude should appear first.');
rows = c.StrainChoices.Data;
chosen = [2 4];
for k = 1:size(rows,1)
    rows{k,1} = ismember(tablePaths(k),string({app.Entries(chosen).Path}));
end
c.StrainChoices.Data = rows;
folder = fullfile(outputFolder,'checked_files');
app.exportLissajous(folder);
exact = jsondecode(fileread(fullfile(folder,'manifest.json')));
assert(strcmp(exact.selectionMode,'selected_files'));
assert(isequal(sort([exact.entries.inputIndex]),chosen));
assert(isequal(sort(string({exact.entries.sourcePath})),sort(string({app.Entries(chosen).Path}))));
assert(numel(dir(fullfile(folder,'*.fig')))==1);
checkFigure(fullfile(folder,'overlay_elastic.fig'),1,{app.Entries(chosen).Preview},{},c.LastNCycles.Value,false);
folder = fullfile(outputFolder,'checked_central');
app.exportResults(folder);
exact = jsondecode(fileread(fullfile(folder,'Lissajous','manifest.json')));
assert(strcmp(exact.selectionMode,'selected_files') && isequal(sort([exact.entries.inputIndex]),chosen));
rows = c.StrainChoices.Data;
rows(:,1) = {false};
c.StrainChoices.Data = rows;
folder = fullfile(outputFolder,'empty_selection');
rejectExport(@()app.exportLissajous(folder),folder,'MergedLAOS:LissajousSelection');
c.ExportLissajous.Value = false;
folder = fullfile(outputFolder,'empty_checklist_ft_only');
manifest = app.exportResults(folder);
assert(manifest.exportedFTCount==2 && ~isfield(manifest.modules,'Lissajous'));
report = struct('Passed',true,'OutputFolder',outputFolder,'MATLAB',version);
end

function checkCsv(folder,entry,r,mask)
decomposition = readtable(fullfile(folder,entry.decompositionCSV));
sourceTime = r.time_raw(r.selected_mask);
closeEnough(decomposition.Time_s,r.time(mask));
closeEnough(decomposition.SourceTime_s,sourceTime(mask));
closeEnough(decomposition.Strain_percent,100*r.strain(mask));
closeEnough(decomposition.StrainRate_per_s,r.gammadot(mask));
closeEnough(decomposition.Stress_Pa,r.stress(mask));
closeEnough(decomposition.ElasticStress_Pa,r.stress_elastic(mask));
closeEnough(decomposition.ViscousStress_Pa,r.stress_viscous(mask));
end

function checkFigure(file,kind,previews,results,lastN,usingSD)
fig = openfig(file,'new','invisible');
cleanupFig = onCleanup(@()delete(fig)); %#ok<NASGU>
ax = findobj(fig,'Type','axes');
assert(isscalar(ax));
lines = findobj(ax,'Type','line');
assert(numel(lines) == numel(previews));
for j = 1:numel(previews)
    p = previews{j};
    if ~usingSD
        t = p.time; f = p.frequencyHz; y = p.stress;
        if kind == 1, x = 100*p.strain; else, x = p.strainRate; end
    else
        r = results{j};
        t = r.time; f = r.freq_hz;
        switch kind
            case 1, x = 100*r.strain; y = r.stress;
            case 2, x = r.gammadot; y = r.stress;
            case 3, x = 100*r.strain; y = r.stress_elastic;
            case 4, x = r.gammadot; y = r.stress_viscous;
        end
    end
    mask = true(size(t));
    if ~isempty(lastN), mask = t >= t(end)-lastN/f; end
    line = lines(contains(string({lines.DisplayName}),p.source.name));
    assert(isscalar(line),'Saved legend does not identify the input file.');
    assert(isequal(line.XData(:),x(mask)) && isequal(line.YData(:),y(mask)), ...
        'Saved figure coordinates differ from the corresponding native arrays in %s.',file);
end
end

function closeEnough(actual,expected)
assert(isequal(size(actual),size(expected)));
assert(max(abs(actual-expected)) <= 5e-13*max(1,max(abs(expected))), ...
    'CSV values differ from the plotted source arrays.');
end

function rejectExport(run,folder,id)
try
    run();
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, received %s: %s',id,ME.identifier,ME.message);
    assert(~isfolder(folder),'Failed export published an output folder.');
    return
end
error('Test:MissingError','Expected %s.',id);
end
