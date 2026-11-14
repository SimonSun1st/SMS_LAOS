function report=SMS_LAOS_app_test_export_workspace()
% Exercise folder identity, export scope, cancellation and retry through the app.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
out=tempname;mkdir(out);one=fullfile(out,'run.one');two=fullfile(out,'run.two');
mkdir(one);mkdir(two);
example=fullfile(root,'modules','ft','examples','SMS-LAOS app synthetic demo.dat');
copyfile(example,fullfile(one,'sample.dat'));copyfile(example,fullfile(two,'sample.dat'));
app=SMS_LAOS_app('Visible','off');finish=onCleanup(@()delete(app)); %#ok<NASGU>
app.setStrainUnit('decimal');c=app.Controls;
assert(strcmp(c.SourceFolder.Text,'Folder: —'));
app.addFolder(one);assert(strcmp(c.SourceFolder.Text,'Folder: run.one'));
app.addFolder(two);app.selectFiles(2);
assert(strcmp(c.SourceFolder.Text,'Folder: run.two (+1)') && contains(c.SourceFolder.Tooltip,one));
app.removeSelected();assert(strcmp(c.SourceFolder.Text,'Folder: run.one'));
app.addFolder(two);
app.Tabs.SelectedTab=c.ExportTab;
c.ExportScope.Value='plots';c.ExportScope.ValueChangedFcn(c.ExportScope,[]);
assert(strcmp(c.StrainMatchMode.Value,'checked') && strcmp(c.PlotSettings.Visible,'on'));
assert(strcmp(c.ResultSettings.Visible,'off') && ~c.ExportLissajous.Value);
c.StrainChoices.Data{1,1}=true;c.AxisScale.Value='normalised';
c.ExportScope.Value='both';c.ExportScope.ValueChangedFcn(c.ExportScope,[]);
assert(c.ExportLissajous.Value && c.StrainChoices.Data{1,1} && strcmp(c.ResultSettings.Visible,'on'));
c.ExportScope.Value='plots';c.ExportScope.ValueChangedFcn(c.ExportScope,[]);
cancelled=false;probe=timer('ExecutionMode','fixedSpacing','Period',.05,'TimerFcn',@cancel);
stopProbe=onCleanup(@()disposeTimer(probe)); %#ok<NASGU>
destination=fullfile(out,'cancelled');start(probe);
try
    app.exportLissajous(destination);
    error('Test:Cancel','Export did not accept cancellation.');
catch ME
    assert(strcmp(ME.identifier,'MergedLAOS:ExportCancelled'),'%s',ME.message);
end
stop(probe);
assert(cancelled && ~app.Busy && ~isfolder(destination) && isempty(app.LastExport));
assert(strcmp(c.ExportProgress.Text,'Export cancelled.') && strcmp(c.CancelExport.Visible,'off'));
success=fullfile(out,'retry');m=app.exportLissajous(success);
assert(m.matchedCount==1 && numel(dir(fullfile(success,'*_normalised.png')))==2);
assert(strcmp(app.LastExport,success) && contains(c.ExportProgress.Text,'100%'));
app.clearFiles();assert(strcmp(c.SourceFolder.Text,'Folder: —') && isempty(c.SourceFolder.Tooltip));
report=struct('Passed',true);

    function cancel(~,~)
        if ~cancelled && app.Busy && strcmp(c.CancelExport.Enable,'on')
            cancelled=true;c.CancelExport.ButtonPushedFcn(c.CancelExport,[]);
        end
    end
end
function disposeTimer(t)
if isvalid(t),stop(t);delete(t);end
end
