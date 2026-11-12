function report = test_merged_laos_batch()
% Exercise the real app on a sweep with repeated filenames and interrupted work.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
folder = tempname;
mkdir(folder);
cleanupFiles = onCleanup(@()rmdir(folder, 's')); %#ok<NASGU>
n = 48;
paths = makeSweep(folder, n);
bad = fullfile(folder, 'bad.csv');
writematrix(ones(10, 3), bad);

app = launch_merged_laos_analysis('Visible', 'off');
cleanupApp = onCleanup(@()delete(app)); %#ok<NASGU>
app.SPP.applySettings(struct('AveragingPolicy', 'manual', 'SelectionMode', 'average', ...
    'TrimCycles', [1 1], 'PointsPerCycle', 301, ...
    'AssessWindowSensitivity', false, 'AssessSmoothingSensitivity', false));

% Interrupt a batch from the event loop once some previews are complete.
% The same callback attempts a nested import, as a second Load click might.
stopped = false;
locked = false;
pulse = timer('ExecutionMode', 'fixedSpacing', 'Period', .01, 'TimerFcn', @stopLoading);
cleanupPulse = onCleanup(@()disposeTimer(pulse)); %#ok<NASGU>
start(pulse);
app.addFiles(paths);
stop(pulse);
assert(stopped && locked && ~app.Busy, 'Load did not accept Stop or block a nested import.');
pending = find(cellfun(@isempty, {app.Entries.Preview}));
assert(numel(app.Entries) == n && ~isempty(pending), 'Stop must leave remaining files available.');
app.selectFiles(pending(end));
checkWaveform(pending(end));

% Load the same sweep through the file-list workflow and isolate a bad file.
app.clearFiles();
app.addFiles([paths, {bad, paths{1}}]);
assert(numel(app.Entries) == n + 1, 'Adding the same path twice created a duplicate.');
assert(all(~cellfun(@isempty, {app.Entries(1:n).Preview})), 'Valid files lack previews.');
assert(isempty(app.Entries(end).Preview) && ~isempty(app.Entries(end).PreviewError));
assert(isequal({app.Entries.Path}, {app.FT.Entries.Path}, {app.SD.Entries.Path}, {app.SPP.Entries.Path}));

% Two files in different folders deliberately share the same basename.
% Require independently measured values and all three correct result sources.
selected = [n 1 n+1];
app.selectFiles(selected);
pulse.TimerFcn = @observeProgress;
samples = zeros(0,1);
sawWaiting = false;
sawFinishedWhileRunning = false;
wrongActiveRow = false;
wrongSelection = false;
start(pulse);
app.analyze('selected');
stop(pulse);
assert(isequal(app.SelectedIndices, selected), 'Analysis changed the highlighted rows.');
assert(sawWaiting && sawFinishedWhileRunning && ~wrongActiveRow && ~wrongSelection, ...
    'Live row states: Waiting=%d, finished with another running=%d, wrong active row=%d, selection changed=%d.', ...
    sawWaiting,sawFinishedWhileRunning,wrongActiveRow,wrongSelection);
assert(~isempty(samples) && all(diff(samples)>=0) && any(samples>0 & samples<100), ...
    'Expected the progress indicator to advance during the selected batch.');
assert(abs(app.Controls.BatchProgress.Position(3)-1)<1e-9, 'A completed batch must reach 100 percent.');
assert(startsWith(app.Controls.FileTable.Data{1,3},'Review (FT, SD'), ...
    'Both reconstruction methods should flag the deliberately distorted file.');
assert(ismember(app.Controls.FileTable.Data{end,3},{'Error','Input error'}), ...
    'A failed file needs its own error state.');
for module = {app.FT, app.SD, app.SPP}
    entries = module{1}.Entries;
    assert(isequal(find(~cellfun(@isempty, {entries.Result})), [1 n]), ...
        'A selected result was omitted or associated with an unselected file.');
    assert(strcmp(entries(end).Status, 'error') && isempty(entries(end).Result));
    for k = [1 n]
        assert(strcmp(entries(k).Result.source.path, app.Entries(k).Path));
    end
end

