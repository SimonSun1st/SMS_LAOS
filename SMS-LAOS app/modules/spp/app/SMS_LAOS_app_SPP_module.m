classdef SMS_LAOS_app_SPP_module < handle
    %SMS_LAOS_APP_SPP_MODULE Embedded average/evolution module with frozen SPP v5 core.
    % Public actions are shared by UI callbacks and integration tests.
    properties
        StateChangedFcn=[]
    end
    properties (SetAccess=private)
        Figure
        Controls=struct()
        FileTable
        Tabs
        Axes=struct()
        Entries=struct('Path',{},'Name',{},'Status',{},'Result',{},'Error',{},'Options',{},'SourceSignature',{},'StaleReason',{},'InputSettings',{})
        SelectedIndex=0
        SelectedIndices=[]
        Busy=false
        LastExport=''
        InputSettings=struct()
    end
    properties (Access=private)
        Root
        Parent=[]
        HostFigure=[]
        OwnFigure=true
        Surface=[]
        HiddenControls=[]
        HostLocked=false
        GlobalStrainUnit=''
        FrequencyUnit='rad/s'
        LastAnalysisMode=''
        Font='Arial'
        CancelRequested=false
        CloseAfterRun=false
        ParameterControls={}
        ActionControls={}
        Cards=struct()
        Background=[.95 .96 .98]
        Ink=[.12 .18 .27]
        Blue=[.12 .35 .69]
        Orange=[.66 .35 .05]
    end
    methods
        function app=SMS_LAOS_app_SPP_module(varargin)
            p=inputParser; p.addParameter('Visible','on',@(x) any(strcmpi(x,{'on','off'})));
            p.addParameter('Parent',[]); p.addParameter('HostFigure',[]); p.parse(varargin{:});
            app.Parent=p.Results.Parent; app.HostFigure=p.Results.HostFigure;
            app.OwnFigure=isempty(app.Parent);
            if ~app.OwnFigure
                if isempty(app.HostFigure), app.HostFigure=ancestor(app.Parent,'figure'); end
                if isempty(app.HostFigure) || ~isgraphics(app.HostFigure,'figure')
                    error('SPPApp:Parent','Embedded SPP requires a valid Parent and HostFigure.');
                end
                app.GlobalStrainUnit='percent';
            end
            app.Root=fileparts(fileparts(mfilename('fullpath')));
            addpath(app.Root,fullfile(app.Root,'legacy'),fullfile(app.Root,'..','..','core'));
            app.InputSettings=SMS_LAOS_app_input_defaults();
            fonts=listfonts;
            for f={'Arial','Helvetica'}
                if any(strcmpi(fonts,f{1})), app.Font=f{1}; break; end
            end
            app.buildUI();
            app.refreshTable(); app.renderEmpty(); app.refreshEnable();
            if app.OwnFigure, app.Figure.Visible=p.Results.Visible; end
        end

        function addFiles(app,paths)
            app.requireIdle();
            if ischar(paths) || isstring(paths), paths=cellstr(paths); end
            if ~iscell(paths), error('SPPApp:Files','File paths must be text or a list of text paths.'); end
            added=0; next=app.Entries;
            for k=1:numel(paths)
                path=char(paths{k});
                if ~isfile(path), error('SPPApp:Files','File not found: %s',path); end
                [ok,attr]=fileattrib(path); if ok, path=attr.Name; end
                [~,name,ext]=fileparts(path);
                if ~any(strcmpi(ext,{'.dat','.csv','.txt','.tsv','.xls','.xlsx'}))
                    error('SPPApp:Files','Unsupported file type: %s',ext);
                end
                if any(strcmp({next.Path},path)), continue; end
                e=struct('Path',path,'Name',[name ext],'Status','pending','Result',[], ...
                    'Error','','Options',struct(),'SourceSignature',struct(),'StaleReason','','InputSettings',struct());
                next(end+1)=e; added=added+1;
            end
            app.Entries=next;
            if app.SelectedIndex==0 && ~isempty(app.Entries), app.SelectedIndex=1; app.SelectedIndices=1; end
            app.refreshTable(); app.refreshEnable();
            if app.SelectedIndex>0, app.renderSelected(); end
            app.setStatus(sprintf('Added %d files | %d files in the list',added,numel(app.Entries)));
        end

        function replaceFiles(app,paths,hostPaths)
            % The host supplies a canonical, validated list in display order.
            app.requireIdle();
            if nargin<3, hostPaths=false; end
            if ischar(paths) || isstring(paths), paths=cellstr(paths); end
            if ~iscell(paths), error('SPPApp:Files','File paths must be a list of text paths.'); end
            old=app.Entries;
            if ~hostPaths
                for k=1:numel(paths)
                    value=paths{k};
                    if ~((ischar(value)&&isrow(value)) || (isstring(value)&&isscalar(value))) || strlength(string(value))==0
                        error('SPPApp:Files','Every path must be nonempty scalar text.');
                    end
                    file=char(value);
                    if isfile(file)
                        [ok,attr]=fileattrib(file); if ok, file=attr.Name; end
                    elseif ~any(strcmp({old.Path},file))
                        error('SPPApp:Files','File not found: %s',file);
                    end
                    [~,~,ext]=fileparts(file);
                    if ~ismember(lower(ext),{'.dat','.csv','.txt','.tsv','.xls','.xlsx'})
                        error('SPPApp:Files','Unsupported file type: %s',ext);
                    end
                    paths{k}=file;
                end
                paths=unique(paths,'stable');
            end
            paths=reshape(paths,1,[]);
            selectedPaths={};
            if ~isempty(app.SelectedIndices), selectedPaths={old(app.SelectedIndices).Path}; end
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
            if isempty(indices) && ~isempty(next), indices=1; end
            app.SelectedIndices=reshape(indices,1,[]);
            if isempty(indices), app.SelectedIndex=0; else, app.SelectedIndex=indices(1); end
            if isempty(next), app.clearFiles(); end
            if ~hostPaths, app.refresh(); end
        end

        function refresh(app,indices,renderView)
            if nargin<2, indices=1:numel(app.Entries); end
            if nargin<3, renderView=true; end
            app.syncStates(indices);
            app.refreshTable();
            if renderView, app.renderSelected(); end
            if app.OwnFigure, app.refreshEnable(); end
        end

        function setLocked(app,value)
            if ~isscalar(value) || ~(islogical(value) || (isnumeric(value) && ismember(value,[0 1])))
                error('SPPApp:Lock','Lock state must be logical scalar.');
            end
            if app.HostLocked==logical(value), return; end
            app.HostLocked=logical(value);
            if app.HostLocked, app.LastAnalysisMode=''; end
            app.refreshEnable();
        end

        function setInputSettings(app,settings)
            app.requireIdle();
            if app.HostLocked,error('SPPApp:Busy','Shared analysis is running.');end
            settings=SMS_LAOS_app_input_defaults(settings);
            app.InputSettings=settings;app.GlobalStrainUnit=settings.StrainUnit;
            for name={'TimeColumn','StrainColumn','StressColumn','HeaderLines'}
                app.Controls.(name{1}).Value=settings.(name{1});
            end
            if isnumeric(settings.Sheet),app.Controls.Sheet.Value=num2str(settings.Sheet);else,app.Controls.Sheet.Value=char(settings.Sheet);end
            d=settings.Delimiter;
            if isempty(d),d='auto';elseif strcmp(d,sprintf('\t')),d='tab';elseif strcmp(d,' '),d='space';end
            if ~ismember(d,app.Controls.Delimiter.ItemsData)
                app.Controls.Delimiter.Items=[app.Controls.Delimiter.Items,{d}];
                app.Controls.Delimiter.ItemsData=[app.Controls.Delimiter.ItemsData,{d}];
            end
            app.Controls.Delimiter.Value=d;
            app.Controls.StrainUnit.Value=settings.StrainUnit;
            app.settingsChanged();
        end

        function settings=currentInputSettings(app)
            settings=app.InputSettings;
        end

        function setStrainUnit(app,value)
            settings=app.InputSettings;settings.StrainUnit=char(value);app.setInputSettings(settings);
        end

        function applySettings(app,s)
            app.requireIdle();
            if app.HostLocked, error('SPPApp:Busy','Shared analysis is running.'); end
            if ~isstruct(s) || ~isscalar(s), error('SPPApp:Settings','Settings must be a scalar structure.'); end
            names=fieldnames(s);before=cellfun(@(c)c.Value,app.ParameterControls,'UniformOutput',false);beforeFrequencyUnit=app.FrequencyUnit;
            shared={'StrainUnit','TimeColumn','StrainColumn','StressColumn','HeaderLines','Delimiter','Sheet'};
            if ~app.OwnFigure&&any(ismember(names,shared))
                error('SPPApp:SharedInput','Input units and import settings are controlled by Data & units. Use setInputSettings.');
            end
            try
                for k=1:numel(names)
                    n=names{k}; v=s.(n);
                    switch n
                        case 'TrimCycles'
                            if numel(v)~=2, error('SPPApp:Settings','TrimCycles requires two values.'); end
                            app.Controls.TrimStart.Value=v(1); app.Controls.TrimEnd.Value=v(2);
                        case {'FitWindowFraction','SmoothFraction','StationarityTolerance','HarmonicStationarityTolerance','HarmonicFloor'}
                            app.Controls.(n).Value=100*v;
                        case 'Omega'
                            if strcmp(app.FrequencyUnit,'Hz'),v=v/(2*pi);end
                            if isempty(v),app.Controls.Omega.Value='';else,app.Controls.Omega.Value=num2str(v,17);end
                        case 'FrequencyUnit',app.changeFrequencyUnit(v);
                        case 'CycleNumbers', app.Controls.CycleNumbers.Value=strtrim(sprintf('%g ',v));
                        case 'Sheet'
                            if isnumeric(v), v=num2str(v); end
                            app.Controls.Sheet.Value=char(v);
                        case {'StrainUnit','SelectionMode','StrainRateMode','DerivativeMode','DetectCyclesFrom','AnalysisMode','AveragingPolicy'}
                            app.Controls.(n).Value=char(v);
                        case 'Delimiter'
                            if strcmp(v,sprintf('\t')), v='tab'; elseif isempty(v), v='auto'; elseif strcmp(v,' '), v='space'; end
                            app.Controls.Delimiter.Value=char(v);
                        case {'TimeColumn','StrainColumn','StressColumn','HeaderLines','PointsPerCycle','AssessWindowSensitivity','AssessSmoothingSensitivity','MinStableCycles','HarmonicMaxOrder'}
                            app.Controls.(n).Value=v;
                        otherwise, error('SPPApp:Settings','This interface does not support the setting: %s',n);
                    end
                end
                app.currentOptions();
            catch ME
                for k=1:numel(app.ParameterControls),app.ParameterControls{k}.Value=before{k};end
                app.FrequencyUnit=beforeFrequencyUnit;
                rethrow(ME);
            end
            app.settingsChanged();
        end

        function options=currentOptions(app)
            c=app.Controls;
            nums=[c.TimeColumn.Value c.StrainColumn.Value c.StressColumn.Value c.HeaderLines.Value ...
                c.TrimStart.Value c.TrimEnd.Value c.PointsPerCycle.Value c.MinStableCycles.Value c.HarmonicMaxOrder.Value];
            if any(~isfinite(nums)) || any(nums~=fix(nums))
                error('SPPApp:Settings','Columns, header rows, cycle counts, harmonic order and sampling points must be integers.');
            end
            omegaText=strtrim(c.Omega.Value);
            if isempty(omegaText), w=[];
            else
                w=str2double(omegaText);
                if ~isfinite(w)||w<=0,error('SPPApp:Settings','Frequency must be positive, or blank for automatic estimation.');end
                if strcmp(app.FrequencyUnit,'Hz'),w=w*2*pi;end
            end
            txt=strtrim(c.CycleNumbers.Value); cycles=[];
            if ~isempty(txt)
                txt=regexprep(txt,'[,;，；]',' ');
                parts=regexp(txt,'\s+','split');
                for k=1:numel(parts)
                    bounds=str2double(strsplit(parts{k},':'));
                    if numel(bounds)>2 || any(~isfinite(bounds)) || any(bounds<1) || any(bounds~=fix(bounds))
                        error('SPPApp:Settings','Enter positive cycle IDs or a range such as 4:20, separated by spaces or commas.');
                    end
                    if numel(bounds)==2
                        if bounds(2)<bounds(1) || bounds(2)-bounds(1)>100000
                            error('SPPApp:Settings','A cycle range must increase and contain at most 100001 IDs.');
                        end
                        cycles=[cycles bounds(1):bounds(2)]; %#ok<AGROW>
                    else, cycles(end+1)=bounds; end %#ok<AGROW>
                end
                cycles=unique(cycles,'stable');
            end
            manual=strcmp(c.AnalysisMode.Value,'average') && strcmp(c.AveragingPolicy.Value,'manual');
            if manual && strcmp(c.SelectionMode.Value,'single_manual') && numel(cycles)~=1
                error('SPPApp:Settings','Manual single-cycle analysis requires exactly one cycle ID.');
            end
            if manual && ~strcmp(c.SelectionMode.Value,'average') && numel(cycles)>1
                error('SPPApp:Settings','A single-cycle selection accepts only one cycle ID.');
            end
            sheet=c.Sheet.Value; number=str2double(sheet);
            if isfinite(number) && number>=1 && number==fix(number), sheet=number; end
            delimiter=c.Delimiter.Value;
            if strcmp(delimiter,'tab'), delimiter=sprintf('\t'); elseif strcmp(delimiter,'auto'), delimiter=''; elseif strcmp(delimiter,'space'), delimiter=' '; end
            strainUnit=c.StrainUnit.Value;
            if ~isempty(app.GlobalStrainUnit), strainUnit=app.GlobalStrainUnit; end
            options=struct('AnalysisMode',c.AnalysisMode.Value,'AveragingPolicy',c.AveragingPolicy.Value, ...
                'MinStableCycles',c.MinStableCycles.Value,'StationarityTolerance',c.StationarityTolerance.Value/100, ...
                'HarmonicStationarityTolerance',c.HarmonicStationarityTolerance.Value/100, ...
                'HarmonicMaxOrder',c.HarmonicMaxOrder.Value,'HarmonicFloor',c.HarmonicFloor.Value/100, ...
                'TimeColumn',c.TimeColumn.Value,'StrainColumn',c.StrainColumn.Value,'StressColumn',c.StressColumn.Value, ...
                'HeaderLines',c.HeaderLines.Value,'Delimiter',delimiter,'Sheet',sheet,'StrainUnit',strainUnit, ...
                'Omega',w,'DetectCyclesFrom',c.DetectCyclesFrom.Value,'TrimCycles',[c.TrimStart.Value c.TrimEnd.Value], ...
                'SelectionMode',c.SelectionMode.Value,'CycleNumbers',cycles,'PointsPerCycle',c.PointsPerCycle.Value, ...
                'FitWindowFraction',c.FitWindowFraction.Value/100,'SmoothFraction',c.SmoothFraction.Value/100, ...
                'StrainRateMode',c.StrainRateMode.Value,'DerivativeMode',c.DerivativeMode.Value, ...
                'AssessWindowSensitivity',c.AssessWindowSensitivity.Value,'AssessSmoothingSensitivity',c.AssessSmoothingSensitivity.Value, ...
                'MakePlots',false,'Verbose',false,'StoreRaw',false);
        end

        function analyze(app,scope)
            app.requireIdle();
            if isempty(app.Entries), error('SPPApp:Files','Add data files before starting analysis.'); end
            if nargin<2, scope='selected'; end
            options=app.currentOptions();
            if strcmp(options.AnalysisMode,'cycle_evolution'), app.Tabs.SelectedTab=app.Controls.EvolutionTab;
            else, app.Tabs.SelectedTab=app.Controls.AverageTab; end
            if strcmp(scope,'all'), indices=1:numel(app.Entries);
            elseif strcmp(scope,'selected') && ~isempty(app.SelectedIndices), indices=app.SelectedIndices;
            else, error('SPPApp:Scope','Analysis scope must be selected or all.'); end
            app.Busy=true; app.CancelRequested=false; app.refreshEnable();
            finish=onCleanup(@() app.finishRun()); %#ok<NASGU>
            completed=0; failed=0;
            for k=1:numel(indices)
                drawnow;
                if app.CancelRequested, break; end
                i=indices(k);
                app.setStatus(sprintf('Analyzing %d / %d | %s',k,numel(indices),app.Entries(i).Name));
                app.Controls.Progress.Value=sprintf('%d / %d',k,numel(indices));
                drawnow;
                if app.calculateFile(i,options), completed=completed+1; else, failed=failed+1; end
                app.SelectedIndex=i; app.refreshTable(); app.renderSelected();
                drawnow;
            end
            if ~isempty(app.SelectedIndices), app.SelectedIndex=app.SelectedIndices(1); app.renderSelected(); end
            if app.CancelRequested, prefix='Stopped'; else, prefix='Analysis complete'; end
            app.setStatus(sprintf('%s | Completed: %d | Failed: %d | Select a file to view its results',prefix,completed,failed));
        end

        function ok=analyzeFile(app,i,options)
            % The host owns progress, cancellation, selection and final rendering.
            if ~app.HostLocked || app.Busy
                error('SPPApp:Busy','Single-file batch analysis requires the locked merged workspace.');
            end
            if ~strcmp(app.LastAnalysisMode,options.AnalysisMode)
                if strcmp(options.AnalysisMode,'cycle_evolution')
                    app.Tabs.SelectedTab=app.Controls.EvolutionTab;
                else
                    app.Tabs.SelectedTab=app.Controls.AverageTab;
                end
                app.LastAnalysisMode=options.AnalysisMode;
            end
            ok=app.calculateFile(i,options);
        end

        function requestCancel(app)
            if app.Busy
                app.CancelRequested=true;
                app.setStatus('Stopping after the current file finishes');
            end
        end

        function selectFile(app,index,varargin)
            app.selectFiles(index,varargin{:});
        end

        function selectFiles(app,indices,renderView)
            if nargin<3, renderView=true; end
            if isempty(indices) || any(~isfinite(indices)) || any(indices~=fix(indices)) || any(indices<1) || any(indices>numel(app.Entries))
                error('SPPApp:Selection','Choose one or more valid file indices.');
            end
            app.SelectedIndices=unique(indices(:)','stable'); app.SelectedIndex=app.SelectedIndices(1);
            if renderView, app.refresh(app.SelectedIndices); end
        end

        function manifest=exportResults(app,folder)
            app.requireIdle();
            app.syncStates(); app.refreshTable(); app.refreshEnable(); app.renderSelected();
            manifest=SMS_LAOS_app_export_SPP_v5(app.Entries,folder);
            app.LastExport=folder;
            app.setStatus(['Exported current results to: ' char(folder)]);
        end

        function saveView(app,path)
            app.requireIdle();
            if isfile(path), error('SPPApp:ViewExists','The file already exists. Choose a new image filename.'); end
            app.syncStates(); app.refreshTable(); app.refreshEnable(); app.renderSelected();
            exportapp(app.Figure,path);
            app.setStatus(['Saved the current view to: ' char(path)]);
        end

        function delete(app)
            if app.OwnFigure
                if ~isempty(app.Figure) && isvalid(app.Figure), delete(app.Figure); end
            else
                if ~isempty(app.Surface) && isvalid(app.Surface), delete(app.Surface); end
                if ~isempty(app.HiddenControls) && isvalid(app.HiddenControls), delete(app.HiddenControls); end
            end
        end
    end

    methods (Access=private)
        function ok=calculateFile(app,i,options)
            try
                source=app.sourceSignature(app.Entries(i).Path);
                R=SMS_LAOS_app_analyze_SPP(app.Entries(i).Path,options,app.InputSettings);
                if ~isequal(source,app.sourceSignature(app.Entries(i).Path))
                    error('SPPApp:SourceChanged','The source file changed during analysis. Run the analysis again.');
                end
                app.Entries(i).Result=R; app.Entries(i).Options=options;app.Entries(i).InputSettings=app.InputSettings; app.Entries(i).Error='';
                app.Entries(i).SourceSignature=source; app.Entries(i).StaleReason='';
                if R.quality.has_warnings, app.Entries(i).Status='warning'; else, app.Entries(i).Status='ok'; end
                ok=true;
            catch ME
                % A failed new run must not leave a previous successful result exportable.
                app.Entries(i).Result=[]; app.Entries(i).Options=options;app.Entries(i).InputSettings=app.InputSettings;
                app.Entries(i).Error=[ME.identifier ': ' ME.message]; app.Entries(i).Status='error';
                app.Entries(i).SourceSignature=struct(); app.Entries(i).StaleReason='';
                ok=false;
            end
        end

        function buildUI(app)
            if ~app.OwnFigure
                app.Figure=app.HostFigure;
                app.HiddenControls=uipanel(app.Figure,'Visible','off','Position',[0 0 1 1]);
                app.Controls.Status=uilabel(app.HiddenControls,'Text','Ready');
                app.Controls.Progress=uieditfield(app.HiddenControls,'text','Editable','off','Value','');
                app.Controls.Cancel=uibutton(app.HiddenControls,'Text','Stop','ButtonPushedFcn',@(~,~)app.requestCancel());
                app.Controls.Export=uibutton(app.HiddenControls,'Text','Export results');
                app.Surface=uigridlayout(app.Parent,[1 2]); app.Surface.ColumnWidth={365,'1x'};
                app.Surface.Padding=[8 8 8 8]; app.Surface.ColumnSpacing=10; app.Surface.BackgroundColor=app.Background;
                app.buildSidebar(app.Surface); app.buildMain(app.Surface); return
            end
            app.Figure=uifigure('Name','SPP LAOS | Local analysis workspace','Visible','off', ...
                'Position',[35 35 1540 940],'Color',app.Background, ...
                'CloseRequestFcn',@(~,~)app.onClose());
            outer=uigridlayout(app.Figure,[3 1]); outer.RowHeight={64,'1x',30};
            outer.Padding=[18 12 18 10]; outer.RowSpacing=12; outer.BackgroundColor=app.Background;
            head=uigridlayout(outer,[1 4]); head.ColumnWidth={'1x',130,130,100}; head.Padding=[4 0 0 0]; head.BackgroundColor=app.Background;
            titlebox=uigridlayout(head,[2 1]); titlebox.RowHeight={32,22}; titlebox.Padding=[0 0 0 0]; titlebox.RowSpacing=0; titlebox.BackgroundColor=app.Background;
            uilabel(titlebox,'Text','SPP LAOS','FontName',app.Font,'FontSize',27,'FontWeight','bold','FontColor',app.Ink);
            uilabel(titlebox,'Text','Average response and cycle evolution  /  v5','FontName',app.Font,'FontSize',12,'FontColor',[.4 .46 .55]);
            app.Controls.Export=uibutton(head,'Text','Export results','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.safe(@()app.chooseExport()),'BackgroundColor',[1 1 1]);
            view=uibutton(head,'Text','Save view','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.safe(@()app.chooseView()),'BackgroundColor',[1 1 1]);
            app.ActionControls{end+1}=view;
            uibutton(head,'Text','User guide','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.showHelp(),'BackgroundColor',[1 1 1]);
            body=uigridlayout(outer,[1 2]); body.ColumnWidth={370,'1x'}; body.Padding=[0 0 0 0]; body.ColumnSpacing=14; body.BackgroundColor=app.Background;
            app.buildSidebar(body);
            app.buildMain(body);
            foot=uigridlayout(outer,[1 3]); foot.ColumnWidth={'1x',80,86}; foot.Padding=[4 0 0 0]; foot.BackgroundColor=app.Background;
            app.Controls.Status=uilabel(foot,'Text','Ready | Add files to start analysis','FontName',app.Font,'FontColor',[.38 .43 .5],'FontSize',11);
            app.Controls.Progress=uieditfield(foot,'text','Editable','off','Value','','HorizontalAlignment','center','FontName',app.Font);
            app.Controls.Cancel=uibutton(foot,'Text','Stop','FontName',app.Font,'Enable','off','ButtonPushedFcn',@(~,~)app.requestCancel());
        end

        function buildSidebar(app,parent)
            panel=uipanel(parent,'BackgroundColor',[1 1 1],'BorderType','none');
            if app.OwnFigure
                g=uigridlayout(panel,[7 1]); g.RowHeight={22,34,30,22,'1x',38,30};
                actionParent=g;
            else
                g=uigridlayout(panel,[1 1]); g.RowHeight={'1x'};
                actionParent=app.HiddenControls;
            end
            g.Padding=[10 10 10 10]; g.RowSpacing=9;
            uilabel(actionParent,'Text','01  Select data','FontName',app.Font,'FontWeight','bold','FontColor',app.Ink);
            buttons=uigridlayout(actionParent,[1 2]); buttons.Padding=[0 0 0 0]; buttons.ColumnSpacing=8;
            add=uibutton(buttons,'Text','Add files','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.safe(@()app.chooseFiles()));
            folder=uibutton(buttons,'Text','Add folder','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.safe(@()app.chooseFolder()));
            example=uibutton(actionParent,'Text','Load synthetic demo','FontName',app.Font,'FontColor',app.Blue,'BackgroundColor',[.94 .97 1], ...
                'ButtonPushedFcn',@(~,~)app.safe(@()app.loadPackageDemo()));
            uilabel(actionParent,'Text','02  Analysis settings','FontName',app.Font,'FontWeight','bold','FontColor',app.Ink);
            if app.OwnFigure
                tabs=uitabgroup(g);basic=uitab(tabs,'Title','Analysis');imports=uitab(tabs,'Title','Import');
            else
                basic=uipanel(g,'BorderType','none');imports=app.HiddenControls;
            end
            b=uigridlayout(basic,[25 2]); b.ColumnWidth={165,'1x'}; b.RowHeight=repmat({29},1,25); b.Padding=[8 10 8 10]; b.RowSpacing=7; b.Scrollable='on';
            app.drop(b,1,'Analysis mode','AnalysisMode',{'Average response','Cycle evolution'},{'average','cycle_evolution'},'average');
            app.drop(b,2,'Averaging policy','AveragingPolicy',{'Stable final cycles','Manual selection'},{'stable_tail','manual'},'stable_tail');
            app.drop(b,3,'Manual selection','SelectionMode',{'Cycle average','Middle cycle','One cycle ID'},{'average','single_middle','single_manual'},'average');
            app.edit(b,4,'Cycle IDs / range','CycleNumbers','','4:20 or 4 7 9');
            app.number(b,5,'Trim first cycles','TrimStart',0,[0 Inf]);
            app.number(b,6,'Trim last cycles','TrimEnd',0,[0 Inf]);
            app.number(b,7,'Minimum stable cycles','MinStableCycles',5,[2 Inf]);
            app.number(b,8,'Bulk stability tolerance (%)','StationarityTolerance',5,[.01 99.99]);
            app.number(b,9,'Harmonic tolerance (%)','HarmonicStationarityTolerance',25,[.01 99.99]);
            app.Controls.HarmonicStationarityTolerance.Tooltip='Maximum complex-coefficient range and whole-window trend relative to that harmonic amplitude. Empirical screen; not a coefficient of variation or confidence interval.';
            app.number(b,10,'Harmonic maximum order','HarmonicMaxOrder',15,[7 99]);
            app.Controls.HarmonicMaxOrder.Tooltip='Reported Fourier descriptors only; this does not truncate the SPP reconstruction.';
            app.number(b,11,'Harmonic floor / I1 (%)','HarmonicFloor',.1,[.000001 99.99]);
            app.fieldLabel(b,12,'Input frequency');
            freq=uigridlayout(b,[1 2]);freq.Layout.Row=12;freq.Layout.Column=2;freq.Padding=[0 0 0 0];freq.ColumnWidth={'1x',64};freq.ColumnSpacing=4;
            app.Controls.Omega=uieditfield(freq,'text','Value','','Placeholder','Auto','FontName',app.Font,'ValueChangedFcn',@(~,~)app.settingsChanged());
            app.Controls.FrequencyUnit=uidropdown(freq,'Items',{'rad/s','Hz'},'Value','rad/s','FontName',app.Font,'ValueChangedFcn',@(~,~)app.safe(@()app.frequencyUnitChanged()));
            app.ParameterControls=[app.ParameterControls {app.Controls.Omega,app.Controls.FrequencyUnit}];
            app.number(b,13,'Points per cycle','PointsPerCycle',1001,[101 10001]);
            app.number(b,14,'Fit half-window (%)','FitWindowFraction',1.5,[.1 24]);
            app.number(b,15,'Smooth full-window (%)','SmoothFraction',2,[.1 40]);
            app.drop(b,16,'Average strain rate','StrainRateMode',{'Analytic sine','Numerical'},{'analytic_sine_fit','numerical'},'analytic_sine_fit');
            app.drop(b,17,'Average derivatives','DerivativeMode',{'5-point difference','SG derivative'},{'finite_difference','sgolay'},'finite_difference');
            app.drop(b,18,'Cycle detection signal','DetectCyclesFrom',{'Strain','Stress'},{'gamma','stress'},'gamma');
            cb=uicheckbox(b,'Text','Average: compare fit windows','Value',true,'FontName',app.Font,'ValueChangedFcn',@(~,~)app.settingsChanged()); cb.Layout.Row=19; cb.Layout.Column=[1 2];
            app.Controls.AssessWindowSensitivity=cb; app.ParameterControls{end+1}=cb;
            cb=uicheckbox(b,'Text','Average: compare smoothing windows','Value',true,'FontName',app.Font,'ValueChangedFcn',@(~,~)app.settingsChanged()); cb.Layout.Row=20; cb.Layout.Column=[1 2];
            app.Controls.AssessSmoothingSensitivity=cb; app.ParameterControls{end+1}=cb;
            hint=uilabel(b,'Text',{'Cycle IDs override trimming. Blank uses the eligible range.','Evolution keeps cycle order; no automatic endpoint trim.','Window sizes are fractions of one cycle.'},'WordWrap','on','FontName',app.Font,'FontSize',11,'FontColor',[.45 .48 .55]);
            hint.Layout.Row=[21 23]; hint.Layout.Column=[1 2];
            reset=uibutton(b,'Text','Restore recommended settings','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.safe(@()app.resetSettings())); reset.Layout.Row=24; reset.Layout.Column=[1 2];
            app.ActionControls{end+1}=reset;
            i=uigridlayout(imports,[13 2]); i.ColumnWidth={155,'1x'}; i.RowHeight=repmat({28},1,13); i.Padding=[8 10 8 10]; i.RowSpacing=7; i.Scrollable='on';
            app.drop(i,1,'Strain units','StrainUnit',{'Percent (%)','Decimal','Millistrain','Microstrain'},{'percent','decimal','millistrain','microstrain'},'percent');
            app.number(i,2,'Time column','TimeColumn',1,[1 Inf]); app.number(i,3,'Strain column','StrainColumn',2,[1 Inf]); app.number(i,4,'Stress column','StressColumn',3,[1 Inf]);
            app.number(i,5,'Skip header rows','HeaderLines',0,[0 Inf]);
            app.drop(i,6,'Text delimiter','Delimiter',{'Auto detect','Tab','Comma','Space'},{'auto','tab',',','space'},'auto');
            app.edit(i,7,'Excel sheet','Sheet','1','Name or number');
            hint=uilabel(i,'Text',{'Time must be seconds; stress must be Pa.','Count original columns, including text.','Check header and units in File preview.'},'FontName',app.Font,'FontSize',11,'FontColor',[.45 .48 .55]); hint.Layout.Row=[8 10]; hint.Layout.Column=[1 2];
            run=uigridlayout(actionParent,[1 2]); run.Padding=[0 0 0 0]; run.ColumnSpacing=8;
            app.Controls.AnalyzeSelected=uibutton(run,'Text','Analyze selected','FontName',app.Font,'FontColor',[1 1 1],'BackgroundColor',app.Blue,'ButtonPushedFcn',@(~,~)app.safe(@()app.analyze('selected')));
            app.Controls.AnalyzeAll=uibutton(run,'Text','Analyze all','FontName',app.Font,'BackgroundColor',[.91 .94 .98],'ButtonPushedFcn',@(~,~)app.safe(@()app.analyze('all')));
            app.Controls.Clear=uibutton(actionParent,'Text','Clear list','FontName',app.Font,'ButtonPushedFcn',@(~,~)app.clearFiles());
            app.ActionControls=[app.ActionControls {add,folder,example,app.Controls.Clear}];
        end

        function buildMain(app,parent)
            if app.OwnFigure
                g=uigridlayout(parent,[5 1]); g.RowHeight={135,68,38,22,'1x'}; tableParent=g;
            else
                g=uigridlayout(parent,[4 1]); g.RowHeight={60,38,22,'1x'}; tableParent=app.HiddenControls;
            end
            g.Padding=[0 0 0 0]; g.RowSpacing=8; g.BackgroundColor=app.Background;
            app.FileTable=uitable(tableParent,'ColumnName',{'File (multi-select to compare)','Status','Strain (%)','Omega (rad/s)','Mode'},'ColumnEditable',false, ...
                'ColumnWidth',{'auto',145,90,100,110},'RowName',{},'FontName',app.Font,'FontSize',12, ...
                'SelectionType','row','Multiselect','on','CellSelectionCallback',@(~,event)app.tableSelected(event));
            cards=uigridlayout(g,[1 4]); cards.Padding=[0 0 0 0]; cards.ColumnSpacing=10; cards.BackgroundColor=app.Background;
            names={'Amplitude','Omega','Cycles','Valid'}; titles={'Median strain amplitude / %','Estimated omega / rad s^-1','Eligible / detected cycles','SPP numerically valid points'};
            for k=1:4
                panel=uipanel(cards,'BorderType','none','BackgroundColor',[1 1 1]); cg=uigridlayout(panel,[2 1]); cg.RowHeight={20,30}; cg.Padding=[10 4 8 4]; cg.RowSpacing=0;
                uilabel(cg,'Text',titles{k},'FontName',app.Font,'FontSize',11,'FontColor',[.45 .5 .57]);
                app.Cards.(names{k})=uilabel(cg,'Text','—','FontName',app.Font,'FontSize',21,'FontWeight','bold','FontColor',app.Ink);
            end
            app.Controls.Banner=uilabel(g,'Text','Select a file, then start analysis','FontName',app.Font,'FontSize',12,'WordWrap','on','BackgroundColor',[.9 .93 .96],'FontColor',app.Ink);
            app.Controls.CurrentFile=uilabel(g,'Text','No file selected','FontName',app.Font,'FontSize',11,'FontColor',[.38 .43 .5]);
            app.Tabs=uitabgroup(g);
            evolution=uitab(app.Tabs,'Title','Cycle evolution'); eg=uigridlayout(evolution,[3 1]); eg.RowHeight={32,24,'1x'}; eg.Padding=[10 8 10 6];
            views=uigridlayout(eg,[1 6]); views.Padding=[0 0 0 0]; views.ColumnWidth={42,160,48,'1x',50,95};
            uilabel(views,'Text','X axis','FontName',app.Font);
            app.Controls.EvolutionXAxis=uidropdown(views,'Items',{'Cycle number','Elapsed seconds'},'ItemsData',{'cycle','seconds'},'Value','cycle','FontName',app.Font,'ValueChangedFcn',@(~,~)app.viewChanged());
            uilabel(views,'Text','Metric','FontName',app.Font);
            app.Controls.EvolutionMetric=uidropdown(views,'Items',{'G1 storage + loss','I2/I1','I3/I1','I5/I1','I7/I1','I1 (Pa)','I3 (Pa)','I5 (Pa)','I7 (Pa)','Work input per cycle','Strain + stress closure','Waveform change','SPP valid fraction'}, ...
                'ItemsData',{'G1','I2I1','I3I1','I5I1','I7I1','I1_Pa','I3_Pa','I5_Pa','I7_Pa','WorkInput_J_m3','closure','WaveformChangeRelative','ValidSPPFraction'},'Value','G1','FontName',app.Font,'ValueChangedFcn',@(~,~)app.viewChanged());
            app.Controls.EvolutionMetric.Tooltip='Closure is endpoint mismatch divided by strain amplitude or stress RMS, respectively. Work input is not automatically dissipated heat.';
            uilabel(views,'Text','Cycle ID','FontName',app.Font);
            app.Controls.CyclePicker=uidropdown(views,'Items',{'No cycles'},'ItemsData',0,'Value',0,'FontName',app.Font,'ValueChangedFcn',@(~,~)app.viewChanged());
            app.Controls.CycleInfo=uilabel(eg,'Text','Available cycle IDs and selected range appear after analysis.','FontName',app.Font,'FontSize',11,'FontColor',[.4 .45 .5]);
            plots=uigridlayout(eg,[2 2]); plots.Padding=[0 0 0 0]; plots.RowSpacing=13;
            for name={'CycleTrend','StressCycles','CycleColeCole','CycleModuli'}, app.Axes.(name{1})=app.newAxes(plots); end
            overview=uitab(app.Tabs,'Title','Average signals'); ov=uigridlayout(overview,[2 2]); ov.Padding=[10 8 10 6]; ov.RowSpacing=12;
            for name={'Strain','Stress','Moduli','ColeCole'}, app.Axes.(name{1})=app.newAxes(ov); end
            loops=uitab(app.Tabs,'Title','Lissajous'); lg=uigridlayout(loops,[1 2]); lg.Padding=[10 10 10 10];
            app.Axes.Elastic=app.newAxes(lg); app.Axes.Viscous=app.newAxes(lg);
            compare=uitab(app.Tabs,'Title','Compare files'); cg=uigridlayout(compare,[2 1]); cg.RowHeight={30,'1x'};
            uilabel(cg,'Text','Select multiple file rows. Same metric and time-axis choice as Cycle evolution; time resets within each file.','WordWrap','on','FontName',app.Font,'FontSize',11);
            cp=uigridlayout(cg,[1 2]); app.Axes.CompareTrend=app.newAxes(cp); app.Axes.CompareColeCole=app.newAxes(cp);
            windows=uitab(app.Tabs,'Title','Fit windows'); wg=uigridlayout(windows,[1 2]); wg.Padding=[10 10 10 10];
            app.Axes.WindowStorage=app.newAxes(wg); app.Axes.WindowLoss=app.newAxes(wg);
            smoothing=uitab(app.Tabs,'Title','Smoothing'); sg=uigridlayout(smoothing,[1 2]); sg.Padding=[10 10 10 10];
            app.Axes.SmoothStorage=app.newAxes(sg); app.Axes.SmoothLoss=app.newAxes(sg);
            metrics=uitab(app.Tabs,'Title','Cycle metrics'); mg=uigridlayout(metrics,[2 1]); mg.RowHeight={38,'1x'};
            uilabel(mg,'Text','All detected valid cycles. Included marks eligible cycles; InAverage marks the actual representative average. Cycles are repeated observations within one test.','WordWrap','on','FontName',app.Font,'FontSize',11);
            app.Controls.CycleTable=uitable(mg,'RowName',{},'FontName',app.Font,'FontSize',11);
            stationarity=uitab(app.Tabs,'Title','Stationarity'); st=uigridlayout(stationarity,[2 1]); st.RowHeight={62,'1x'};
            app.Controls.StationarityInfo=uilabel(st,'Text','Final contiguous candidate ranges and screening metrics will appear after analysis.','WordWrap','on','FontName',app.Font,'FontSize',11);
            app.Controls.StationarityTable=uitable(st,'RowName',{},'FontName',app.Font,'FontSize',11);
            quality=uitab(app.Tabs,'Title','Quality'); qg=uigridlayout(quality,[2 1]); qg.RowHeight={'1x',150};
            app.Controls.QualityTable=uitable(qg,'ColumnName',{'Metric','Value / interpretation'},'ColumnWidth',{270,'auto'},'RowName',{},'FontName',app.Font,'FontSize',12);
            app.Controls.QualityMessages=uitextarea(qg,'Editable','off','FontName',app.Font,'FontSize',12,'Value',{'Diagnostics will appear after analysis.'});
            preview=uitab(app.Tabs,'Title','File preview'); pg=uigridlayout(preview,[2 1]); pg.RowHeight={26,'1x'};
            uilabel(pg,'Text','First 12 text lines / 8 Excel rows. Analysis reads the original file.','FontName',app.Font,'FontSize',11);
            app.Controls.Preview=uitextarea(pg,'Editable','off','FontName',app.Font,'FontSize',12,'Value',{'Add a file to preview its header.'});
            evolution.UserData={'CycleTrend','StressCycles','CycleColeCole','CycleModuli'};
            overview.UserData={'Strain','Stress','Moduli','ColeCole'};
            loops.UserData={'Elastic','Viscous'}; compare.UserData={'CompareTrend','CompareColeCole'};
            windows.UserData={'WindowStorage','WindowLoss'};
            smoothing.UserData={'SmoothStorage','SmoothLoss'};
            app.Controls.EvolutionTab=evolution; app.Controls.AverageTab=overview;
            app.Tabs.SelectedTab=overview;
            app.Tabs.SelectionChangedFcn=@(~,~)app.viewChanged();
        end

        function ax=newAxes(app,parent)
            ax=uiaxes(parent,'FontName',app.Font,'FontSize',11,'Box','on','Color',[1 1 1]);
            ax.XGrid='on'; ax.YGrid='on'; ax.GridAlpha=.1; ax.Toolbar.Visible='on';
        end

        function number(app,g,row,label,name,value,limits)
            app.fieldLabel(g,row,label);
            c=uieditfield(g,'numeric','Value',value,'Limits',limits,'FontName',app.Font, ...
                'ValueChangedFcn',@(~,~)app.settingsChanged()); c.Layout.Row=row; c.Layout.Column=2;
            app.Controls.(name)=c; app.ParameterControls{end+1}=c;
        end
        function edit(app,g,row,label,name,value,placeholder)
            app.fieldLabel(g,row,label);
            c=uieditfield(g,'text','Value',value,'Placeholder',placeholder,'FontName',app.Font, ...
                'ValueChangedFcn',@(~,~)app.settingsChanged()); c.Layout.Row=row; c.Layout.Column=2;
            app.Controls.(name)=c; app.ParameterControls{end+1}=c;
        end
        function drop(app,g,row,label,name,items,data,value)
            app.fieldLabel(g,row,label);
            c=uidropdown(g,'Items',items,'ItemsData',data,'Value',value,'FontName',app.Font, ...
                'ValueChangedFcn',@(~,~)app.settingsChanged()); c.Layout.Row=row; c.Layout.Column=2;
            app.Controls.(name)=c; app.ParameterControls{end+1}=c;
        end
        function fieldLabel(app,g,row,text)
            c=uilabel(g,'Text',text,'FontName',app.Font,'FontSize',11); c.Layout.Row=row; c.Layout.Column=1;
        end

        function frequencyUnitChanged(app)
            unit=app.Controls.FrequencyUnit.Value;app.Controls.FrequencyUnit.Value=app.FrequencyUnit;
            app.applySettings(struct('FrequencyUnit',unit));
        end
        function changeFrequencyUnit(app,unit)
            unit=validatestring(char(unit),{'rad/s','Hz'});
            if strcmp(unit,app.FrequencyUnit),app.Controls.FrequencyUnit.Value=unit;return;end
            value=strtrim(app.Controls.Omega.Value);
            if ~isempty(value)
                value=str2double(value);
                if ~isfinite(value)||value<=0,error('SPPApp:Settings','Frequency must be positive or blank.');end
                factor=2*pi;if strcmp(unit,'Hz'),factor=1/factor;end
                app.Controls.Omega.Value=num2str(value*factor,17);
            end
            app.FrequencyUnit=unit;app.Controls.FrequencyUnit.Value=unit;
        end

        function settingsChanged(app)
            if app.Busy, return; end
            app.syncStates(); app.refreshTable(); app.renderSelected(); app.refreshEnable();
            app.setStatus('Settings updated | Reanalyze to apply them');
            if ~isempty(app.StateChangedFcn), feval(app.StateChangedFcn,app,[]); end
        end
        function syncStates(app,indices)
            if nargin<2, indices=1:numel(app.Entries); end
            if isempty(indices) || all(cellfun(@isempty,{app.Entries(indices).Result})), return; end
            try, options=app.currentOptions(); catch, options=[]; end
            for k=reshape(indices,1,[])
                if isempty(app.Entries(k).Result), continue; end
                if ~isequal(app.Entries(k).SourceSignature,app.sourceSignature(app.Entries(k).Path))
                    app.Entries(k).Status='stale'; app.Entries(k).StaleReason='Source file changed or missing';
                elseif ~isequaln(app.InputSettings,app.Entries(k).InputSettings)
                    app.Entries(k).Status='stale';app.Entries(k).StaleReason='Input units or import settings changed';
                elseif isempty(options) || ~isequaln(options,app.Entries(k).Options)
                    app.Entries(k).Status='stale'; app.Entries(k).StaleReason='Analysis settings changed';
                else
                    app.Entries(k).StaleReason='';
                    if app.Entries(k).Result.quality.has_warnings, app.Entries(k).Status='warning';
                    else, app.Entries(k).Status='ok'; end
                end
            end
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
            if ~app.OwnFigure, return; end  % The host owns the visible file list.
            n=numel(app.Entries); rows=cell(n,5);
            for k=1:n
                e=app.Entries(k); rows(k,:)={e.Name,app.statusText(e.Status),'—','—','—'};
                if ~isempty(e.Result)
                    ct=e.Result.evolution.cycle_table;
                    rows{k,3}=sprintf('%.5g',median(ct.StrainPercent,'omitnan'));
                    rows{k,4}=sprintf('%.6g',e.Result.omega); rows{k,5}=strrep(e.Result.analysis_mode,'_',' ');
                end
            end
            app.FileTable.Data=rows; removeStyle(app.FileTable);
            warn=find(ismember({app.Entries.Status},{'warning','stale'})); fail=find(strcmp({app.Entries.Status},'error'));
            if ~isempty(warn), addStyle(app.FileTable,uistyle('FontColor',app.Orange),'row',warn); end
            if ~isempty(fail), addStyle(app.FileTable,uistyle('FontColor',[.7 .16 .16]),'row',fail); end
            if ~isempty(app.SelectedIndices), app.FileTable.Selection=app.SelectedIndices; end
        end

        function text=statusText(~,state)
            switch state
                case 'pending', text='Pending';
                case 'ok', text='Complete';
                case 'warning', text='Review warnings';
                case 'error', text='Failed';
                case 'stale', text='Reanalysis required';
                otherwise, text=state;
            end
        end
        function refreshEnable(app)
            blocked=app.Busy || app.HostLocked;
            onoff='on'; if blocked, onoff='off'; end
            for k=1:numel(app.ParameterControls), app.ParameterControls{k}.Enable=onoff; end
            for k=1:numel(app.ActionControls), app.ActionControls{k}.Enable=onoff; end
            app.FileTable.Enable=onoff;
            if ~blocked
                average=strcmp(app.Controls.AnalysisMode.Value,'average');
                app.Controls.AveragingPolicy.Enable=average;
                app.Controls.SelectionMode.Enable=average && strcmp(app.Controls.AveragingPolicy.Value,'manual');
                app.Controls.StrainRateMode.Enable=average; app.Controls.DerivativeMode.Enable=average;
                app.Controls.AssessWindowSensitivity.Enable=average; app.Controls.AssessSmoothingSensitivity.Enable=average;
            end
            if ~isempty(app.GlobalStrainUnit)
                app.Controls.StrainUnit.Value=app.GlobalStrainUnit; app.Controls.StrainUnit.Enable='off';
                app.Controls.StrainUnit.Tooltip='Strain units are controlled by the merged analysis workspace.';
            end
            hasFiles=~isempty(app.Entries) && ~blocked;
            app.Controls.AnalyzeSelected.Enable=hasFiles && ~isempty(app.SelectedIndices); app.Controls.AnalyzeAll.Enable=hasFiles;
            app.Controls.Export.Enable=any(ismember({app.Entries.Status},{'ok','warning'}))&&~blocked;
            app.Controls.Cancel.Enable=app.Busy;
        end

        function finishRun(app)
            if ~isvalid(app), return; end
            app.Busy=false; app.refreshEnable();
            if app.CloseAfterRun, delete(app); end
        end
        function requireIdle(app)
            if app.Busy, error('SPPApp:Busy','Analysis is running. Wait for it to finish or click Stop.'); end
        end
        function setStatus(app,text)
            app.Controls.Status.Text=text; app.Controls.Status.Tooltip=text;
        end
        function safe(app,callback)
            try, callback();
            catch ME
                message=ME.message;
                app.setStatus(['Operation could not be completed: ' message]);
                uialert(app.Figure,message,'Operation could not be completed','Icon','error','Interpreter','none');
            end
        end

        function renderEmpty(app,allPages)
            if nargin<2, allPages=false; end
            if allPages, names=fieldnames(app.Axes);
            else, names=app.Tabs.SelectedTab.UserData; end
            app.resetAxes(names);
            for k=1:numel(names)
                ax=app.Axes.(names{k});
                title(ax,'Add data and run analysis','FontName',app.Font); xlabel(ax,''); ylabel(ax,'');
            end
            for n=fieldnames(app.Cards)', app.Cards.(n{1}).Text='—'; end
            app.Controls.CycleTable.Data=table(); app.Controls.StationarityTable.Data=table(); app.Controls.QualityTable.Data={};
            app.Controls.CyclePicker.ItemsData=[]; app.Controls.CyclePicker.Items={'No cycles'};
            app.Controls.CyclePicker.ItemsData=0; app.Controls.CyclePicker.Value=0;
            app.Controls.CycleInfo.Text='No analyzed cycle IDs available for this file.';
            app.Controls.StationarityInfo.Text='Stationarity candidate ranges appear after analysis.';
            app.Controls.QualityMessages.Value={'Quality metrics, warnings and settings will appear after analysis.'};
        end

        function resetAxes(app,names)
            for k=1:numel(names)
                ax=app.Axes.(names{k});
                cla(ax); hold(ax,'off'); colorbar(ax,'off'); legend(ax,'off');
            end
        end

        function renderSelected(app)
            if ~app.OwnFigure && isa(app.Parent,'matlab.ui.container.Tab') && app.Parent.Parent.SelectedTab~=app.Parent
                return
            end
            if app.SelectedIndex==0 || isempty(app.Entries), app.renderEmpty(); return; end
            e=app.Entries(app.SelectedIndex);
            app.Controls.CurrentFile.Text=['Detail: ' e.Name]; app.Controls.CurrentFile.Tooltip=e.Path;
            page=app.Tabs.SelectedTab.Title;
            if strcmp(page,'File preview'), app.previewFile(e.Path); end
            if isempty(e.Result)
                app.renderEmpty();
                if strcmp(e.Status,'error')
                    app.banner(['Analysis failed | ' e.Error],[1 .91 .91],[.6 .1 .1]); app.Controls.QualityMessages.Value={e.Error};
                else, app.banner('Pending | Check units and column numbers in Data & units',[.9 .93 .96],app.Ink); end
                if strcmp(page,'Compare files'), app.renderComparison(); end
                return
            end
            R=e.Result; ct=R.evolution.cycle_table;
            app.Cards.Amplitude.Text=sprintf('%.4g',median(ct.StrainPercent,'omitnan'));
            app.Cards.Omega.Text=sprintf('%.6g',R.omega);
            app.Cards.Cycles.Text=sprintf('%d / %d',numel(R.selection.eligible_cycles),height(ct));
            if ~isempty(R.average), vf=R.average.quality.valid_fraction; else, vf=mean(ct.ValidSPPFraction(ct.Included),'omitnan'); end
            app.Cards.Valid.Text=app.percent(vf);
            app.Cards.Valid.Tooltip='Fraction of numerically accepted SPP points. This does not validate physical origin, noise sensitivity or window independence.';
            mode=strrep(R.analysis_mode,'_',' ');
            if strcmp(e.Status,'stale'), app.banner([e.StaleReason ' | Previous ' mode ' result. Reanalyze before export.'],[1 .94 .82],app.Orange);
            elseif strcmp(R.analysis_mode,'average') && isempty(R.average), app.banner('No stable average found | Cycle diagnostics remain available. Review selection or use Cycle evolution.',[1 .94 .82],app.Orange);
            elseif R.quality.has_warnings
                if strcmp(R.analysis_mode,'cycle_evolution'), notice='Review Quality and Stationarity; local SPP remains window-sensitive.';
                else, notice='Review Quality, Fit windows and Smoothing before interpretation.'; end
                app.banner([mode ' | ' notice],[1 .94 .82],app.Orange);
            else, app.banner([mode ' | Numerical validity and stationarity checks do not establish physical origin.'],[.88 .95 .94],[.12 .36 .33]); end
            names=app.Tabs.SelectedTab.UserData;
            app.resetAxes(names);
            if isempty(R.average) && ismember(page,{'Average signals','Lissajous','Fit windows'})
                for k=1:numel(names)
                    ax=app.Axes.(names{k});
                    app.labelAxes(ax,'No representative average in this result','','');
                    text(ax,.5,.5,'Use Cycle evolution and Quality','Units','normalized','HorizontalAlignment','center');
                end
                return
            end
            switch page
                case 'Average signals'
                    A=R.average; ph=A.proc.t_norm;
                    ax=app.Axes.Strain; plot(ax,ph,A.analysis_cycle.gamma*100,'Color',[.65 .7 .76]); hold(ax,'on'); plot(ax,ph,A.proc.gamma*100,'Color',app.Blue,'LineWidth',1.4);
                    app.labelAxes(ax,'Measured and fitted strain','Cycle phase','Strain (%)'); legend(ax,{'Selected average','Used for analysis'},'Location','best','FontSize',10);
                    ax=app.Axes.Stress; plot(ax,ph,A.analysis_cycle.sigma_cycles/1000,'Color',[.8 .83 .87]); hold(ax,'on'); plot(ax,ph,A.proc.sigma/1000,'Color',app.Ink,'LineWidth',1.4);
                    app.labelAxes(ax,'Selected cycles and average stress','Cycle phase','Stress (kPa)');
                    ax=app.Axes.Moduli; plot(ax,ph,A.Gt_storage/1000,'Color',app.Blue,'LineWidth',1.2); hold(ax,'on'); plot(ax,ph,A.Gt_loss/1000,'Color',[.85 .39 .15],'LineWidth',1.2);
                    app.labelAxes(ax,'Transient local moduli','Cycle phase','Modulus (kPa)'); legend(ax,{'G′ₜ','G″ₜ'},'Location','best');
                    ax=app.Axes.ColeCole; plot(ax,A.Gt_storage/1000,A.Gt_loss/1000,'Color',app.Blue,'LineWidth',1.1); app.labelAxes(ax,'Representative average','G′ₜ (kPa)','G″ₜ (kPa)');
                case 'Lissajous'
                    A=R.average;
                    ax=app.Axes.Elastic; scatter(ax,A.proc.gamma*100,A.proc.sigma/1000,14,A.Gt_storage/1000,'filled'); app.labelAxes(ax,'Elastic Lissajous','Strain (%)','Stress (kPa)'); cb=colorbar(ax); cb.Label.String='G′ₜ (kPa)';
                    ax=app.Axes.Viscous; scatter(ax,A.proc.x,A.proc.sigma/1000,14,A.Gt_loss/1000,'filled'); app.labelAxes(ax,'Viscous Lissajous','Strain rate / omega','Stress (kPa)'); cb=colorbar(ax); cb.Label.String='G″ₜ (kPa)';
                case 'Cycle evolution'
                    app.renderEvolution();
                case 'Compare files'
                    app.updateCyclePicker(R);
                    app.renderComparison();
                case 'Fit windows'
                    app.plotWindows(R.average);
                case 'Smoothing'
                    app.plotSmoothing(R);
                case 'Cycle metrics'
                    app.Controls.CycleTable.Data=ct;
                case 'Stationarity'
                    if isfield(R.selection.diagnostics,'candidate_table')
                        app.Controls.StationarityTable.Data=R.selection.diagnostics.candidate_table;
                        app.Controls.StationarityInfo.Text=sprintf('Final contiguous block: %s. Each row tests a suffix ending at its final eligible cycle. Bulk checks use %.2f%%; significant complex-harmonic range/trend uses %.2f%% of its harmonic amplitude. At least %d cycles must pass. A passing suffix does not prove equilibrium.',mat2str(R.selection.diagnostics.final_contiguous_block),100*e.Options.StationarityTolerance,100*e.Options.HarmonicStationarityTolerance,e.Options.MinStableCycles);
                    else
                        app.Controls.StationarityTable.Data=table();
                        app.Controls.StationarityInfo.Text='No candidate table for this result.';
                    end
                case 'Quality'
                    app.renderQuality(e);
            end
        end

        function viewChanged(app)
            if app.Busy || app.HostLocked, return; end
            app.syncStates(app.SelectedIndices);
            app.refreshTable();
            app.renderSelected();
        end

        function [eligible,ids,previous]=updateCyclePicker(app,R)
            ct=R.evolution.cycle_table;
            eligible=find(ct.Included); if isempty(eligible), eligible=(1:height(ct))'; end
            ids=ct.CycleIndex(eligible); previous=app.Controls.CyclePicker.Value;
            app.Controls.CyclePicker.ItemsData=[];
            app.Controls.CyclePicker.Items=cellstr(string(ids));
            app.Controls.CyclePicker.ItemsData=ids(:)';
            if ~ismember(previous,ids), previous=ids(1); end
            app.Controls.CyclePicker.Value=previous;
            info=sprintf('Available IDs: %s | Average IDs: %s',mat2str(ids(:)'),mat2str(R.selection.average_cycles));
            app.Controls.CycleInfo.Text=info; app.Controls.CycleInfo.Tooltip=info;
        end

        function renderEvolution(app)
            R=app.Entries(app.SelectedIndex).Result; ev=R.evolution; ct=ev.cycle_table;
            [eligible,ids,previous]=app.updateCyclePicker(R);
            j=find(ct.CycleIndex==previous,1);
            [xx,xname]=app.cycleAxis(ct);
            [yy,names,yname]=app.metricData(ct);
            ax=app.Axes.CycleTrend; cla(ax); hold(ax,'on');
            colors=[app.Blue;.85 .39 .15];
            for m=1:size(yy,2)
                plot(ax,xx(eligible),yy(eligible,m),'-o','MarkerSize',4,'Color',colors(1+mod(m-1,2),:),'LineWidth',1.1,'DisplayName',names{m});
            end
            app.labelAxes(ax,'Within-file cycle behavior',xname,yname); legend(ax,'show','Location','best','Interpreter','none','FontSize',9);
            ax=app.Axes.StressCycles; cla(ax); hold(ax,'on');
            colors=turbo(256); colorIndex=1+round(255*(ids-min(ids))/max(max(ids)-min(ids),1));
            for m=1:numel(eligible)
                plot(ax,ev.phase/(2*pi),ev.sigma(:,eligible(m))/1000,'Color',colors(colorIndex(m),:),'LineWidth',.9);
            end
            colormap(ax,turbo(256));
            bounds=[min(ids) max(ids)]; if bounds(1)==bounds(2), bounds=bounds+[-.5 .5]; end
            clim(ax,bounds); cb=colorbar(ax); cb.Label.String='Cycle ID';
            app.labelAxes(ax,'Measured stress by cycle','Cycle phase','Stress (kPa)');
            ax1=app.Axes.CycleColeCole; ax2=app.Axes.CycleModuli; cla(ax1); cla(ax2);
            if isempty(ev.Gt_storage)
                for ax=[ax1 ax2]
                    text(ax,.5,.5,{'Cycle-specific SPP is available in','Cycle evolution mode'},'Units','normalized','HorizontalAlignment','center','FontName',app.Font);
                end
                app.labelAxes(ax1,'No cycle-specific SPP in average mode','G′ₜ (kPa)','G″ₜ (kPa)');
                app.labelAxes(ax2,'Cycle harmonics and metrics remain available','Cycle phase','Modulus (kPa)');
            else
                gp=ev.Gt_storage(:,j)/1000; gpp=ev.Gt_loss(:,j)/1000;
                if ~isempty(ev.valid), gp(~ev.valid(:,j))=NaN; gpp(~ev.valid(:,j))=NaN; end
                plot(ax1,gp,gpp,'Color',app.Blue,'LineWidth',1.2);
                app.labelAxes(ax1,sprintf('Cycle %d | continuous support; no forced closure',previous),'G′ₜ (kPa)','G″ₜ (kPa)');
                plot(ax2,ev.phase/(2*pi),gp,'Color',app.Blue,'LineWidth',1.2); hold(ax2,'on');
                plot(ax2,ev.phase/(2*pi),gpp,'Color',[.85 .39 .15],'LineWidth',1.2);
                app.labelAxes(ax2,sprintf('Cycle %d | masked unsupported points',previous),'Cycle phase','Modulus (kPa)'); legend(ax2,{'G′ₜ','G″ₜ'},'Location','best');
            end
        end

        function [xx,label]=cycleAxis(app,ct)
            if strcmp(app.Controls.EvolutionXAxis.Value,'seconds')
                xx=ct.ElapsedTime_s; label='Elapsed time within this file (s)';
            else
                xx=ct.CycleIndex; label='Detected valid cycle ID';
            end
        end

        function [values,names,label]=metricData(app,ct)
            key=app.Controls.EvolutionMetric.Value;
            switch key
                case 'G1'
                    values=[ct.G1Storage_Pa ct.G1Loss_Pa]/1000; names={'G1 storage','G1 loss'}; label='First-harmonic modulus (kPa)';
                case 'closure'
                    values=[ct.StrainClosureRelative ct.StressClosureRelative]*100;
                    names={'Strain closure','Stress closure'}; label='Relative endpoint mismatch (%)';
                case 'WorkInput_J_m3'
                    values=ct.(key); names={'Work input'}; label='Work input per cycle (J m^{-3})';
                case 'WaveformChangeRelative'
                    values=100*ct.(key); names={'Waveform change'}; label='Change relative to previous cycle (%)';
                case 'ValidSPPFraction'
                    values=100*ct.(key); names={'Numerically valid SPP'}; label='Valid SPP points (%)';
                otherwise
                    values=ct.(key);
                    if endsWith(key,'_Pa'), names={strrep(key,'_Pa','')}; label=[names{1} ' amplitude (Pa)'];
                    else, names={strrep(key,'I1','/I1')}; label=[names{1} ' (dimensionless)']; end
            end
        end

        function renderComparison(app)
            ax1=app.Axes.CompareTrend; ax2=app.Axes.CompareColeCole;
            cla(ax1); cla(ax2); legend(ax1,'off'); legend(ax2,'off'); hold(ax1,'on'); hold(ax2,'on');
            selected=app.SelectedIndices; colors=lines(max(1,numel(selected))); count=0; cycleID=app.Controls.CyclePicker.Value;
            for k=1:numel(selected)
                e=app.Entries(selected(k));
                if isempty(e.Result) || ~ismember(e.Status,{'ok','warning'}), continue; end
                R=e.Result; ct=R.evolution.cycle_table; incl=find(ct.Included); if isempty(incl), continue; end
                count=count+1;
                label=sprintf('%.4g%% | %s',median(ct.StrainPercent(incl),'omitnan'),e.Name);
                [xx,xname]=app.cycleAxis(ct); [yy,names,yname]=app.metricData(ct);
                for m=1:size(yy,2)
                    style='-'; if m>1, style='--'; end
                    plot(ax1,xx(incl),yy(incl,m),'LineStyle',style,'Color',colors(k,:),'LineWidth',1.2,'DisplayName',[label ' | ' names{m}]);
                end
                if ~isempty(R.average)
                    gp=R.average.Gt_storage; gpp=R.average.Gt_loss; curveLabel=[label ' | average'];
                elseif ~isempty(R.evolution.Gt_storage)
                    j=find(ct.CycleIndex==cycleID & ct.Included,1); if isempty(j), j=incl(1); end
                    gp=R.evolution.Gt_storage(:,j); gpp=R.evolution.Gt_loss(:,j);
                    if ~isempty(R.evolution.valid), gp(~R.evolution.valid(:,j))=NaN; gpp(~R.evolution.valid(:,j))=NaN; end
                    curveLabel=sprintf('%s | cycle %d',label,ct.CycleIndex(j));
                else, gp=[]; gpp=[]; curveLabel=label; end
                if ~isempty(gp), plot(ax2,gp/1000,gpp/1000,'Color',colors(k,:),'LineWidth',1.1,'DisplayName',curveLabel); end
            end
            if count==0
                app.labelAxes(ax1,'Select files with current completed results','','');
                app.labelAxes(ax2,'Pending and stale results excluded','','');
            else
                app.labelAxes(ax1,'Selected files | within-file time axes',xname,yname);
                app.labelAxes(ax2,'Selected files | SPP response','G′ₜ (kPa)','G″ₜ (kPa)');
                legend(ax1,'show','Location','best','Interpreter','none','FontSize',8);
                if ~isempty(ax2.Children), legend(ax2,'show','Location','best','Interpreter','none','FontSize',8); end
            end
        end

        function plotSmoothing(app,R)
            ax1=app.Axes.SmoothStorage; ax2=app.Axes.SmoothLoss;
            app.labelAxes(ax1,'Storage component | Smoothing windows','Cycle phase','G′ₜ (kPa)');
            app.labelAxes(ax2,'Loss component | Smoothing windows','Cycle phase','G″ₜ (kPa)');
            if ~isfield(R,'smoothing_sensitivity') || isempty(R.smoothing_sensitivity)
                for ax=[ax1 ax2]
                    text(ax,.5,.5,{'Smoothing comparison not assessed','for this result'},'Units','normalized','HorizontalAlignment','center','FontName',app.Font);
                end
                return
            end
            z=R.smoothing_sensitivity; hold(ax1,'on'); hold(ax2,'on'); colors=lines(numel(z.fractions));
            phase=z.phase; if max(phase)>1.01, phase=phase/(2*pi); end
            for k=1:numel(z.fractions)
                gp=z.Gt_storage(:,k)/1000; gpp=z.Gt_loss(:,k)/1000;
                if ~isempty(z.valid), gp(~z.valid(:,k))=NaN; gpp(~z.valid(:,k))=NaN; end
                plot(ax1,phase,gp,'Color',colors(k,:),'LineWidth',1.1,'DisplayName',sprintf('%.2f%% | ΔRMS %.1f%%',100*z.fractions(k),100*z.storage_rms_change(k)));
                plot(ax2,phase,gpp,'Color',colors(k,:),'LineWidth',1.1,'DisplayName',sprintf('%.2f%% | ΔRMS %.1f%%',100*z.fractions(k),100*z.loss_rms_change(k)));
            end
            legend(ax1,'show','Location','best','FontSize',9); legend(ax2,'show','Location','best','FontSize',9);
        end

        function banner(app,text,bg,fg)
            app.Controls.Banner.Text=['  ' text]; app.Controls.Banner.Tooltip=text;
            app.Controls.Banner.BackgroundColor=bg; app.Controls.Banner.FontColor=fg;
        end
        function labelAxes(app,ax,titleText,x,y)
            title(ax,titleText,'FontName',app.Font,'FontWeight','normal'); xlabel(ax,x,'FontName',app.Font); ylabel(ax,y,'FontName',app.Font);
        end
        function plotWindows(app,R)
            ax1=app.Axes.WindowStorage; ax2=app.Axes.WindowLoss; w=R.proc.window_sensitivity;
            if isempty(w)
                plot(ax1,R.proc.t_norm,R.Gt_storage/1000); plot(ax2,R.proc.t_norm,R.Gt_loss/1000);
                text(ax1,.5,.9,'Window comparison is disabled','Units','normalized','HorizontalAlignment','center','FontName',app.Font);
            else
                hold(ax1,'on'); hold(ax2,'on');
                colors=[.16 .4 .7;.9 .45 .16;.25 .6 .49];
                for j=1:numel(w)
                    name=sprintf('Half-window %.2f%%',100*w(j).fraction); color=colors(1+mod(j-1,3),:);
                    plot(ax1,R.proc.t_norm,w(j).Gt_storage/1000,'DisplayName',name,'Color',color,'LineWidth',1.2);
                    plot(ax2,R.proc.t_norm,w(j).Gt_loss/1000,'DisplayName',name,'Color',color,'LineWidth',1.2);
                end
                legend(ax1,'show','Location','best','FontName',app.Font); legend(ax2,'show','Location','best','FontName',app.Font);
            end
            app.labelAxes(ax1,'Storage component | Fit windows','Cycle phase','G′ₜ (kPa)');
            app.labelAxes(ax2,'Loss component | Fit windows','Cycle phase','G″ₜ (kPa)');
        end
        function renderQuality(app,e)
            R=e.Result; q=R.quality; sel=R.selection;
            rows={'Analysis mode',R.analysis_mode;'Selection status',char(string(sel.status)); ...
                'Eligible cycle IDs',mat2str(sel.eligible_cycles);'Analyzed cycle IDs',mat2str(sel.analyzed_cycles); ...
                'Average cycle IDs',mat2str(sel.average_cycles);'Stable final cycle IDs',mat2str(sel.stable_tail_cycles); ...
                'Stationarity test passed',char(string(sel.stationarity_pass)); ...
                'Bulk stationarity tolerance',app.percent(e.Options.StationarityTolerance); ...
                'Complex-harmonic range / trend tolerance',app.percent(e.Options.HarmonicStationarityTolerance); ...
                'Minimum stable cycles',num2str(e.Options.MinStableCycles); ...
                'Harmonic maximum order',num2str(e.Options.HarmonicMaxOrder); ...
                'Harmonic floor / I1',app.percent(e.Options.HarmonicFloor); ...
                'Time axis origin','Elapsed time resets within each input file'; ...
                'Input strain units',e.Options.StrainUnit; ...
                'Original columns',sprintf('Time %d / strain %d / stress %d',e.Options.TimeColumn,e.Options.StrainColumn,e.Options.StressColumn)};
            if ~isempty(R.average)
                A=R.average; w=A.proc.window_sensitivity; storage=NaN; loss=NaN;
                if ~isempty(w), storage=max([w.storage_rms_change]); loss=max([w.loss_rms_change]); end
                rows=[rows; {'Average valid phase points',app.percent(A.quality.valid_fraction); ...
                    'Storage fit-window change',app.percent(storage);'Loss fit-window change',app.percent(loss); ...
                    'Average fit half-window',sprintf('%d points / %.3f%%',A.effective_settings.FitHalfWindow,100*A.effective_settings.FitWindowFraction); ...
                    'Average smoothing full-window',sprintf('%d points',A.effective_settings.SmoothWindow)}];
            end
            if isfield(sel.diagnostics,'eligible_metrics')
                m=sel.diagnostics.eligible_metrics;
                rows=[rows; {'Eligible maximum screen / tolerance',sprintf('%.4g (pass requires ≤1)',m.maximum_screen_ratio); ...
                    'Eligible stress waveform scatter',app.percent(m.stress_waveform_scatter); ...
                    'Eligible total stress waveform trend',app.percent(m.stress_waveform_total_trend); ...
                    'Eligible max. significant harmonic change',app.percent(m.max_significant_harmonic_change); ...
                    'Eligible max. significant harmonic trend',app.percent(m.max_significant_harmonic_trend)}];
            end
            if strcmp(R.analysis_mode,'cycle_evolution')
                rows=[rows; {'Cycle strain-rate method','Actual-time local polynomial derivative'; ...
                    'Cycle boundary treatment','Continuous measured neighbors; unsupported block edges masked'}];
            end
            app.Controls.QualityTable.Data=rows;
            messages={'Repeated cycles within one test are not independent specimens. Stationarity is a numerical screen, not proof of equilibrium.'; ...
                'Work input can include stored-energy changes during evolution; it is not automatically dissipated heat. No relaxation time is inferred.'; ...
                'Even harmonics are retained as measured asymmetry; material, contact and instrument origins require separate evidence.'};
            if strcmp(e.Status,'stale'), messages{end+1}=[e.StaleReason '. Previous results shown; stale results cannot be exported.']; end
            if isempty(R.average) && strcmp(R.analysis_mode,'average'), messages{end+1}='No stable representative cycle was produced. Review cycle metrics or choose manual selection explicitly.'; end
            qm=cellstr(string(q.messages));
            for k=1:numel(qm), messages{end+1}=['• ' qm{k}]; end
            app.Controls.QualityMessages.Value=messages;
        end

        function s=percent(~,v)
            if ~isfinite(v), s='Not assessed'; else, s=sprintf('%.3g%%',100*v); end
        end
        function s=translateWarning(~,s)
            % Core quality messages are already English. Preserve them verbatim.
        end
        function previewFile(app,path)
            try
                [~,~,ext]=fileparts(path);
                if any(strcmpi(ext,{'.xls','.xlsx'}))
                    sheet=app.Controls.Sheet.Value; n=str2double(sheet); if isfinite(n), sheet=n; end
                    c=readcell(path,'Sheet',sheet,'Range','A1:H8'); lines=cell(size(c,1),1);
                    for j=1:size(c,1), lines{j}=strjoin(cellfun(@(x)char(string(x)),c(j,:),'UniformOutput',false),' | '); end
                else
                    f=fopen(path,'r'); if f<0, error('Could not read the file.'); end
                    clean=onCleanup(@()fclose(f)); lines={}; %#ok<NASGU>
                    for j=1:12, line=fgetl(f); if ~ischar(line), break; end; lines{end+1}=line; end
                end
                if isempty(lines), lines={'The file is empty.'}; end
                app.Controls.Preview.Value=lines;
            catch ME, app.Controls.Preview.Value={['Preview unavailable: ' ME.message]}; end
        end

        function tableSelected(app,event)
            if app.Busy || isempty(event.Indices), return; end
            app.selectFiles(unique(event.Indices(:,1),'stable'));
        end

        function chooseFiles(app)
            [files,folder]=uigetfile({'*.dat;*.csv;*.txt;*.tsv;*.xls;*.xlsx','Rheology data';'*.*','All files'},'Select data files','MultiSelect','on');
            if isequal(files,0), return; end
            if ischar(files), files={files}; end
            app.addFiles(cellfun(@(f)fullfile(folder,f),files,'UniformOutput',false));
        end
        function chooseFolder(app)
            folder=uigetdir(pwd,'Select a data folder'); if isequal(folder,0), return; end
            app.addFolder(folder);
        end
        function addFolder(app,folder)
            files=dir(folder); keep=false(size(files));
            for k=1:numel(files), [~,~,ext]=fileparts(files(k).name); keep(k)=~files(k).isdir && any(strcmpi(ext,{'.dat','.csv','.txt','.tsv','.xls','.xlsx'})); end
            files=files(keep); [~,ix]=sort({files.name}); files=files(ix);
            if isempty(files), error('SPPApp:Files','The folder contains no supported data files.'); end
            app.addFiles(arrayfun(@(f)fullfile(f.folder,f.name),files,'UniformOutput',false));
        end
        function loadPackageDemo(app)
            file=fullfile(app.Root,'..','ft','examples','SMS-LAOS app synthetic demo.dat');
            if ~isfile(file), error('SPPApp:Files','The synthetic demo is missing. Restore the complete SMS-LAOS project folder.'); end
            app.setStrainUnit('decimal'); app.addFiles(file);
        end
        function chooseExport(app)
            folder=uigetdir(app.Root,'Choose an export location; a new results subfolder will be created'); if isequal(folder,0), return; end
            out=fullfile(folder,['SPP_results_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
            app.exportResults(out);
        end
        function chooseView(app)
            [name,folder]=uiputfile({'*.png','PNG image';'*.pdf','PDF document'},'Save the current view','SPP_view.png');
            if isequal(name,0), return; end
            app.saveView(fullfile(folder,name));
        end
        function resetSettings(app)
            defaults=struct('AnalysisMode','average','AveragingPolicy','stable_tail','MinStableCycles',5, ...
                'StationarityTolerance',.05,'HarmonicStationarityTolerance',.25,'HarmonicMaxOrder',15,'HarmonicFloor',.001, ...
                'StrainUnit','percent','TimeColumn',1,'StrainColumn',2,'StressColumn',3, ...
                'HeaderLines',0,'Delimiter','auto','Sheet',1,'Omega',[],'TrimCycles',[0 0], ...
                'SelectionMode','average','CycleNumbers',[],'PointsPerCycle',1001,'FitWindowFraction',.015, ...
                'SmoothFraction',.02,'StrainRateMode','analytic_sine_fit','DerivativeMode','finite_difference', ...
                'DetectCyclesFrom','gamma','AssessWindowSensitivity',true,'AssessSmoothingSensitivity',true);
            if ~app.OwnFigure,defaults=rmfield(defaults,{'StrainUnit','TimeColumn','StrainColumn','StressColumn','HeaderLines','Delimiter','Sheet'});end
            app.applySettings(defaults);
        end

        function clearFiles(app)
            app.requireIdle();
            app.Entries=app.Entries([]); app.SelectedIndex=0; app.SelectedIndices=[]; app.refreshTable(); app.renderEmpty(true); app.refreshEnable();
            app.Controls.CurrentFile.Text='No file selected'; app.Controls.Preview.Value={'Add a file to preview its header.'};
            app.banner('Select a file, then start analysis',[.9 .93 .96],app.Ink); app.setStatus('File list cleared');
        end
        function showHelp(app)
            message=sprintf(['Average response: select a stable final set of cycles, align by input phase and average. If the stationarity screen finds no qualifying final set, no average is produced. Manual selection remains an explicit alternative.\n\n' ...
                'Default stationarity screening uses separate empirical limits: 5% for bulk amplitude, waveform, period and closure checks; 25% for the maximum complex-coefficient range and whole-window trend relative to each significant harmonic amplitude. These are engineering screens, not confidence intervals or noise estimates.\n\n' ...
                'Cycle evolution: preserve cycle order and time, inspect each cycle and compare one or more strain files. Derivatives use continuous measured neighbors without wrapping every cycle; outer boundaries and gaps are masked. No curve is forced closed.\n\n' ...
                'Cycle IDs override trimming. Blank IDs use the eligible range; default trimming is zero. The cycle picker changes only the displayed cycle, not analysis selection. Elapsed seconds reset within each file, not at a known common loading onset.\n\n' ...
                'Select multiple file rows for comparisons and Analyze selected. Import defaults use time/strain/stress columns 1/2/3, automatic delimiter detection and zero explicitly skipped rows. In the merged workspace, strain units are controlled by the shared input setting. Check every new format.\n\n' ...
                'Harmonics include even orders. A repeated second harmonic indicates measured half-cycle asymmetry, not proven material origin. Harmonic floor is a diagnostic relevance threshold, not a command to erase even harmonics.\n\n' ...
                'Cycle repetitions are not independent specimens. Work input during evolution may include stored energy and is not automatically heat. Trends alone do not identify a relaxation time or mechanism. Check both modulus components and window sensitivity.\n\n' ...
                'Changing settings or source files marks results stale. Reanalyze before exporting. Export creates a new results folder; Stop takes effect after the current file finishes.']);
            uialert(app.Figure,message,'SMS-LAOS — SPP guide','Icon','info','Interpreter','none');
        end

        function onClose(app)
            if app.Busy, app.CloseAfterRun=true; app.requestCancel(); else, delete(app); end
        end
    end
end
