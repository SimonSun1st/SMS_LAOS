function report = test_sms_laos_review()
% Exercise the file table's selection callback and the recorded quality diagnostics.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
folder = tempname;
mkdir(folder);
cleanupFiles = onCleanup(@()rmdir(folder, 's')); %#ok<NASGU>
paths = cell(1, 3);
cycles = [20 10 10];
for k = 1:numel(cycles)
    time = (0:cycles(k)*240-1)' / 240;
    phase = 2*pi*time;
    stress = 150*sin(phase+.18) + sin(3*phase-.2);
    if k == 3
        stress = stress + 90*sin(5*phase+.13);
    end
    paths{k} = fullfile(folder, sprintf('waveform_%d.csv', k));
    writematrix([time sin(phase) stress], paths{k});
end

app = launch_SMS_LAOS('Visible','off');
cleanupApp = onCleanup(@()delete(app)); %#ok<NASGU>
assert(strcmp(app.Figure.Name, 'SMS-LAOS'));
% The two short inputs cannot supply 14 complete cycles. The last input
% also has a fifth harmonic outside the FT and SD reconstructions.
app.SPP.applySettings(struct('AveragingPolicy','stable_tail','MinStableCycles',14, ...
    'PointsPerCycle',301,'AssessWindowSensitivity',false,'AssessSmoothingSensitivity',false));
app.addFiles(paths);
app.analyze('all');
fileTable = app.Controls.FileTable;
states = string(fileTable.Data(:,3));
assert(isequal(states, ["Finished"; "Review (SPP)"; "Review (FT, SD, SPP)"]), ...
    'Unexpected all-method row states: %s', strjoin(states, ', '));
assert(contains(app.Controls.BatchSummary.Text, '2 review', 'IgnoreCase', true));

% Keep a method tab open while selecting a different file, as in normal use.
app.Tabs.SelectedTab = app.Controls.FTTab;
clickRow(2);
assert(strcmp(app.SPP.Entries(2).Result.selection.status, 'no_stable_tail'));
assertReasons(2, {'SPP'});
clickRow(3);
assertReasons(3, {'FT','SD','SPP'});
clickRow(1);
assertReasons(1, {});
clickRow(2);
assertReasons(2, {'SPP'});

clickRow(3);
app.setMethods(struct('FT',false,'SPP',false));
assert(strcmp(fileTable.Data{3,3}, 'Review (SD)'));
assertReasons(3, {'SD'});
assert(strcmp(fileTable.Data{2,3}, 'Finished'));
app.setMethods(struct('Stress',false,'SPP',true));
assert(strcmp(fileTable.Data{3,3}, 'Review (SPP)'));
assertReasons(3, {'SPP'});
app.SPP.applySettings(struct('MinStableCycles',15));
assert(strcmp(fileTable.Data{3,3}, 'Stale'));
assertReasons(3, {});
app.clearFiles();
assert(isempty(fileTable.Data));
assertReasons([], {});
report = struct('Passed',true, 'AllMethodsStates',states, 'MATLABVersion',version);

    function clickRow(index)
        fileTable.Selection = index;
        fileTable.SelectionChangedFcn(fileTable, struct('Selection',index));
        assert(isequal(app.SelectedIndices, index));
        assert(isequal(app.Tabs.SelectedTab, app.Controls.FTTab));
    end

    function assertReasons(index, methods)
        details = app.Controls.ReviewDetails;
        assert(strcmp(details.Visible,'on') == ~isempty(methods), ...
            'The review panel visibility does not match the selected file.');
        shown = string(details.Value(:));
        warnings = shown(strlength(shown) > 0);
        expected = strings(0,1);
        for j = 1:numel(methods)
            name = methods{j};
            messages = string(app.(name).Entries(index).Result.quality.messages);
            assert(~isempty(messages), 'Fixture lacks a diagnostic for %s.', name);
            expected = [expected; name + ": " + messages(:)]; %#ok<AGROW>
        end
        assert(isequal(warnings(:), expected), ...
            'Review details do not match the current row and checked methods.');
    end
end