% A changed method selection must update the displayed results for all rows.
app.setMethods(struct('FT', true, 'Stress', false, 'SPP', false));
assert(strcmp(app.FT.Entries(n).Status,'ok') && strcmp(app.Controls.FileTable.Data{n,3},'Finished'));
assert(strcmp(app.FT.Entries(1).Status,'warning') && strcmp(app.Controls.FileTable.Data{1,3},'Review (FT)'));
for k = [1 n]
    app.Tabs.SelectedTab = app.Controls.InputTab;
    app.selectFiles(k);
    app.refresh();
    checkWaveform(k);
    app.Tabs.SelectedTab = app.Controls.FTTab;
    app.refresh();
    ft = app.Controls.FTTable.Data;
    i1 = ft{strcmp(ft(:, 1), 'I1'), 2};
    assert(i1 == app.FT.Entries(k).Result.I1, 'FT panel shows another file.');
    assert(abs(i1 / k - 150) < 1, 'Fundamental amplitude does not identify this input.');
end

% Losing one source must not discard another file with the same name or
% transfer cached results to a different row when the failed file is removed.
movefile(paths{1}, fullfile(folder, 'moved.csv'));
app.refresh();
for module = {app.FT, app.SD, app.SPP}
    assert(strcmp(module{1}.Entries(1).Status, 'stale'));
    assert(ismember(module{1}.Entries(n).Status, {'ok', 'warning'}));
end
app.selectFiles([1 n+1]);
app.removeSelected();
for module = {app.FT, app.SD, app.SPP}
    assert(strcmp(module{1}.Entries(end).Result.source.path, paths{n}));
end
assert(numel(app.Entries) == n - 1);

% Interrupt a previously pending file between selected methods. Retry those
% rows and make sure the earlier run's incomplete state is cleared.
retryRows=4:15;
app.selectFiles(retryRows);
app.setMethods(struct('FT',true,'Stress',true,'SPP',true));
partialRow=[];
% Stop at the first SD transition. A timer may run inside the final method;
% in that case the current file correctly finishes before Stop takes effect.
methodListener=addlistener(app.Controls.FileTable,'Data','PostSet',@stopBetweenMethods);
app.analyze('selected');
delete(methodListener);
assert(~isempty(partialRow) && strcmp(app.Controls.FileTable.Data{partialRow,3},'Partial'), ...
    'Stopping between two methods lost the partially completed file.');
stoppedFraction=app.Controls.BatchProgress.Position(3);
assert(stoppedFraction>0 && stoppedFraction<1 && ...
    contains(lower(app.Controls.BatchSummary.Text),'stop'), ...
    'The stopped batch must show an incomplete progress indicator.');
assert(~any(startsWith(string(app.Controls.FileTable.Data(:,3)),'Running')), ...
    'A running row remained after Stop.');
assert(isequal(app.SelectedIndices,retryRows));
app.analyze('selected');
assert(abs(app.Controls.BatchProgress.Position(3)-1)<1e-9);
states=string(app.Controls.FileTable.Data(retryRows,3));
assert(all(states=="Finished" | startsWith(states,"Review (")), ...
    'A rerun left temporary row states after its selected methods finished.');

% Stop FT partway through a run and preserve every finished, correctly keyed result.
app.Tabs.SelectedTab = app.Controls.InputTab;
app.selectFiles(3);
app.setMethods(struct('FT', true, 'Stress', false, 'SPP', false));
cached = [app.Entries.FTDone];
stopped = false;
pulse.TimerFcn = @stopAnalysis;
start(pulse);
app.analyze('all');
stop(pulse);
done = [app.Entries.FTDone];
assert(stopped && ~app.Busy && any(done & ~cached) && any(~done));
assert(isequal(app.SelectedIndices, 3));
for k = find(done)
    assert(strcmp(app.FT.Entries(k).Result.source.path, app.Entries(k).Path));
end
ftOnly=find(done & cellfun(@isempty,{app.SPP.Entries.Result}) & strcmp({app.FT.Entries.Status},'ok'),1);
assert(~isempty(ftOnly));
app.selectFiles(retryRows(end));  % Keep the checked row off the selection.
app.setMethods(struct('SPP',true));
assert(strcmp(app.Controls.FileTable.Data{ftOnly,3},'Partial'), ...
    'An unchecked row with a newly requested method still showed Finished.');
