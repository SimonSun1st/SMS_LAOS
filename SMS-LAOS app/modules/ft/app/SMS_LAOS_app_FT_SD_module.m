classdef SMS_LAOS_app_FT_SD_module < handle
    %SMS_LAOS_APP_FT_SD_MODULE Embedded or standalone original SMS-LAOS v2 views.
    % Numerical results are produced by SMS_LAOS_app_analyze_FT_SD_file. This class
    % manages the interface and result snapshots; it does not alter curves.
    properties
        StateChangedFcn=[]
    end
    properties (SetAccess=private)
        Figure
        Controls=struct()
        FileTable
        Tabs
        Axes=struct()
        Entries=struct('Path',{},'Name',{},'Status',{},'Result',{}, ...
            'Error',{},'Options',{},'SourceSignature',{},'StaleReason',{},'InputSettings',{})
        SelectedIndex=0
        Busy=false
        LastExport=''
        InputSettings=struct()
        Role='stress'
    end
    properties (Access=private)
        Root
        Parent=[]
        Embedded=false
        HostLocked=false
        GlobalStrainUnit='decimal'
        FrequencyUnit='Hz'
        Body=[]
        HiddenControls=[]
        Font='Arial'
        CancelRequested=false
        CloseAfterRun=false
        IsExporting=false
        ParameterControls={}
        ActionControls={}
        Cards=struct()
        ViewRevision=0
        SummaryRevision=0
        RenderedTabs=struct()
        PlotObjects=struct()
        HeaderKey=[]
        ResultsKey=[]
        TableRows={}
        TableWarningRows=[]
        TableFailedRows=[]
        Background=[.95 .96 .98]
        Ink=[.12 .18 .27]
        Blue=[.12 .35 .69]
        Orange=[.66 .35 .05]
    end
    methods
        function app=SMS_LAOS_app_FT_SD_module(varargin)
            p=inputParser;
            p.addParameter('Visible','on',@(x) any(strcmpi(x,{'on','off'})));
            p.addParameter('Parent',[]);
            p.addParameter('HostFigure',[]);
            p.addParameter('Role','stress',@(x)any(strcmp(char(x),{'ft','stress'})));
            p.parse(varargin{:});
            app.Parent=p.Results.Parent; app.Embedded=~isempty(app.Parent);app.Role=char(p.Results.Role);
            if app.Embedded
                if ~isgraphics(app.Parent), error('SMSApp:Parent','Parent must be a valid UI container.'); end
                app.Figure=p.Results.HostFigure;
                if isempty(app.Figure), app.Figure=ancestor(app.Parent,'figure'); end
                if isempty(app.Figure) || ~isgraphics(app.Figure,'figure')
                    error('SMSApp:Parent','An embedded module requires a valid host figure.');
                end
            elseif ~isempty(p.Results.HostFigure)
                error('SMSApp:Parent','HostFigure requires Parent.');
            end
            app.Root=fileparts(fileparts(mfilename('fullpath')));
            addpath(fullfile(app.Root,'core'),fullfile(app.Root,'app'),fullfile(app.Root,'..','..','core'));
            app.InputSettings=SMS_LAOS_app_input_defaults(struct('StrainUnit',app.GlobalStrainUnit));
            app.buildUI(); app.refreshTable(); app.renderEmpty(); app.refreshEnable();
            app.Tabs.SelectionChangedFcn=@(~,~)app.tabChanged();
            if ~app.Embedded, app.Figure.Visible=p.Results.Visible; end
        end

        function replaceFiles(app,paths,hostPaths)
            % The host supplies a canonical, validated list in display order.
            app.requireIdle();
            if nargin<3, hostPaths=false; end
            if ischar(paths) || isstring(paths), paths=cellstr(paths); end
            if ~iscell(paths), error('SMSApp:Files','File paths must be a list of text paths.'); end
            old=app.Entries;
            if ~hostPaths
                for k=1:numel(paths)
                    value=paths{k};
                    if ~((ischar(value)&&isrow(value)) || (isstring(value)&&isscalar(value))) || strlength(string(value))==0
                        error('SMSApp:Files','Every path must be nonempty scalar text.');
                    end
                    file=char(value);
                    [ok,attr]=fileattrib(file); if ok, file=attr.Name; end
                    paths{k}=file;
                end
                paths=unique(paths,'stable');
            end
            paths=reshape(paths,1,[]);
            selectedPaths={};
            if app.SelectedIndex>0, selectedPaths={old(app.SelectedIndex).Path}; end
            blank=struct('Path','','Name','','Status','pending','Result',[], ...
                'Error','','Options',struct(),'SourceSignature',struct(),'StaleReason','','InputSettings',struct());
            next=repmat(blank,1,numel(paths));
            [retained,previous]=ismember(paths,{old.Path});
            if any(retained), next(retained)=old(previous(retained)); end
            for k=find(~retained)
                [~,name,ext]=fileparts(paths{k});
                next(k).Path=paths{k}; next(k).Name=[name ext];
            end
            app.Entries=next;
            [retained,indices]=ismember(selectedPaths,paths);
            indices=indices(retained);
            if isempty(next)
                app.SelectedIndex=0;
            elseif isempty(indices)
                app.SelectedIndex=1;
            else
                app.SelectedIndex=indices(1);
            end
            app.ViewRevision=app.ViewRevision+1;
            app.SummaryRevision=app.SummaryRevision+1;
            if isempty(next), app.releasePlotData(); end
            if ~hostPaths, app.refresh(); end
        end

        function refresh(app,indices,renderView)
            if nargin<2, indices=1:numel(app.Entries); end
            if nargin<3, renderView=true; end
            app.syncStates(indices);
            app.refreshTable();
            if renderView, app.renderSelected(); end
            if ~app.Embedded, app.refreshEnable(); end
        end

        function setLocked(app,value)
            if ~(isscalar(value)&&(islogical(value)||isnumeric(value))&&isreal(value)&&isfinite(value)&&any(value==[0 1]))
                error('SMSApp:Locked','Locked must be true or false.');
            end
            if app.HostLocked==logical(value), return; end
            app.HostLocked=logical(value); app.refreshEnable();
        end

        function setInputSettings(app,settings)
            app.requireIdle();
            if app.HostLocked,error('SMSApp:Busy','Shared analysis is running.');end
            settings=SMS_LAOS_app_input_defaults(settings);
            app.InputSettings=settings;app.GlobalStrainUnit=settings.StrainUnit;
            app.Controls.strain_is_percent.Value=strcmp(settings.StrainUnit,'percent');
            app.settingsChanged();
        end

        function settings=currentInputSettings(app)
            settings=app.InputSettings;
        end

        function setStrainUnit(app,unit)
            settings=app.InputSettings;settings.StrainUnit=char(unit);app.setInputSettings(settings);
        end

        function addFiles(app,paths)
            app.requireIdle();
            if ischar(paths) || isstring(paths), paths=cellstr(paths); end
            if ~iscell(paths), error('SMSApp:Files','Paths must be text or a cell array of file paths.'); end
            next=app.Entries; added=0;
            for k=1:numel(paths)
                path=char(paths{k});
                if ~isfile(path), error('SMSApp:Files','File not found: %s',path); end
                [ok,attr]=fileattrib(path); if ok, path=attr.Name; end
                [~,name,ext]=fileparts(path);
                if ~strcmpi(ext,'.dat'), error('SMSApp:Files','The original SMS workflow accepts .dat files only.'); end
                if any(strcmp({next.Path},path)), continue; end
                next(end+1)=struct('Path',path,'Name',[name ext],'Status','pending', ...
                    'Result',[],'Error','','Options',struct(),'SourceSignature',struct(),'StaleReason','','InputSettings',struct()); %#ok<AGROW>
                added=added+1;
            end
            app.Entries=next;
            if added>0, app.SummaryRevision=app.SummaryRevision+1; end
            if app.SelectedIndex==0 && ~isempty(next)
                app.SelectedIndex=1; app.ViewRevision=app.ViewRevision+1;
            end
            app.syncStates(); app.refreshTable(); app.renderSelected(); app.refreshEnable();
            app.setStatus(sprintf('Added %d files | %d files in the list',added,numel(next)));
        end

        function addFolder(app,folder)
            app.requireIdle();
            if ~isfolder(folder), error('SMSApp:Files','Folder not found: %s',folder); end
            files=dir(folder); keep=false(size(files));
            for k=1:numel(files)
                [~,~,ext]=fileparts(files(k).name);
                keep(k)=~files(k).isdir && strcmpi(ext,'.dat');
            end
            files=files(keep); [~,ix]=sort({files.name}); files=files(ix);
            if isempty(files), error('SMSApp:Files','The folder contains no .dat files.'); end
            app.addFiles(arrayfun(@(f)fullfile(f.folder,f.name),files,'UniformOutput',false));
        end

        function removeSelected(app)
            app.requireIdle();
            if app.SelectedIndex==0, return; end
            app.Entries(app.SelectedIndex)=[];
            app.SelectedIndex=min(app.SelectedIndex,numel(app.Entries));
            app.ViewRevision=app.ViewRevision+1; app.SummaryRevision=app.SummaryRevision+1;
            if isempty(app.Entries), app.releasePlotData(); end
            app.refreshTable(); app.renderSelected(); app.refreshEnable();
            app.setStatus('Selected file removed from the list');
        end

        function clearFiles(app)
            app.requireIdle();
            app.Entries=app.Entries([]); app.SelectedIndex=0;
            app.ViewRevision=app.ViewRevision+1; app.SummaryRevision=app.SummaryRevision+1;
            app.releasePlotData();
            app.refreshTable(); app.renderEmpty(); app.refreshEnable();
            app.Controls.CurrentFile.Text='No file selected';
            app.banner('Add data, check strain units, then analyze.',[.9 .93 .96],app.Ink);
            app.setStatus('File list cleared');
        end

        function applySettings(app,s)
            app.requireIdle();
            if app.HostLocked, error('SMSApp:Busy','Shared analysis is running.'); end
            if ~isstruct(s) || ~isscalar(s), error('SMSApp:Settings','Settings must be a scalar struct.'); end
            names=fieldnames(s); allowed=[fieldnames(SMS_LAOS_app_FT_SD_defaults());{'FrequencyUnit'}];
            before=cellfun(@(c)c.Value,app.ParameterControls,'UniformOutput',false);beforeFrequencyUnit=app.FrequencyUnit;
            try
                for k=1:numel(names)
                    name=names{k};
                    if ~ismember(name,allowed), error('SMSApp:Settings','Unknown setting: %s',name); end
                    v=s.(name);
                    if strcmp(name,'FrequencyUnit'),app.changeFrequencyUnit(v);continue;end
                    if any(strcmp(name,{'freq_min','freq_max'}))&&strcmp(app.FrequencyUnit,'rad/s'),v=v*2*pi;end
                    if app.Embedded && strcmp(name,'strain_is_percent'), v=strcmp(app.GlobalStrainUnit,'percent'); end
                    if strcmp(name,'cycle_selection_mode'), v=char(v); end
                    app.Controls.(name).Value=v;
                end
                app.currentOptions();
            catch ME
                for k=1:numel(app.ParameterControls), app.ParameterControls{k}.Value=before{k}; end
                app.FrequencyUnit=beforeFrequencyUnit;
                rethrow(ME);
            end
            app.settingsChanged();
        end

        function opts=currentOptions(app)
            opts=SMS_LAOS_app_FT_SD_defaults(); names=fieldnames(opts);
            for k=1:numel(names), opts.(names{k})=app.Controls.(names{k}).Value; end
            if app.Embedded, opts.strain_is_percent=strcmp(app.GlobalStrainUnit,'percent'); end
            if strcmp(app.FrequencyUnit,'rad/s'),opts.freq_min=opts.freq_min/(2*pi);opts.freq_max=opts.freq_max/(2*pi);end
            opts=SMS_LAOS_app_FT_SD_validate_options(opts);
        end

        function analyze(app,scope)
            app.requireIdle();
            if isempty(app.Entries), error('SMSApp:Files','Add data files before starting analysis.'); end
            if nargin<2, scope='selected'; end
            opts=app.currentOptions();
            if strcmp(scope,'all'), indices=1:numel(app.Entries);
            elseif strcmp(scope,'selected') && app.SelectedIndex>0, indices=app.SelectedIndex;
            else, error('SMSApp:Scope','Analysis scope must be selected or all.'); end
            app.Busy=true; app.CancelRequested=false; app.refreshEnable();
            finish=onCleanup(@()app.finishRun()); %#ok<NASGU>
            completed=0; failed=0;
            for k=1:numel(indices)
                drawnow;
                if app.CancelRequested, break; end
                i=indices(k);
                app.setStatus(sprintf('Analyzing %d / %d | %s',k,numel(indices),app.Entries(i).Name));
                app.Controls.Progress.Value=sprintf('%d / %d',k,numel(indices)); drawnow;
                if app.calculateFile(i,opts), completed=completed+1; else, failed=failed+1; end
                app.SelectedIndex=i; app.ViewRevision=app.ViewRevision+1;
                app.SummaryRevision=app.SummaryRevision+1;
                app.refreshTable();
                % Numerical work remains per-file; draw the active tab once
                % after analysis, or if the user explicitly opens a tab.
                drawnow limitrate;
            end
            app.syncStates(); app.refreshTable(); app.renderSelected();
            prefix='Analysis complete'; if app.CancelRequested, prefix='Stopped'; end
            app.setStatus(sprintf('%s | %d completed, %d failed | Select a row to inspect results',prefix,completed,failed));
        end

        function ok=analyzeFile(app,i,opts)
            % The host owns progress, cancellation, selection and final rendering.
            if ~app.HostLocked || app.Busy
                error('SMSApp:Busy','Single-file batch analysis requires the locked merged workspace.');
            end
            ok=app.calculateFile(i,opts);
            app.SummaryRevision=app.SummaryRevision+1;
            if i==app.SelectedIndex, app.ViewRevision=app.ViewRevision+1; end
        end

        function requestCancel(app)
            if app.Busy && ~app.IsExporting
                app.CancelRequested=true;
                app.setStatus('Stopping after the current file finishes');
            end
        end

        function selectFile(app,index,renderView)
            if nargin<3, renderView=true; end
            app.requireIdle();
            if ~isscalar(index) || index~=fix(index) || index<1 || index>numel(app.Entries)
                error('SMSApp:Selection','Invalid file index.');
            end
            if app.SelectedIndex~=index
                app.SelectedIndex=index; app.ViewRevision=app.ViewRevision+1;
            end
            if renderView, app.refresh(index); end
        end

        function selectTab(app,titleText)
            %SELECTTAB Open a result page and synchronously populate it.
            % Unlike setting SelectedTab directly, this public action also
            % works when MATLAB does not fire SelectionChangedFcn.
            app.requireIdle();
            tabs=app.Tabs.Children;
            index=find(strcmp({tabs.Title},char(titleText)),1);
            if isempty(index), error('SMSApp:Tab','Unknown result tab: %s',char(titleText)); end
            app.Tabs.SelectedTab=tabs(index);
            app.tabChanged();
        end

        function manifest=exportResults(app,folder)
            app.requireIdle(); app.syncStates(); app.refreshTable(); app.refreshEnable(); app.renderSelected();
            opts=app.currentOptions();
            exportOptions=struct('fast_mode',opts.fast_mode,'save_curve_csv',opts.save_curve_csv);
            app.Busy=true; app.IsExporting=true; app.refreshEnable();
            finish=onCleanup(@()app.finishExport()); %#ok<NASGU>
            app.setStatus('Exporting current results | Please wait; this operation cannot be cancelled');
            drawnow;
            manifest=SMS_LAOS_app_export_SD(app.Entries,folder,exportOptions,@(event)app.exportProgress(event));
            app.LastExport=char(folder); app.setStatus(['Export complete: ' char(folder)]);
        end

        function saveView(app,path)
            app.requireIdle();
            if isfile(path), error('SMSApp:ViewExists','The output file already exists. Choose a new filename.'); end
            app.syncStates(); app.refreshTable(); app.renderSelected(); app.refreshEnable(); drawnow;
            exportapp(app.Figure,path);
            app.setStatus(['View saved: ' char(path)]);
        end

        function delete(app)
            if app.Embedded
                if ~isempty(app.Body) && isvalid(app.Body), delete(app.Body); end
                if ~isempty(app.HiddenControls) && isvalid(app.HiddenControls), delete(app.HiddenControls); end
            elseif ~isempty(app.Figure) && isvalid(app.Figure)
                delete(app.Figure);
            end
        end
    end

    methods (Access=private)
        function ok=calculateFile(app,i,opts)
            try
                source=app.sourceSignature(app.Entries(i).Path);
                R=SMS_LAOS_app_analyze_FT_SD(app.Entries(i).Path,opts,app.InputSettings);
                if ~isequal(source,app.sourceSignature(app.Entries(i).Path))
                    error('SMSApp:SourceChanged','The source file changed during analysis. Reanalyze it.');
                end
                app.Entries(i).Result=R; app.Entries(i).Options=opts;app.Entries(i).InputSettings=app.InputSettings;
                app.Entries(i).SourceSignature=source;
                app.Entries(i).StaleReason=''; app.Entries(i).Error='';
                if R.quality.has_warnings, app.Entries(i).Status='warning'; else, app.Entries(i).Status='ok'; end
                ok=true;
            catch ME
                app.Entries(i).Result=[]; app.Entries(i).Options=opts;app.Entries(i).InputSettings=app.InputSettings;
                app.Entries(i).Error=[ME.identifier ': ' ME.message];
                app.Entries(i).Status='error'; app.Entries(i).StaleReason='';
                app.Entries(i).SourceSignature=struct(); ok=false;
            end
        end

        function buildUI(app)
            if app.Embedded, app.buildEmbeddedUI(); return; end
            app.Figure=uifigure('Name','SMS LAOS | Local analysis workspace','Visible','off', ...
                'Position',[40 40 1440 940],'Color',app.Background,'CloseRequestFcn',@(~,~)app.onClose());
            outer=uigridlayout(app.Figure,[3 1]); outer.RowHeight={64,'1x',30};
            outer.Padding=[18 12 18 10]; outer.RowSpacing=12; outer.BackgroundColor=app.Background;
            head=uigridlayout(outer,[1 4]); head.ColumnWidth={'1x',130,110,100}; head.Padding=[4 0 0 0]; head.BackgroundColor=app.Background;
            titlebox=uigridlayout(head,[2 1]); titlebox.RowHeight={32,22}; titlebox.Padding=[0 0 0 0]; titlebox.RowSpacing=0; titlebox.BackgroundColor=app.Background;
            uilabel(titlebox,'Text','SMS LAOS','FontName',app.Font,'FontSize',27,'FontWeight','bold','FontColor',app.Ink);
            uilabel(titlebox,'Text','Fourier & stress decomposition  /  Original v2 calculation','FontName',app.Font,'FontSize',12,'FontColor',[.4 .46 .55]);
            app.Controls.Export=uibutton(head,'Text','Export results','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.safe(@()app.chooseExport()));
            view=uibutton(head,'Text','Save view','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.safe(@()app.chooseView()));
            app.ActionControls{end+1}=view;
            uibutton(head,'Text','User guide','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.showHelp());
            body=uigridlayout(outer,[1 2]); body.ColumnWidth={360,'1x'}; body.Padding=[0 0 0 0]; body.ColumnSpacing=14; body.BackgroundColor=app.Background;
            app.buildSidebar(body); app.buildMain(body);
            foot=uigridlayout(outer,[1 3]); foot.ColumnWidth={'1x',80,86}; foot.Padding=[4 0 0 0]; foot.BackgroundColor=app.Background;
            app.Controls.Status=uilabel(foot,'Text','Ready | Add files to start','FontName',app.Font,'FontSize',11,'FontColor',[.38 .43 .5]);
            app.Controls.Progress=uieditfield(foot,'text','Editable','off','Value','','HorizontalAlignment','center','FontName',app.Font);
            app.Controls.Cancel=uibutton(foot,'Text','Stop','FontName',app.Font,'Enable','off','ButtonPushedFcn',@(~,~)app.requestCancel());
        end

        function buildSidebar(app,parent)
            panel=uipanel(parent,'BackgroundColor',[1 1 1],'BorderType','none');
            g=uigridlayout(panel,[8 1]); g.RowHeight={22,34,30,52,22,'1x',38,32}; g.Padding=[14 14 14 14]; g.RowSpacing=9;
            uilabel(g,'Text','01  Select data','FontName',app.Font,'FontWeight','bold','FontColor',app.Ink);
            buttons=uigridlayout(g,[1 2]); buttons.Padding=[0 0 0 0]; buttons.ColumnSpacing=8;
            add=uibutton(buttons,'Text','Add files','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.safe(@()app.chooseFiles()));
            folder=uibutton(buttons,'Text','Add folder','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.safe(@()app.chooseFolder()));
            demo=uibutton(g,'Text','Load synthetic demo','FontName',app.Font,'FontColor',app.Blue, ...
                'BackgroundColor',[.94 .97 1],'Tooltip','Loads synthetic data and restores the original script defaults.', ...
                'ButtonPushedFcn',@(~,~)app.safe(@()app.loadDemo()));
            uilabel(g,'Text',{'.dat columns: time (s), strain, stress (Pa).','Set strain units below before analysis.','Input files are read only.'},'FontName',app.Font,'FontSize',11,'FontColor',[.38 .43 .5]);
            uilabel(g,'Text','02  Analysis settings','FontName',app.Font,'FontWeight','bold','FontColor',app.Ink);
            app.buildSettingsTabs(g);
            run=uigridlayout(g,[1 2]); run.Padding=[0 0 0 0]; run.ColumnSpacing=8;
            app.Controls.AnalyzeSelected=uibutton(run,'Text','Analyze selected','FontName',app.Font,'FontColor',[1 1 1],'BackgroundColor',app.Blue,'ButtonPushedFcn',@(~,~)app.safe(@()app.analyze('selected')));
            app.Controls.AnalyzeAll=uibutton(run,'Text','Analyze all','FontName',app.Font,'BackgroundColor',[.91 .94 .98],'ButtonPushedFcn',@(~,~)app.safe(@()app.analyze('all')));
            remove=uigridlayout(g,[1 2]); remove.Padding=[0 0 0 0]; remove.ColumnSpacing=8;
            app.Controls.Remove=uibutton(remove,'Text','Remove selected','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.safe(@()app.removeSelected()));
            app.Controls.Clear=uibutton(remove,'Text','Clear list','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.safe(@()app.clearFiles()));
            app.ActionControls=[app.ActionControls {add,folder,demo,app.Controls.Remove,app.Controls.Clear}];
        end

        function buildEmbeddedUI(app)
            % Hidden compatibility controls have no layout allocation in the
            % host. All visible actions and file selection belong to it.
            app.HiddenControls=uipanel(app.Figure,'Visible','off','Position',[1 1 1 1]);
            h=app.HiddenControls;
            for name={'Export','AnalyzeSelected','AnalyzeAll','Remove','Clear','Cancel'}
                app.Controls.(name{1})=uibutton(h,'Visible','off');
            end
            app.Controls.Status=uilabel(h,'Visible','off','Text','Ready');
            app.Controls.Progress=uieditfield(h,'text','Visible','off','Value','');
            app.FileTable=uitable(h,'Visible','off','ColumnName',{'File','Status','f (Hz)','I3/I1'}, ...
                'SelectionType','row','Multiselect','off');
            if strcmp(app.Role,'ft')
                app.Body=uigridlayout(app.Parent,[1 1]);app.Body.ColumnWidth={'1x'};
            else
                app.Body=uigridlayout(app.Parent,[1 2]);app.Body.ColumnWidth={310,'1x'};
            end
            app.Body.Padding=[6 6 6 6];app.Body.ColumnSpacing=10;app.Body.BackgroundColor=app.Background;
            panel=uipanel(app.Body,'BackgroundColor',[1 1 1],'BorderType','none');
            g=uigridlayout(panel,[2 1]);g.RowHeight={24,'1x'};g.Padding=[8 8 8 8];
            title='Stress decomposition settings';if strcmp(app.Role,'ft'),title='FT-LAOS settings';end
            uilabel(g,'Text',title,'FontName',app.Font,'FontWeight','bold','FontColor',app.Ink);
            app.buildSettingsTabs(g);
            if strcmp(app.Role,'ft'),app.buildMain(app.HiddenControls);else,app.buildMain(app.Body);end
        end

        function buildSettingsTabs(app,parent)
            if app.Embedded
                basic=uipanel(parent,'BorderType','none');exports=app.HiddenControls;
            else
                tabs=uitabgroup(parent);basic=uitab(tabs,'Title','Analysis');exports=uitab(tabs,'Title','Export');
            end
            b=uigridlayout(basic,[15 2]);b.ColumnWidth={155,'1x'};b.RowHeight=repmat({28},1,15);b.Padding=[6 8 6 8];b.RowSpacing=7;b.Scrollable='on';
            d=SMS_LAOS_app_FT_SD_defaults();
            app.drop(b,1,'Cycle selection','cycle_selection_mode',{'Trim ends','Last N cycles'},{'trim_ends','last_n_cycles'},d.cycle_selection_mode);
            app.number(b,2,'Trim first cycles','remove_first_cycles',d.remove_first_cycles,[0 Inf]);
            app.number(b,3,'Trim last cycles','remove_last_cycles',d.remove_last_cycles,[0 Inf]);
            app.number(b,4,'Last N cycles','last_n_cycles',d.last_n_cycles,[1 Inf]);
            if app.Embedded
                app.Controls.strain_is_percent=uicheckbox(app.HiddenControls,'Visible','off','Value',d.strain_is_percent);
                app.ParameterControls{end+1}=app.Controls.strain_is_percent;
            else
                app.check(b,5,'Input strain is percent (%)','strain_is_percent',d.strain_is_percent);
            end
            app.check(b,5,'Restrict frequency search','use_freq_range',d.use_freq_range);
            app.drop(b,6,'Frequency input unit','FrequencyUnit',{'Hz','rad/s'},{'Hz','rad/s'},'Hz');
            app.Controls.FrequencyUnit.ValueChangedFcn=@(~,~)app.safe(@()app.frequencyUnitChanged());
            app.number(b,7,'Minimum frequency','freq_min',d.freq_min,[eps Inf]);
            app.number(b,8,'Maximum frequency','freq_max',d.freq_max,[eps Inf]);
            app.check(b,9,'Alternating odd-harmonic sign','use_alternating_odd_sign',d.use_alternating_odd_sign);
            hint=uilabel(b,'Text',{'Input units and columns: Data & units tab.','Results use seconds, decimal strain and Pa.','Cycle selection does not establish steady state.','The original method retains harmonics 1 and 3.'}, ...
                'WordWrap','on','FontName',app.Font,'FontSize',11,'FontColor',[.45 .48 .55]);hint.Layout.Row=[10 12];hint.Layout.Column=[1 2];
            reset=uibutton(b,'Text','Restore method defaults','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.safe(@()app.resetAnalysisSettings()));
            reset.Layout.Row=14;reset.Layout.Column=[1 2];app.ActionControls{end+1}=reset;
            eg=uigridlayout(exports,[11 2]);eg.ColumnWidth={160,'1x'};eg.RowHeight=repmat({28},1,11);eg.Padding=[8 10 8 10];eg.RowSpacing=7;eg.Scrollable='on';
            app.check(eg,1,'Fast export mode','fast_mode',d.fast_mode);
            app.check(eg,2,'Export decomposed curve CSV','save_curve_csv',d.save_curve_csv);
            if ~app.Embedded
                hint=uilabel(eg,'Text',{'FULL MODE: original CSV, Excel and PNG/FIG.','FAST MODE: summary and optional curve CSV.','Both modes include exact MAT snapshots.'}, ...
                    'WordWrap','on','FontName',app.Font,'FontSize',11);hint.Layout.Row=[3 6];hint.Layout.Column=[1 2];
            end
        end

        function buildMain(app,parent)
            if app.Embedded
                g=uigridlayout(parent,[4 1]); g.RowHeight={68,38,22,'1x'};
            else
                g=uigridlayout(parent,[5 1]); g.RowHeight={135,68,38,22,'1x'};
            end
            g.Padding=[0 0 0 0]; g.RowSpacing=9; g.BackgroundColor=app.Background;
            if ~app.Embedded
            app.FileTable=uitable(g,'ColumnName',{'File','Status','f (Hz)','I3/I1'},'ColumnEditable',false, ...
                'ColumnWidth',{'auto',145,80,80},'RowName',{},'FontName',app.Font,'FontSize',12, ...
                'SelectionType','row','Multiselect','off','CellSelectionCallback',@(~,e)app.tableSelected(e));
            end
            cards=uigridlayout(g,[1 4]); cards.Padding=[0 0 0 0]; cards.ColumnSpacing=10; cards.BackgroundColor=app.Background;
            names={'Amplitude','Frequency','Cycles','Residual'}; labels={'Strain amplitude / decimal','Detected frequency / Hz','Selected cycles','Residual RMS / I1'};
            for k=1:4
                panel=uipanel(cards,'BorderType','none','BackgroundColor',[1 1 1]); cg=uigridlayout(panel,[2 1]); cg.RowHeight={20,30}; cg.Padding=[10 5 8 5]; cg.RowSpacing=0;
                uilabel(cg,'Text',labels{k},'FontName',app.Font,'FontSize',11,'FontColor',[.45 .5 .57]);
                app.Cards.(names{k})=uilabel(cg,'Text','—','FontName',app.Font,'FontSize',22,'FontWeight','bold','FontColor',app.Ink);
            end
            app.Controls.Banner=uilabel(g,'Text','Add data, check strain units, then analyze.','WordWrap','on','FontName',app.Font,'FontSize',12,'BackgroundColor',[.9 .93 .96],'FontColor',app.Ink);
            app.Controls.CurrentFile=uilabel(g,'Text','No file selected','FontName',app.Font,'FontSize',11,'FontColor',[.38 .43 .5]);
            app.Tabs=uitabgroup(g);
            app.plotTab('Signals',{'RawStrain','RawStress','SelectedStrain','SelectedStress'},[2 2]);
            app.plotTab('Lissajous',{'Total','Elastic','Viscous','Reconstructed'},[2 2]);
            app.plotTab('Reconstruction',{'StressReconstruction','Residual'},[2 1]);
            results=uitab(app.Tabs,'Title','Results & quality'); qg=uigridlayout(results,[2 1]); qg.RowHeight={'1x',150};
            app.Controls.ResultsTable=uitable(qg,'ColumnName',{'Quantity','Value','Unit / definition'},'ColumnWidth',{195,160,'auto'},'RowName',{},'FontName',app.Font,'FontSize',12);
            app.Controls.QualityTable=app.Controls.ResultsTable;
            app.Controls.QualityMessages=uitextarea(qg,'Editable','off','FontName',app.Font,'FontSize',12,'Value',{'Analyze a file to see results and diagnostics.'});
            app.plotTab('Batch summary',{'SummaryFrequency','SummaryHarmonic','SummaryElastic','SummaryViscous','SummaryS','SummaryT'},[3 2]);
        end

        function plotTab(app,titleText,names,shape)
            tab=uitab(app.Tabs,'Title',titleText); g=uigridlayout(tab,shape);
            g.Padding=[10 10 10 8]; g.RowSpacing=12; g.ColumnSpacing=14;
            for k=1:numel(names)
                ax=uiaxes(g,'FontName',app.Font,'FontSize',10,'Box','on','Color',[1 1 1],'NextPlot','add');
                ax.XGrid='on'; ax.YGrid='on'; ax.GridAlpha=.1; ax.Toolbar.Visible='on';
                app.Axes.(names{k})=ax;
            end
        end

        function number(app,g,row,label,name,value,limits)
            app.fieldLabel(g,row,label);
            c=uieditfield(g,'numeric','Value',value,'Limits',limits,'FontName',app.Font,'ValueChangedFcn',@(~,~)app.settingsChanged());
            c.Layout.Row=row; c.Layout.Column=2; app.Controls.(name)=c; app.ParameterControls{end+1}=c;
        end
        function drop(app,g,row,label,name,items,data,value)
            app.fieldLabel(g,row,label);
            c=uidropdown(g,'Items',items,'ItemsData',data,'Value',value,'FontName',app.Font,'ValueChangedFcn',@(~,~)app.settingsChanged());
            c.Layout.Row=row; c.Layout.Column=2; app.Controls.(name)=c; app.ParameterControls{end+1}=c;
        end
        function check(app,g,row,label,name,value)
            c=uicheckbox(g,'Text',label,'Value',value,'FontName',app.Font,'FontSize',11,'ValueChangedFcn',@(~,~)app.settingsChanged());
            c.Layout.Row=row; c.Layout.Column=[1 2]; app.Controls.(name)=c; app.ParameterControls{end+1}=c;
        end
        function fieldLabel(app,g,row,label)
            c=uilabel(g,'Text',label,'FontName',app.Font,'FontSize',11); c.Layout.Row=row; c.Layout.Column=1;
        end

        function resetAnalysisSettings(app)
            defaults=rmfield(SMS_LAOS_app_FT_SD_defaults(),{'fast_mode','save_curve_csv','strain_is_percent'});
            app.applySettings(defaults);
        end
        function frequencyUnitChanged(app)
            unit=app.Controls.FrequencyUnit.Value;app.Controls.FrequencyUnit.Value=app.FrequencyUnit;
            app.applySettings(struct('FrequencyUnit',unit));
        end
        function changeFrequencyUnit(app,unit)
            unit=validatestring(char(unit),{'Hz','rad/s'});
            if strcmp(unit,app.FrequencyUnit),app.Controls.FrequencyUnit.Value=unit;return;end
            factor=2*pi;if strcmp(unit,'Hz'),factor=1/factor;end
            app.Controls.freq_min.Value=app.Controls.freq_min.Value*factor;
            app.Controls.freq_max.Value=app.Controls.freq_max.Value*factor;
            app.FrequencyUnit=unit;app.Controls.FrequencyUnit.Value=unit;
        end

        function settingsChanged(app)
            if app.Busy, return; end
            app.syncStates(); app.refreshTable(); app.renderSelected(); app.refreshEnable();
            app.setStatus('Settings updated | Reanalysis is required only when analysis settings change');
            if ~isempty(app.StateChangedFcn), app.StateChangedFcn(app); end
        end
        function s=analysisOptions(~,s)
            for n={'fast_mode','save_curve_csv'}, if isfield(s,n{1}), s=rmfield(s,n{1}); end; end
        end
        function syncStates(app,indices)
            if nargin<2, indices=1:numel(app.Entries); end
            if isempty(indices) || all(cellfun(@isempty,{app.Entries(indices).Result})), return; end
            try, opts=app.analysisOptions(app.currentOptions()); catch, opts=[]; end
            changed=false;
            for k=reshape(indices,1,[])
                e=app.Entries(k); if isempty(e.Result), continue; end
                if ~isequal(e.SourceSignature,app.sourceSignature(e.Path))
                    app.Entries(k).Status='stale'; app.Entries(k).StaleReason='Source file changed or is missing';
                elseif ~isequaln(app.InputSettings,e.InputSettings)
                    app.Entries(k).Status='stale';app.Entries(k).StaleReason='Input units or import settings changed';
                elseif isempty(opts) || ~isequaln(opts,app.analysisOptions(e.Options))
                    app.Entries(k).Status='stale'; app.Entries(k).StaleReason='Analysis settings changed';
                else
                    app.Entries(k).StaleReason='';
                    if e.Result.quality.has_warnings, app.Entries(k).Status='warning'; else, app.Entries(k).Status='ok'; end
                end
                changed=changed || ~strcmp(e.Status,app.Entries(k).Status) || ...
                    ~strcmp(e.StaleReason,app.Entries(k).StaleReason);
            end
            if changed, app.SummaryRevision=app.SummaryRevision+1; end
        end
        function signature=sourceSignature(~,path)
            d=dir(path);
            if isempty(d) || d(1).isdir
                signature=struct('Exists',false,'Bytes',NaN,'ModifiedDatenum',NaN,'Method','file-size-and-mtime');
            else
                signature=struct('Exists',true,'Bytes',d(1).bytes,'ModifiedDatenum',d(1).datenum,'Method','file-size-and-mtime');
            end
        end
        function refreshTable(app)
            if app.Embedded, return; end  % The host owns the visible file list.
            n=numel(app.Entries); rows=cell(n,4);
            for k=1:n
                e=app.Entries(k); rows(k,:)={e.Name,app.statusText(e.Status),'—','—'};
                if ~isempty(e.Result)
                    rows{k,3}=sprintf('%.6g',e.Result.freq_hz); rows{k,4}=sprintf('%.5g',e.Result.I3_I1);
                end
            end
            warn=find(ismember({app.Entries.Status},{'warning','stale'})); fail=find(strcmp({app.Entries.Status},'error'));
            if ~isequal(rows,app.TableRows) || ~isequal(warn,app.TableWarningRows) || ~isequal(fail,app.TableFailedRows)
                app.FileTable.Data=rows; removeStyle(app.FileTable);
                if ~isempty(warn), addStyle(app.FileTable,uistyle('FontColor',app.Orange),'row',warn); end
                if ~isempty(fail), addStyle(app.FileTable,uistyle('FontColor',[.7 .16 .16]),'row',fail); end
                app.TableRows=rows; app.TableWarningRows=warn; app.TableFailedRows=fail;
            end
            if app.SelectedIndex>0 && app.SelectedIndex<=n && ~isequal(app.FileTable.Selection,app.SelectedIndex)
                app.FileTable.Selection=app.SelectedIndex;
            end
        end
        function label=statusText(~,state)
            switch state
                case 'pending', label='Pending';
                case 'ok', label='Complete';
                case 'warning', label='Review warnings';
                case 'error', label='Failed';
                case 'stale', label='Reanalysis required';
                otherwise, label=state;
            end
        end
        function refreshEnable(app)
            locked=app.Busy || app.HostLocked;
            state='on'; if locked, state='off'; end
            for k=1:numel(app.ParameterControls), app.ParameterControls{k}.Enable=state; end
            for k=1:numel(app.ActionControls), app.ActionControls{k}.Enable=state; end
            app.FileTable.Enable=state;
            hasFiles=~isempty(app.Entries) && ~locked;
            app.Controls.AnalyzeSelected.Enable=hasFiles; app.Controls.AnalyzeAll.Enable=hasFiles;
            app.Controls.Remove.Enable=hasFiles; app.Controls.Clear.Enable=hasFiles;
            app.Controls.Export.Enable=any(ismember({app.Entries.Status},{'ok','warning'})) && ~locked;
            app.Controls.Cancel.Enable=app.Busy && ~app.IsExporting;
            if ~locked
                trimming=strcmp(app.Controls.cycle_selection_mode.Value,'trim_ends');
                app.Controls.remove_first_cycles.Enable=trimming; app.Controls.remove_last_cycles.Enable=trimming;
                app.Controls.last_n_cycles.Enable=~trimming;
                app.Controls.freq_min.Enable=app.Controls.use_freq_range.Value; app.Controls.freq_max.Enable=app.Controls.use_freq_range.Value;
            end
            if app.Embedded
                app.Controls.strain_is_percent.Value=strcmp(app.GlobalStrainUnit,'percent');
                app.Controls.strain_is_percent.Enable='off';
                app.Controls.strain_is_percent.Tooltip='Controlled by the shared input strain unit.';
            end
        end
        function finishRun(app)
            if ~isvalid(app), return; end
            app.Busy=false; app.refreshEnable();
            if app.CloseAfterRun, delete(app); end
        end
        function finishExport(app)
            if ~isvalid(app), return; end
            app.IsExporting=false; app.finishRun();
        end
        function requireIdle(app)
            if app.Busy, error('SMSApp:Busy','An operation is running. Wait for it to finish; analysis can be stopped after the current file.'); end
        end
        function setStatus(app,message)
            app.Controls.Status.Text=message; app.Controls.Status.Tooltip=message;
        end
        function exportProgress(app,event)
            if ~isvalid(app) || isempty(app.Figure) || ~isvalid(app.Figure), return; end
            message=sprintf('Exporting %d / %d | %s',event.FileIndex,event.FileCount,char(event.Stage));
            if ~isempty(event.Filename), message=[message ' | ' char(event.Filename)]; end
            if app.CloseAfterRun, message=[message ' | Window will close when export finishes']; end
            app.setStatus(message);
            app.Controls.Progress.Value=sprintf('%d / %d',event.FileIndex,event.FileCount);
            drawnow limitrate;
        end
        function tabChanged(app)
            if isempty(app.Tabs.SelectedTab) || (app.Embedded && app.HostLocked), return; end
            if ~app.Busy
                if strcmp(app.Tabs.SelectedTab.Title,'Batch summary')
                    app.syncStates();
                elseif app.SelectedIndex>0
                    app.syncStates(app.SelectedIndex);
                end
                app.refreshTable(); app.refreshEnable();
            end
            app.renderSelected();
        end
        function safe(app,callback)
            try, callback(); catch ME
                if ~isvalid(app) || isempty(app.Figure) || ~isvalid(app.Figure), return; end
                app.setStatus(['Operation could not be completed: ' ME.message]);
                uialert(app.Figure,ME.message,'Operation could not be completed','Icon','error','Interpreter','none');
            end
        end

        function releasePlotData(app)
            % Clear list must release large cached arrays on hidden pages,
            % while retaining graphics handles for the next imported file.
            names=fieldnames(app.PlotObjects);
            for k=1:numel(names)
                h=app.PlotObjects.(names{k});
                if ~isgraphics(h), continue; end
                if isgraphics(h,'line')
                    set(h,'XData',[],'YData',[],'Visible','off');
                else
                    h.Visible='off';
                end
            end
            app.RenderedTabs=struct();
        end
        function renderEmpty(app)
            for n=fieldnames(app.Cards)', app.Cards.(n{1}).Text='—'; end
            app.Controls.ResultsTable.Data={};
            app.Controls.QualityMessages.Value={'Original v2 values and diagnostic notices will appear after analysis.'};
            app.ResultsKey=[]; app.HeaderKey=[];
            app.renderActiveTab([]);
        end
        function renderSelected(app)
            if app.Embedded && (strcmp(app.Role,'ft') || ...
                    (isa(app.Parent,'matlab.ui.container.Tab') && app.Parent.Parent.SelectedTab~=app.Parent))
                return
            end
            if app.SelectedIndex==0 || isempty(app.Entries)
                key=struct('Revision',app.ViewRevision,'Status','empty','Reason','');
                if ~isequaln(key,app.HeaderKey)
                    app.renderEmpty(); app.Controls.CurrentFile.Text='No file selected';
                    app.Controls.CurrentFile.Tooltip='';
                    app.banner('Add data, check strain units, then analyze.',[.9 .93 .96],app.Ink);
                    app.HeaderKey=key;
                end
                app.renderActiveTab([]); return
            end
            e=app.Entries(app.SelectedIndex);
            key=struct('Revision',app.ViewRevision,'Status',e.Status,'Reason',e.StaleReason);
            if ~isequaln(key,app.HeaderKey)
                app.Controls.CurrentFile.Text=e.Name; app.Controls.CurrentFile.Tooltip=e.Path;
                if isempty(e.Result)
                    for n=fieldnames(app.Cards)', app.Cards.(n{1}).Text='—'; end
                    app.Controls.ResultsTable.Data={};
                    if strcmp(e.Status,'error')
                        app.banner(['Analysis failed | ' e.Error],[1 .91 .91],[.6 .1 .1]);
                        app.Controls.QualityMessages.Value={e.Error};
                    else
                        app.banner('Pending | Check whether the strain column uses percent or decimal values.',[.9 .93 .96],app.Ink);
                        app.Controls.QualityMessages.Value={'Original v2 values and diagnostic notices will appear after analysis.'};
                    end
                    app.ResultsKey=[];
                else
                    R=e.Result;
                    app.Cards.Amplitude.Text=sprintf('%.5g',R.gamma0);
                    app.Cards.Frequency.Text=sprintf('%.6g',R.freq_hz);
                    app.Cards.Cycles.Text=num2str(R.n_cycles_used);
                    app.Cards.Residual.Text=sprintf('%.4g',R.residual_rms_over_I1);
                    if strcmp(e.Status,'stale')
                        app.banner([e.StaleReason ' | Previous results are shown and excluded from export.'],[1 .94 .82],app.Orange);
                    elseif R.quality.has_warnings
                        app.banner(sprintf('%d diagnostic notices | Review Results & quality before interpreting the curves.',numel(R.quality.messages)),[1 .94 .82],app.Orange);
                    else
                        app.banner('Complete | Original v2 calculation. Review the model limits in Results & quality.',[.88 .95 .94],[.12 .36 .33]);
                    end
                end
                app.HeaderKey=key;
            end
            if ~isempty(e.Result) && ~isequaln(key,app.ResultsKey)
                app.renderResults(e); app.ResultsKey=key;
            end
            app.renderActiveTab(e.Result);
        end

        function renderActiveTab(app,R)
            % Only the opened page receives graphics work. Cached pages keep
            % their full-resolution objects until a different result is shown.
            if isempty(app.Tabs.SelectedTab), return; end
            page=app.Tabs.SelectedTab.Title;
            key=regexprep(lower(page),'[^a-z]','');
            if strcmp(page,'Results & quality'), return; end
            revision=app.ViewRevision;
            if strcmp(page,'Batch summary'), revision=app.SummaryRevision; end
            if isfield(app.RenderedTabs,key) && app.RenderedTabs.(key)==revision, return; end
            if strcmp(page,'Batch summary')
                app.renderSummary();
            elseif isempty(R)
                app.emptyTab(page);
            else
                switch page
                    case 'Signals'
                        for n={'Strain','Stress'}
                            name=n{1}; raw=R.([lower(name) '_raw']); axisName=['Raw' name];
                            app.updateLine([axisName 'All'],axisName,R.time_raw,raw,'Color',[.65 .7 .76],'LineWidth',.8);
                            app.updateLine([axisName 'Selected'],axisName,R.time_raw(R.selected_mask),raw(R.selected_mask),'Color',app.Blue,'LineWidth',1.1);
                            app.updateBoundary([axisName 'Start'],axisName,R.t_start_use);
                            app.updateBoundary([axisName 'End'],axisName,R.t_end_use);
                            unit='Strain (decimal)'; if strcmp(name,'Stress'), unit='Stress (Pa)'; end
                            app.prepareAxes(axisName,['Raw ' lower(name) ' and selected interval'],'Time (s)',unit);
                            axisName=['Selected' name];
                            app.updateLine(axisName,axisName,R.time,R.(lower(name)),'Color',app.Blue,'LineWidth',1.1);
                            app.prepareAxes(axisName,['Selected ' lower(name)],'Time from selected start (s)',unit);
                        end
                    case 'Lissajous'
                        app.updateLine('Total','Total',R.strain,R.stress,'Color',app.Blue,'LineWidth',1.1);
                        app.prepareAxes('Total','Total stress–strain','Strain (decimal)','Stress (Pa)');
                        app.updateLine('Elastic','Elastic',R.strain,R.stress_elastic,'Color',app.Blue,'LineWidth',1.1);
                        app.prepareAxes('Elastic','Elastic Lissajous','Strain (decimal)','Elastic stress (Pa)');
                        app.updateLine('Viscous','Viscous',R.gammadot_over_omega,R.stress_viscous,'Color',[.85 .39 .15],'LineWidth',1.1);
                        app.prepareAxes('Viscous','Viscous Lissajous','Strain rate / omega','Viscous stress (Pa)');
                        first=app.updateLine('ReconstructedMeasured','Reconstructed',R.strain,R.stress,'Color',app.Blue,'LineWidth',1);
                        second=app.updateLine('ReconstructedFit','Reconstructed',R.strain,R.stress_reconstructed,'LineStyle','--','Color',[.85 .39 .15],'LineWidth',1.2);
                        app.prepareAxes('Reconstructed','Measured and reconstructed Lissajous','Strain (decimal)','Stress (Pa)');
                        app.ensureLegend('Reconstructed',first,second);
                    case 'Reconstruction'
                        first=app.updateLine('StressReconstructionMeasured','StressReconstruction',R.time,R.stress,'Color',app.Blue,'LineWidth',1);
                        second=app.updateLine('StressReconstructionFit','StressReconstruction',R.time,R.stress_reconstructed,'LineStyle','--','Color',[.85 .39 .15],'LineWidth',1.2);
                        app.prepareAxes('StressReconstruction','Measured and reconstructed stress','Time from selected start (s)','Stress (Pa)');
                        app.ensureLegend('StressReconstruction',first,second);
                        app.updateLine('Residual','Residual',R.time,R.stress_residual,'Color',app.Orange,'LineWidth',1);
                        app.prepareAxes('Residual','Reconstruction residual','Time from selected start (s)','Measured − reconstructed (Pa)');
                end
            end
            app.RenderedTabs.(key)=revision;
        end

        function h=updateLine(app,key,axisName,x,y,varargin)
            if isfield(app.PlotObjects,key) && isgraphics(app.PlotObjects.(key),'line')
                h=app.PlotObjects.(key); set(h,'XData',x,'YData',y,'Visible','on');
            else
                h=line(app.Axes.(axisName),x,y,varargin{:});
                app.PlotObjects.(key)=h;
            end
        end
        function updateBoundary(app,key,axisName,value)
            if isfield(app.PlotObjects,key) && isgraphics(app.PlotObjects.(key))
                set(app.PlotObjects.(key),'Value',value,'Visible','on');
            else
                app.PlotObjects.(key)=xline(app.Axes.(axisName),value,'--','Color',app.Orange);
            end
        end
        function prepareAxes(app,name,titleText,x,y)
            ax=app.Axes.(name);
            set(ax,'XLimMode','auto','YLimMode','auto');
            app.labelAxes(ax,titleText,x,y);
            key=[name 'Empty'];
            if isfield(app.PlotObjects,key) && isgraphics(app.PlotObjects.(key))
                app.PlotObjects.(key).Visible='off';
            end
        end
        function ensureLegend(app,name,first,second)
            key=[name 'Legend'];
            if ~isfield(app.PlotObjects,key) || ~isgraphics(app.PlotObjects.(key))
                app.PlotObjects.(key)=legend(app.Axes.(name),[first second],{'Measured','Elastic + viscous'},'Location','best','FontSize',9);
            else
                app.PlotObjects.(key).Visible='on';
            end
        end
        function emptyTab(app,page)
            switch page
                case 'Signals', names={'RawStrain','RawStress','SelectedStrain','SelectedStress'};
                case 'Lissajous', names={'Total','Elastic','Viscous','Reconstructed'};
                case 'Reconstruction', names={'StressReconstruction','Residual'};
                otherwise, return
            end
            for k=1:numel(names)
                ax=app.Axes.(names{k});
                children=ax.Children;
                for j=1:numel(children), children(j).Visible='off'; end
                legendKey=[names{k} 'Legend'];
                if isfield(app.PlotObjects,legendKey) && isgraphics(app.PlotObjects.(legendKey))
                    app.PlotObjects.(legendKey).Visible='off';
                end
                title(ax,'Analyze selected to view results'); xlabel(ax,''); ylabel(ax,'');
            end
        end

        function renderResults(app,e)
            R=e.Result;
            fields={'freq_hz','omega','n_cycles_used','I1','I3','I3_I1','delta1','delta3', ...
                'Gp1','Gpp1','Gp3','Gpp3','e1','v1','e3','v3','e3_e1','v3_v1', ...
                'G_M_prime','G_L_prime','S','eta_M_prime','eta_L_prime','T','gamma0','residual_rms','residual_rms_over_I1'};
            labels={'Detected frequency','Angular frequency','Cycles used','I1','I3','I3 / I1','delta1','delta3', ...
                'G′1','G″1','G′3','G″3','e1','v1','e3','v3','e3 / e1','v3 / v1', ...
                'G′M','G′L','S','η′M','η′L','T','Strain amplitude','Residual RMS','Residual RMS / I1'};
            units={'Hz','rad/s','Selected by estimated period','Pa','Pa','Dimensionless','rad','rad', ...
                'Pa','Pa','Pa','Pa','Pa','Pa·s','Pa','Pa·s','Dimensionless','Dimensionless', ...
                'Pa','Pa','1st + 3rd terms','Pa·s','Pa·s','1st + 3rd terms','Decimal','Pa','Dimensionless'};
            rows=cell(numel(fields)+1,3); rows(1,:)={'Filename',e.Name,'Original source file'};
            for k=1:numel(fields), rows(k+1,:)={labels{k},sprintf('%.15g',R.(fields{k})),units{k}}; end
            if isfield(R.quality,'relative_sampling_step_deviation')
                rows(end+1,:)={'Sampling step deviation',sprintf('%.5g%%',100*R.quality.relative_sampling_step_deviation),'Maximum relative to median time step'};
                rows(end+1,:)={'Third harmonic < Nyquist',char(string(R.quality.third_harmonic_below_nyquist)),'Sampling check only'};
            end
            app.Controls.ResultsTable.Data=rows;
            messages={'Values retain the original v2 algorithm, including the selected harmonic sign convention.'; ...
                'S, T and stress reconstruction use harmonics 1 and 3 only. Cycle selection does not test steady state.'; ...
                'Poor reconstruction can also reflect frequency error, sampling, phase or derivative noise.'};
            if strcmp(e.Status,'stale'), messages{end+1}=[e.StaleReason '. These previous results are excluded from export.']; end
            for k=1:numel(R.quality.messages), messages{end+1}=['• ' char(R.quality.messages{k})]; end
            if isfield(R.quality,'notes')
                for k=1:numel(R.quality.notes), messages{end+1}=['Note: ' char(R.quality.notes{k})]; end
            end
            messages{end+1}=['Actual analysis settings: ' jsonencode(app.analysisOptions(e.Options))];
            app.Controls.QualityMessages.Value=messages;
        end

        function renderSummary(app)
            names={'SummaryFrequency','SummaryHarmonic','SummaryElastic','SummaryViscous','SummaryS','SummaryT'};
            fields={'freq_hz','I3_I1','e3_e1','v3_v1','S','T'};
            titles={'Detected frequency','Harmonic ratio','Elastic nonlinearity','Viscous nonlinearity','Strain-stiffening ratio','Shear-thickening ratio'};
            units={'f (Hz)','I3 / I1','e3 / e1','v3 / v1','S','T'};
            indices=find(ismember({app.Entries.Status},{'ok','warning'}));
            for k=1:numel(names)
                name=names{k}; ax=app.Axes.(name);
                app.prepareAxes(name,titles{k},'File row in the list',units{k});
                if ~isempty(indices)
                    values=arrayfun(@(i) app.Entries(i).Result.(fields{k}),indices);
                    app.updateLine(name,name,indices,values,'Marker','o','Color',app.Blue,'LineWidth',1.2,'MarkerSize',4);
                    ax.XTick=indices; ax.XTickLabel=arrayfun(@num2str,indices,'UniformOutput',false);
                else
                    if isfield(app.PlotObjects,name) && isgraphics(app.PlotObjects.(name))
                        set(app.PlotObjects.(name),'XData',[],'YData',[],'Visible','off');
                    end
                    set(ax,'XTickMode','auto','XTickLabelMode','auto');
                    key=[name 'Empty'];
                    if isfield(app.PlotObjects,key) && isgraphics(app.PlotObjects.(key))
                        app.PlotObjects.(key).Visible='on';
                    else
                        app.PlotObjects.(key)=text(ax,.5,.5,'No current results','Units','normalized','HorizontalAlignment','center','FontSize',11);
                    end
                end
            end
        end

        function labelAxes(app,ax,titleText,x,y)
            title(ax,titleText,'FontName',app.Font,'FontWeight','normal','Interpreter','none');
            xlabel(ax,x,'FontName',app.Font,'Interpreter','none'); ylabel(ax,y,'FontName',app.Font,'Interpreter','none');
        end
        function banner(app,message,bg,fg)
            app.Controls.Banner.Text=['  ' message]; app.Controls.Banner.Tooltip=message;
            app.Controls.Banner.BackgroundColor=bg; app.Controls.Banner.FontColor=fg;
        end
        function tableSelected(app,event)
            if app.Busy || isempty(event.Indices), return; end
            app.selectFile(event.Indices(1,1));
        end
        function chooseFiles(app)
            [files,folder]=uigetfile({'*.dat','SMS-LAOS data (*.dat)'},'Select data files','MultiSelect','on');
            if isequal(files,0), return; end
            if ischar(files), files={files}; end
            app.addFiles(cellfun(@(f)fullfile(folder,f),files,'UniformOutput',false));
        end
        function chooseFolder(app)
            folder=uigetdir(pwd,'Select a folder containing .dat files'); if isequal(folder,0), return; end
            app.addFolder(folder);
        end
        function loadDemo(app)
            path=fullfile(app.Root,'examples','SMS-LAOS app synthetic demo.dat');
            if ~isfile(path), error('SMSApp:Demo','The synthetic example was not found. Keep the package folder intact.'); end
            app.applySettings(SMS_LAOS_app_FT_SD_defaults()); app.addFiles(path);
            [ok,attr]=fileattrib(path); if ok, path=attr.Name; end
            app.selectFile(find(strcmp({app.Entries.Path},path),1));
            app.setStatus('Synthetic demo loaded with original defaults | Click Analyze selected');
        end
        function chooseExport(app)
            folder=uigetdir(app.Root,'Choose a location; a new results folder will be created'); if isequal(folder,0), return; end
            target=fullfile(folder,['SMS_results_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
            app.exportResults(target);
        end
        function chooseView(app)
            [name,folder]=uiputfile({'*.png','PNG image';'*.pdf','PDF document'},'Save current view','SMS_view.png');
            if isequal(name,0), return; end
            app.saveView(fullfile(folder,name));
        end
        function showHelp(app)
            message=sprintf(['1. Add .dat files. The first three columns are time in seconds, strain and stress in Pa. Check Input strain is percent if 50 represents 50%% strain.\n\n' ...
                '2. Choose trim ends or last N cycles. All analysis defaults match SMS_LAOS_v2.m. Optional frequency limits and the original odd-harmonic sign setting are retained.\n\n' ...
                '3. Analyze selected or all files. Select a row to view Signals, Lissajous, Reconstruction, Results & quality, and Batch summary. Check the source file column order and units before importing.\n\n' ...
                '4. Analysis settings or source-file changes mark previous results as Reanalysis required. File freshness uses size and modification time, not content hashes.\n\n' ...
                '5. Full export preserves the original CSV, Excel, PNG and FIG outputs. Fast mode omits plots, selected-cycle CSV and Excel; curve CSV remains separately selectable. Both modes add MAT results, settings and a manifest.\n\n' ...
                '6. The v2 calculation uses harmonics 1 and 3. Check the quality messages before interpreting the results. Stop takes effect after the current file.']);
            uialert(app.Figure,message,'SMS-LAOS — FT and stress decomposition guide','Icon','info','Interpreter','none');
        end
        function onClose(app)
            if app.Busy
                app.CloseAfterRun=true;
                if app.IsExporting, app.setStatus('Export is finishing | This window will close when it completes');
                else, app.requestCancel(); end
            else, delete(app); end
        end
    end
end