app.setMethods(struct('SPP',false));
assert(strcmp(app.Controls.FileTable.Data{ftOnly,3},'Finished'), ...
    'An unchecked method was counted toward an unselected row status.');
report = struct('passed', true, 'validFiles', n, 'samplesPerFile', 4800, ...
    'pendingWhenStopped', numel(pending), 'newFTResultsBeforeStop', nnz(done & ~cached), ...
    'liveProgressSamples',numel(samples),'stoppedBetweenMethods',true, ...
    'matlab', version);
disp(report);

    function stopLoading(~, ~)
        if ~isvalid(app) || ~app.Busy || numel(app.Entries) ~= n || stopped, return; end
        present = ~cellfun(@isempty, {app.Entries.Preview});
        if ~any(present) || all(present), return; end
        stopped = true;
        try
            app.addFiles(bad);
        catch ME
            locked = strcmp(ME.identifier, 'MergedLAOS:Busy');
        end
        app.requestCancel();
    end

    function stopAnalysis(~, ~)
        if isvalid(app) && app.Busy && ~stopped && any([app.Entries.FTDone] & ~cached)
            stopped = true;
            app.requestCancel();
        end
    end

    function observeProgress(~,~)
        if ~isvalid(app) || ~app.Busy, return; end
        states=string(app.Controls.FileTable.Data(:,3));
        running=find(startsWith(states,'Running'));
        if isempty(running), return; end
        wrongActiveRow=wrongActiveRow || numel(running)~=1 || ~all(ismember(running,selected));
        wrongSelection=wrongSelection || ~isequal(app.SelectedIndices,selected);
        sawWaiting=sawWaiting || any(states(selected)=="Waiting");
        sawFinishedWhileRunning=sawFinishedWhileRunning || any(states(selected)=="Finished" | startsWith(states(selected),"Review ("));
        samples(end+1)=100*app.Controls.BatchProgress.Position(3);
    end

    function stopBetweenMethods(~,~)
        if ~isvalid(app) || ~app.Busy || ~isempty(partialRow), return; end
        states=string(app.Controls.FileTable.Data(retryRows,3));
        j=find(states=="Running: SD",1);
        if isempty(j), return; end
        row=retryRows(j);
        if app.Entries(row).FTDone && isempty(app.SPP.Entries(row).Result)
            partialRow=row;
            stopButton=app.Controls.Stop;
            stopButton.ButtonPushedFcn(stopButton,[]);
        end
    end

    function checkWaveform(k)
        drawnow;
        assert(app.FT.SelectedIndex == k && app.SD.SelectedIndex == k && app.SPP.SelectedIndex == k);
        preview = app.Entries(k).Preview;
        assert(strcmp(preview.source.path, paths{k}));
        assert(abs(preview.strainAmplitudePercent - k) < .001);
        line = findobj(app.Axes.Strain, 'Type', 'line');
        assert(isscalar(line) && abs(max(line.YData) - k) < .001, 'Wrong input waveform on screen.');
    end
end

function paths = makeSweep(folder, n)
mkdir(fullfile(folder, 'first'));
mkdir(fullfile(folder, 'last'));
t = (0:4799)' / 240;
phase = 2*pi*t;
paths = cell(1, n);
for k = 1:n
    if k == 1
        path = fullfile(folder, 'first', 'repeat.csv');
    elseif k == n
        path = fullfile(folder, 'last', 'repeat.csv');
    else
        path = fullfile(folder, sprintf('sweep_%02d.csv', k));
    end
    stress=k*(150*sin(phase+.18)+sin(3*phase-.2));
    if k==1
        % A fifth harmonic outside the FT/SD reconstruction raises a genuine warning.
        stress=stress+90*sin(5*phase+.13);
    end
    writematrix([t k*sin(phase) stress], path);
    [~, info] = fileattrib(path);
    paths{k} = info.Name;
end
end

function disposeTimer(t)
if isvalid(t)
    stop(t);
    delete(t);
end
end
