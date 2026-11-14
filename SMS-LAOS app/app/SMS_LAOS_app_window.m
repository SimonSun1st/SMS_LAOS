classdef SMS_LAOS_app_window < handle
    % One input workspace, three optional methods, and a final export step.
    properties (SetAccess=private)
        Figure
        Controls=struct()
        Tabs
        Axes=struct()
        FT
        SD
        SPP
        Entries=struct('Path',{},'Name',{},'Preview',{},'PreviewError',{},'FTDone',{},'StressDone',{})
        SelectedIndices=[]
        Busy=false
        LastExport=''
    end
    properties (Access=private)
        Root
        CancelRequested=false
        CloseAfterRun=false
        Exporting=false
        ExportUpdateClock
        Updating=false
        PreviewLines=struct()
        TabChangedWhileBusy=false
        InputSettings=struct()
        ActionControls={}
        BatchRowStates={}
    end
    methods
        function app=SMS_LAOS_app_window(varargin)
            p=inputParser;p.addParameter('Visible','on');p.parse(varargin{:});
            app.Root=fileparts(fileparts(mfilename('fullpath')));
            app.InputSettings=SMS_LAOS_app_input_defaults();
            app.buildUI();
            app.Updating=true;
            app.FT=SMS_LAOS_app_FT_SD_module('Parent',app.Controls.FTSettings,'HostFigure',app.Figure,'Role','ft');
            app.SD=SMS_LAOS_app_FT_SD_module('Parent',app.Controls.StressTab,'HostFigure',app.Figure,'Role','stress');
            app.SPP=SMS_LAOS_app_SPP_module('Parent',app.Controls.SPPTab,'HostFigure',app.Figure);
            app.FT.setInputSettings(app.InputSettings);app.SD.setInputSettings(app.InputSettings);app.SPP.setInputSettings(app.InputSettings);
            app.FT.StateChangedFcn=@(~)app.moduleChanged();
            app.SD.StateChangedFcn=@(~)app.moduleChanged();
            app.SPP.StateChangedFcn=@(~,~)app.moduleChanged();
            app.Updating=false;
            app.refresh();app.Figure.Visible=p.Results.Visible;
        end

        function addFiles(app,paths)
            app.requireIdle();
            if ischar(paths)||isstring(paths),paths=cellstr(paths);end
            finish=app.startRun(false); %#ok<NASGU>
            app.setStatus(sprintf('Checking %d input paths…',numel(paths)));drawnow;
            known=configureDictionary('string','logical');
            if ~isempty(app.Entries),known(string({app.Entries.Path}))=true;end
            % Validate before publishing a new list. Keep full paths as the file identity.
            added=cell(size(paths));count=0;lastUpdate=tic;
            for k=1:numel(paths)
                if toc(lastUpdate)>.15
                    app.setStatus(sprintf('Checking file %d / %d…',k,numel(paths)));drawnow;lastUpdate=tic;
                end
                if app.CancelRequested,app.setStatus('Load stopped before adding files.');return;end
                path=char(paths{k});
                if ~isfile(path),error('MergedLAOS:File','File not found: %s',path);end
                [ok,a]=fileattrib(path);if ok,path=a.Name;end
                key=string(path);
                if isKey(known,key),continue;end
                [~,~,ext]=fileparts(path);
                if ~ismember(lower(ext),{'.dat','.csv','.txt','.tsv','.xls','.xlsx'})
                    error('MergedLAOS:File','Unsupported file type: %s',ext);
                end
                known(key)=true;count=count+1;added{count}=path;
            end
            if count>0
                blank=struct('Path','','Name','','Preview',[],'PreviewError','','FTDone',false,'StressDone',false);
                entries=repmat(blank,1,count);
                for k=1:count
                    path=added{k};[~,name,ext]=fileparts(path);
                    entries(k).Path=path;entries(k).Name=[name ext];
                end
                app.Entries=[reshape(app.Entries,1,[]) entries];
                if isempty(app.SelectedIndices),app.SelectedIndices=1;end
                app.syncFileLists();
            end
            app.Tabs.SelectedTab=app.Controls.InputTab;
            app.refreshTable();
            app.loadPreviews(1:numel(app.Entries));
            app.refresh();app.reportPreviews();
        end

        function addFolder(app,folder)
            app.requireIdle();files=dir(folder);paths={};
            for k=1:numel(files)
                [~,~,ext]=fileparts(files(k).name);
                if ~files(k).isdir&&ismember(lower(ext),{'.dat','.csv','.txt','.tsv','.xls','.xlsx'})
                    paths{end+1}=fullfile(files(k).folder,files(k).name); %#ok<AGROW>
                end
            end
            if isempty(paths),error('MergedLAOS:File','No supported data files were found.');end
            app.addFiles(sort(paths));
        end

        function selectFiles(app,indices)
            app.requireIdle();
            if isempty(indices)||any(indices<1)||any(indices>numel(app.Entries))||any(indices~=fix(indices))
                error('MergedLAOS:Selection','Select one or more valid files.');
            end
            app.SelectedIndices=unique(indices(:)','stable');
            app.syncSelection();
            i=app.SelectedIndices(1);
            if isempty(app.Entries(i).Preview)&&isempty(app.Entries(i).PreviewError)
                finish=app.startRun(false); %#ok<NASGU>
                app.setStatus(['Preparing waveform | ' app.Entries(i).Name]);drawnow;
                if app.CancelRequested,app.refresh(app.SelectedIndices);app.reportPreviews();return;end
                app.loadPreview(i);
                app.reportPreviews();
            end
            app.refresh(app.SelectedIndices);
        end

        function setMethods(app,s)
            app.requireIdle();
            if ~isstruct(s)||~isscalar(s),error('MergedLAOS:Method','Methods must be a scalar structure.');end
            for n=fieldnames(s)'
                if ~ismember(n{1},{'FT','Stress','SPP'}),error('MergedLAOS:Method','Unknown method: %s',n{1});end
                v=s.(n{1});
                if ~(islogical(v)||isnumeric(v))||~isscalar(v)||~ismember(v,[0 1])
                    error('MergedLAOS:Method','Method values must be scalar true or false.');
                end
            end
            for n=fieldnames(s)'
                app.Controls.(['Use' n{1}]).Value=logical(s.(n{1}));
            end
            app.methodsChanged();
        end

        function retryPreview(app)
            app.requireIdle();
            if isempty(app.SelectedIndices),return;end
            i=app.SelectedIndices(1);
            finish=app.startRun(false); %#ok<NASGU>
            app.loadPreviews(i);
            app.refresh(i);app.reportPreviews();
        end

        function m=methodsSelected(app)
            m=struct('FT',app.Controls.UseFT.Value,'Stress',app.Controls.UseStress.Value,'SPP',app.Controls.UseSPP.Value);
        end

        function setStrainUnit(app,unit)
            app.setInputSettings(struct('StrainUnit',unit));
        end

        function s=currentInputSettings(app)
            s=app.InputSettings;
        end

        function setInputSettings(app,s)
            app.requireIdle();
            if ~isstruct(s)||~isscalar(s),error('MergedLAOS:InputSettings','Input settings must be a scalar structure.');end
            next=app.InputSettings;
            for n=fieldnames(s)',next.(n{1})=s.(n{1});end
            next=SMS_LAOS_app_input_defaults(next);
            if isempty(next.HeaderLines),next.HeaderLines=0;end
            if isequaln(next,app.InputSettings),return;end
            app.Updating=true;finish=onCleanup(@()app.finishUpdate()); %#ok<NASGU>
            app.FT.setInputSettings(next);app.SD.setInputSettings(next);app.SPP.setInputSettings(next);
            app.InputSettings=next;app.populateInputControls();
            app.resetBatchProgress();
            % The new column mapping or units may represent different strain levels.
            app.Controls.StrainChoices.Data=cell(0,3);
            app.Controls.StrainChoices.UserData=cell(0,1);
            % Discard every old-unit preview before allowing Stop during the rebuild.
            for k=1:numel(app.Entries)
                app.Entries(k).Preview=[];app.Entries(k).PreviewError='';
            end
            run=app.startRun(false); %#ok<NASGU>
            app.refreshTable();
            app.loadPreviews(1:numel(app.Entries));app.refresh();
            app.reportPreviews();
        end

        function removeSelected(app)
            app.requireIdle();app.Entries(app.SelectedIndices)=[];
            app.SelectedIndices=[];if ~isempty(app.Entries),app.SelectedIndices=1;end
            app.syncFileLists();app.refresh();
        end

        function clearFiles(app)
            app.requireIdle();app.Entries=app.Entries([]);app.SelectedIndices=[];
            app.syncFileLists();app.refresh();
            % Release full-resolution waveforms and FFT data held by hidden axes.
            if ~isequal(app.Tabs.SelectedTab,app.Controls.InputTab),app.renderPreview();end
            if ~isequal(app.Tabs.SelectedTab,app.Controls.FTTab),app.renderFT();end
        end

        function analyze(app,scope)
            app.requireIdle();if nargin<2,scope='selected';end
            m=app.methodsSelected();
            if ~any(structfun(@logical,m)),error('MergedLAOS:Method','Tick at least one analysis method.');end
            if isempty(app.Entries),error('MergedLAOS:File','Load data first.');end
            if strcmp(scope,'all'),ids=1:numel(app.Entries);
            elseif strcmp(scope,'selected'),ids=app.SelectedIndices;
            else,error('MergedLAOS:Scope','Scope must be selected or all.');end
            if isempty(ids),error('MergedLAOS:Selection','Select a data file.');end
            modules={app.FT,app.SD,app.SPP};labels={'FT-LAOS','Stress decomposition','SPP'};
            methods=find([m.FT m.Stress m.SPP]);options=cell(size(modules));
            for j=methods,options{j}=modules{j}.currentOptions();end
            finish=app.startRun(false); %#ok<NASGU>
            files=numel(ids);stepsPerFile=numel(methods);steps=0;
            shortNames={'FT','SD','SPP'};fileTable=app.Controls.FileTable;
            app.BatchRowStates=cell(1,numel(app.Entries));
            app.BatchRowStates(ids)={'Waiting'};
            try
                app.refreshTable(ids);
                app.showBatchProgress('Running',steps,files,stepsPerFile);
                for k=1:files
                    if app.CancelRequested,break;end
                    i=ids(k);
                    fileTable.BackgroundColor(i,:)=[.82 .91 1];
                    if strcmp(app.Figure.Visible,'on')
                        % MATLAB scrolls the requested row to the top. Keep
                        % recent results visible immediately above the active row.
                        visibleRows=max(1,floor((fileTable.Position(4)-30)/26));
                        preceding=min(5,floor((visibleRows-1)/2));
                        scroll(fileTable,'row',max(1,i-preceding));
                    end
                    for j=methods
                        app.BatchRowStates{i}=['Running: ' shortNames{j}];
                        fileTable.Data{i,3}=app.BatchRowStates{i};
                        app.setStatus(sprintf('%s | File %d / %d | %s',labels{j},k,files,app.Entries(i).Name));
                        drawnow limitrate;
                        if app.CancelRequested,break;end
                        if j==methods(1),app.loadPreview(i);end
                        success=modules{j}.analyzeFile(i,options{j});
                        if j==1,app.Entries(i).FTDone=success;end
                        if j==2,app.Entries(i).StressDone=success;end
                        steps=steps+1;
                        app.showBatchProgress('Running',steps,files,stepsPerFile);
                        if app.CancelRequested,break;end
                    end
                    app.BatchRowStates{i}='';
                    app.refreshTable(i);
                end
            catch ME
                app.finishBatchDisplay('Interrupted',ids,steps,stepsPerFile);
                rethrow(ME)
            end
            word='Analysis complete';if app.CancelRequested&&steps<files*stepsPerFile,word='Stopped';end
            app.finishBatchDisplay(word,ids,steps,stepsPerFile);
            app.setStatus(sprintf('%s | %d / %d files processed. Review individual method status and diagnostics, then Export.',word,floor(steps/stepsPerFile),files));
        end

        function requestCancel(app)
            if app.Busy&&~app.Exporting
                app.CancelRequested=true;app.FT.requestCancel();app.SD.requestCancel();app.SPP.requestCancel();
                app.setStatus('Stopping after the current file operation finishes.');
            end
        end

        function cancelExport(app)
            if app.Exporting
                app.CancelRequested=true;
                app.Controls.CancelExport.Enable='off';
                app.Controls.ExportProgress.Text='Cancelling after the current write…';
                app.setStatus(app.Controls.ExportProgress.Text);
            end
        end

        function refresh(app,indices)
            if isempty(app.FT)||isempty(app.SD)||isempty(app.SPP),return;end
            if nargin<2,indices=1:numel(app.Entries);else,indices=reshape(indices,1,[]);end
            page=app.Tabs.SelectedTab;
            stress=isequal(page,app.Controls.StressTab);
            spp=isequal(page,app.Controls.SPPTab);
            app.FT.refresh(indices,false);app.SD.refresh(indices,stress);app.SPP.refresh(indices,spp);
            app.refreshTable(indices);
            app.refreshStrainChoices();
            if isequal(page,app.Controls.InputTab)
                app.renderPreview();
            elseif isequal(page,app.Controls.FTTab)
                app.renderFT();
            elseif stress
                app.renderStressAvailability();
            end
            app.TabChangedWhileBusy=false;
        end

        function manifest=exportResults(app,folder)
            app.requireIdle();
            options=struct('Methods',app.methodsSelected(),'IncludeWaveforms',app.Controls.ExportWaveforms.Value, ...
                'IncludeLissajous',app.Controls.ExportLissajous.Value,'Lissajous',app.lissajousOptions(app.Controls.ExportLissajous.Value), ...
                'InputSettings',app.InputSettings,'SDOptions',struct('fast_mode',strcmp(app.Controls.ExportMode.Value,'fast'), ...
                'save_curve_csv',app.Controls.ExportCurves.Value));
            manifest=app.runExport(folder,@()app.writeResults(folder,options));
        end

        function manifest=exportLissajous(app,folder,options)
            app.requireIdle();
            if nargin<3,options=app.lissajousOptions();end
            manifest=app.runExport(folder,@()app.writeLissajous(folder,options));
        end

        function saveView(app,path,page)
            app.requireIdle();if isfile(path),error('MergedLAOS:Exists','Choose a new output filename.');end
            if nargin>2
                page=validatestring(page,{'InputTab','FTTab','StressTab','SPPTab','ExportTab'});
                previous=app.Tabs.SelectedTab;finish=onCleanup(@()app.restoreView(previous)); %#ok<NASGU>
                app.Tabs.SelectedTab=app.Controls.(page);
            end
            app.refresh(app.SelectedIndices);
            drawnow;exportapp(app.Figure,path);
        end

        function delete(app)
            if ~isempty(app.FT)&&isvalid(app.FT),delete(app.FT);end
            if ~isempty(app.SD)&&isvalid(app.SD),delete(app.SD);end
            if ~isempty(app.SPP)&&isvalid(app.SPP),delete(app.SPP);end
            if ~isempty(app.Figure)&&isvalid(app.Figure),delete(app.Figure);end
        end
    end
    methods (Access=private)
        function manifest=runExport(app,folder,write)
            finish=app.startRun(true); %#ok<NASGU>
            app.ExportUpdateClock=[];
            try
                app.exportProgress(0,'Preparing export…');
                manifest=write();
            catch ME
                if strcmp(ME.identifier,'MergedLAOS:ExportCancelled')
                    message='Export cancelled.';
                else
                    message=['Export failed: ' ME.message];
                end
                app.Controls.ExportProgress.Text=message;
                app.Controls.ExportProgress.Tooltip=message;
                app.setStatus(message);
                rethrow(ME)
            end
            app.LastExport=char(folder);
            app.Controls.ExportProgress.Text='100%  ·  Export complete';
            app.Controls.ExportProgress.Tooltip=app.LastExport;
            app.setStatus(['Export complete | ' app.LastExport]);
        end

        function exportProgress(app,fraction,message)
            if isempty(app.ExportUpdateClock)||toc(app.ExportUpdateClock)>=.08
                line=sprintf('%d%%  ·  %s',min(99,floor(100*fraction)),message);
                app.Controls.ExportProgress.Text=line;
                app.Controls.ExportProgress.Tooltip=message;
                app.setStatus(line);
                drawnow;
                app.ExportUpdateClock=tic;
            end
            if app.CancelRequested
                error('MergedLAOS:ExportCancelled','Export cancelled.');
            end
        end

        function manifest=writeResults(app,folder,options)
            if options.IncludeWaveforms||options.IncludeLissajous
                pending=find(arrayfun(@(e)isempty(e.Preview)&&isempty(e.PreviewError),app.Entries));
                app.loadPreviews(pending);
            end
            rows=1:numel(app.Entries);
            app.FT.refresh(rows,false);app.SD.refresh(rows,false);app.SPP.refresh(rows,false);
            app.refreshTable();app.refreshStrainChoices();
            manifest=SMS_LAOS_app_export_results(app.Entries,app.FT.Entries,app.SD.Entries,app.SPP.Entries, ...
                folder,options,@(p,msg)app.exportProgress(.05+.95*p,msg));
        end

        function manifest=writeLissajous(app,folder,options)
            candidate=1:numel(app.Entries);
            if isfield(options,'SelectedSourcePaths') && ~isempty(options.SelectedSourcePaths) && ...
                    (ischar(options.SelectedSourcePaths)||isstring(options.SelectedSourcePaths)||iscellstr(options.SelectedSourcePaths))
                candidate=find(ismember(string({app.Entries.Path}),string(options.SelectedSourcePaths)));
            end
            % Recheck checked inputs without opening unrelated files on disk.
            app.loadPreviews(candidate);
            rows=find(~cellfun(@isempty,{app.Entries.Preview}));
            useSD=(isfield(options,'IncludeElasticStrain')&&options.IncludeElasticStrain) || ...
                (isfield(options,'IncludeViscousRate')&&options.IncludeViscousRate);
            if useSD,app.SD.refresh(candidate,false);end
            previews={app.Entries(rows).Preview};
            sdResults=cell(size(previews));
            for j=1:numel(rows)
                k=rows(j);
                previews{j}.inputIndex=k;
                if useSD && app.Entries(k).StressDone && ismember(app.SD.Entries(k).Status,{'ok','warning'})
                    sdResults{j}=app.SD.Entries(k).Result;
                end
            end
            app.refreshTable(candidate);
            manifest=SMS_LAOS_app_export_lissajous(previews,folder,options,sdResults, ...
                @(p,msg)app.exportProgress(.05+.95*p,msg));
        end

        function buildUI(app)
            bg=[.95 .96 .98];ink=[.12 .18 .27];blue=[.12 .35 .69];
            app.Figure=uifigure('Name','SMS-LAOS','Visible','off','Position',[20 35 1540 970], ...
                'Color',bg,'CloseRequestFcn',@(~,~)app.closeRequested());
            outer=uigridlayout(app.Figure,[3 1]);outer.RowHeight={58,'1x',28};outer.Padding=[14 10 14 8];outer.BackgroundColor=bg;
            head=uigridlayout(outer,[1 2]);head.Padding=[0 0 0 0];head.ColumnWidth={'1x',105};head.BackgroundColor=bg;
            titles=uigridlayout(head,[2 1]);titles.Padding=[0 0 0 0];titles.RowHeight={32,20};titles.RowSpacing=0;titles.BackgroundColor=bg;
            uilabel(titles,'Text','SMS-LAOS','FontSize',25,'FontWeight','bold','FontColor',ink);
            uilabel(titles,'Text','Load and check inputs  /  Choose methods  /  Review results  /  Export','FontSize',12,'FontColor',[.4 .46 .55]);
            app.button(head,'User guide',@()app.showGuide());
            body=uigridlayout(outer,[1 2]);body.ColumnWidth={394,'1x'};body.Padding=[0 0 0 0];body.BackgroundColor=bg;
            left=uigridlayout(body,[16 1]);left.RowHeight={23,32,28,23,'1x',32,28,26,0,23,27,27,27,38,30,38};
            left.Padding=[10 8 10 8];left.RowSpacing=6;left.BackgroundColor=[1 1 1];
            uilabel(left,'Text','DATA FILES','FontWeight','bold','FontColor',ink);
            buttons=uigridlayout(left,[1 2]);buttons.Padding=[0 0 0 0];
            app.button(buttons,'Load data',@()app.chooseFiles());app.button(buttons,'Add folder',@()app.chooseFolder());
            app.button(left,'Load synthetic demo',@()app.loadDemo());
            app.Controls.SourceFolder=uilabel(left,'Text','Folder: —','FontSize',12,'FontWeight','bold','Interpreter','none');
            app.Controls.FileTable=uitable(left,'ColumnName',{'File','γ₀ %','State'}, ...
                'ColumnWidth',{166,52,138},'RowName',{},'Multiselect','on','SelectionType','row', ...
                'SelectionChangedFcn',@(~,event)app.tableSelected(event.Selection),'FontSize',11);
            app.Controls.FileTable.Tooltip='Select a review row to see the warnings for its checked methods.';
            addStyle(app.Controls.FileTable,uistyle('FontWeight','bold'),'column',3);
            progress=uigridlayout(left,[2 1]);progress.RowHeight={19,7};progress.RowSpacing=3;
            progress.Padding=[0 0 0 0];progress.BackgroundColor=[1 1 1];
            app.Controls.BatchSummary=uilabel(progress,'Text','Ready to analyze','FontWeight','bold','FontSize',12,'FontColor',ink);
            app.Controls.BatchSummary.Tooltip='Percentage of requested method calculations processed, including those that returned an error.';
            track=uipanel(progress,'BorderType','none','BackgroundColor',[.89 .91 .94],'AutoResizeChildren','off');
            app.Controls.BatchProgress=uipanel(track,'Units','normalized','Position',[0 0 0 1], ...
                'BorderType','none','BackgroundColor',blue);
            remove=uigridlayout(left,[1 2]);remove.Padding=[0 0 0 0];
            app.button(remove,'Remove selected',@()app.removeSelected());app.button(remove,'Clear list',@()app.clearFiles());
            app.Controls.SelectionStatus=uilabel(left,'Text','No file selected.','WordWrap','on','FontSize',11,'FontColor',[.35 .4 .48]);
            app.Controls.ReviewDetails=uitextarea(left,'Editable','off','Visible','off','FontSize',12, ...
                'Tooltip','Quality warnings for the selected file, grouped by method.');
            uilabel(left,'Text','ANALYSIS METHODS','FontWeight','bold','FontColor',ink);
            app.Controls.UseFT=uicheckbox(left,'Text','FT-LAOS','Value',true,'ValueChangedFcn',@(~,~)app.methodsChanged());
            app.Controls.UseStress=uicheckbox(left,'Text','Stress decomposition','Value',true,'ValueChangedFcn',@(~,~)app.methodsChanged());
            app.Controls.UseSPP=uicheckbox(left,'Text','SPP','Value',true,'ValueChangedFcn',@(~,~)app.methodsChanged());
            app.ActionControls=[app.ActionControls {app.Controls.UseFT,app.Controls.UseStress,app.Controls.UseSPP}];
            run=uigridlayout(left,[1 2]);run.Padding=[0 0 0 0];
            app.button(run,'Analyze selected',@()app.analyze('selected'),blue);app.button(run,'Analyze all',@()app.analyze('all'));
            app.Controls.Stop=uibutton(left,'Text','Stop','Enable','off','ButtonPushedFcn',@(~,~)app.requestCancel());
            app.button(left,'Open Export',@()app.showExport());
            app.Tabs=uitabgroup(body,'SelectionChangedFcn',@(~,~)app.tabChanged());
            app.Controls.InputTab=uitab(app.Tabs,'Title','Data & units');app.Controls.WaveformTab=app.Controls.InputTab;
            app.buildInput();
            app.Controls.FTTab=uitab(app.Tabs,'Title','FT-LAOS');
            ft=uigridlayout(app.Controls.FTTab,[1 2]);ft.ColumnWidth={310,'1x'};ft.Padding=[8 8 8 8];
            app.Controls.FTSettings=uipanel(ft,'BorderType','none','BackgroundColor',bg);
            fg=uigridlayout(ft,[4 1]);fg.RowHeight={42,'1x',220,76};fg.Padding=[6 0 0 0];
            app.Controls.FTInfo=uilabel(fg,'Text','Set FT-LAOS parameters on the left, then analyze.','WordWrap','on');
            fp=uigridlayout(fg,[1 2]);fp.Padding=[0 0 0 0];
            for n={'StrainSpectrum','StressSpectrum'},app.Axes.(n{1})=uiaxes(fp,'Box','on');end
            app.Controls.FTTable=uitable(fg,'ColumnName',{'Quantity','Value','Unit'},'ColumnWidth',{230,160,'auto'},'RowName',{});
            app.Controls.FTQuality=uitextarea(fg,'Editable','off','Value',{'Run FT-LAOS to inspect its quality diagnostics.'});
            app.Controls.StressTab=uitab(app.Tabs,'Title','Stress decomposition');
            app.Controls.SPPTab=uitab(app.Tabs,'Title','SPP');
            app.Controls.ExportTab=uitab(app.Tabs,'Title','Export');app.buildExport();
            app.Controls.Status=uilabel(outer,'Text','Ready | Load data, then confirm input units.','FontSize',11,'FontColor',[.35 .4 .47]);
        end

        function buildInput(app)
            g=uigridlayout(app.Controls.InputTab,[5 1]);g.RowHeight={124,26,42,'1x',65};g.Padding=[14 10 14 10];
            panel=uipanel(g,'Title','Input units and columns — applied to all methods');
            fields=uigridlayout(panel,[3 6]);fields.ColumnWidth={96,'1x',96,'1x',96,'1x'};
            fields.RowHeight={27,27,27};fields.Padding=[10 4 10 4];fields.RowSpacing=5;
            app.inputDrop(fields,1,1,'Time unit','TimeUnit',{'s','ms','µs','min','h'},{'s','ms','us','min','h'});
            app.inputDrop(fields,1,2,'Strain unit','StrainUnit',{'Percent (%)','Decimal','Millistrain','Microstrain'},{'percent','decimal','millistrain','microstrain'});
            app.inputDrop(fields,1,3,'Stress unit','StressUnit',{'Pa','kPa','MPa','mPa','bar','psi','dyn/cm²'},{'Pa','kPa','MPa','mPa','bar','psi','dyn/cm^2'});
            app.inputNumber(fields,2,1,'Time column','TimeColumn',[1 Inf]);
            app.inputNumber(fields,2,2,'Strain column','StrainColumn',[1 Inf]);
            app.inputNumber(fields,2,3,'Stress column','StressColumn',[1 Inf]);
            app.inputNumber(fields,3,1,'Header rows','HeaderLines',[0 Inf]);
            app.inputDrop(fields,3,2,'Delimiter','Delimiter',{'Automatic','Tab','Comma','Semicolon','Space'},{'auto','tab',',',';','space'});
            lab=uilabel(fields,'Text','Excel sheet');lab.Layout.Row=3;lab.Layout.Column=5;
            app.Controls.Sheet=uieditfield(fields,'text','Value','1','ValueChangedFcn',@(~,~)app.safe(@()app.inputChanged()));
            app.Controls.Sheet.Layout.Row=3;app.Controls.Sheet.Layout.Column=6;app.ActionControls{end+1}=app.Controls.Sheet;
            app.populateInputControls();
            app.Controls.UnitInfo=uilabel(g,'Text','Calculation units: seconds, decimal strain, Pa. Derived frequency: Hz / rad/s; strain rate: s⁻¹.','FontSize',11,'FontColor',[.35 .4 .48]);
            previewHeader=uigridlayout(g,[1 2]);previewHeader.ColumnWidth={'1x',110};previewHeader.Padding=[0 0 0 0];
            app.Controls.PreviewInfo=uilabel(previewHeader,'Text','Load data to view waveforms, strain rate and frequency.','WordWrap','on','FontSize',13,'FontWeight','bold');
            app.Controls.RetryPreview=uibutton(previewHeader,'Text','Retry preview','Visible','off', ...
                'ButtonPushedFcn',@(~,~)app.safe(@()app.retryPreview()));
            app.ActionControls{end+1}=app.Controls.RetryPreview;
            plots=uigridlayout(g,[2 2]);plots.Padding=[0 0 0 0];
            for n={'Strain','Stress','Rate','RawLissajous'}
                app.Axes.(n{1})=uiaxes(plots,'Box','on');app.Axes.(n{1}).XGrid='on';app.Axes.(n{1}).YGrid='on';
            end
            names={'Strain','Stress','Rate','RawLissajous'};
            titles={'Measured strain','Measured stress','Numerical strain rate','Loaded-data Lissajous'};
            xlabels={'Time (s)','Time (s)','Time (s)','Strain (%)'};
            ylabels={'Strain (%)','Stress (Pa)','Strain rate (s^{-1})','Stress (Pa)'};
            for k=1:numel(names)
                ax=app.Axes.(names{k});app.PreviewLines.(names{k})=line(ax,NaN,NaN,'Color',ax.ColorOrder(1,:));
                xlabel(ax,xlabels{k});ylabel(ax,ylabels{k});title(ax,titles{k});
            end
            app.Controls.PreviewNotes=uitextarea(g,'Editable','off','Value',{'Input unit selection converts the data for every method. Original files remain unchanged.'});
        end

        function buildExport(app)
            root=uigridlayout(app.Controls.ExportTab,[3 1]);
            root.RowHeight={38,26,'1x'};root.Padding=[16 14 16 10];root.RowSpacing=6;
            toolbar=uigridlayout(root,[1 3]);toolbar.ColumnWidth={98,'1x',125};toolbar.Padding=[0 0 0 0];
            uilabel(toolbar,'Text','Export content','FontWeight','bold');
            app.Controls.ExportScope=uidropdown(toolbar, ...
                'Items',{'Analysis results','Lissajous plots','Results and plots','Workspace snapshot'}, ...
                'ItemsData',{'results','plots','both','snapshot'},'Value','results','UserData',false, ...
                'ValueChangedFcn',@(~,~)app.showExportScope());
            app.Controls.ExportAction=uibutton(toolbar,'Text','Export…','BackgroundColor',[.12 .35 .69], ...
                'FontColor',[1 1 1],'FontWeight','bold','ButtonPushedFcn',@(~,~)app.safe(@()app.runExportSelection()));
            status=uigridlayout(root,[1 2]);status.ColumnWidth={'1x',125};status.Padding=[0 0 0 0];
            app.Controls.ExportProgress=uilabel(status,'Text','','FontColor',[.23 .30 .40]);
            app.Controls.CancelExport=uibutton(status,'Text','Cancel export','Enable','off','Visible','off', ...
                'ButtonPushedFcn',@(~,~)app.cancelExport());

            body=uigridlayout(root,[4 1]);body.Padding=[0 0 4 0];body.RowSpacing=4;body.Scrollable='on';
            analysis=uipanel(body,'Title','Analysis results','FontWeight','bold');analysis.Layout.Row=1;
            rg=uigridlayout(analysis,[2 2]);rg.ColumnWidth={125,'1x'};rg.RowHeight={30,26};
            rg.Padding=[12 6 12 8];rg.RowSpacing=6;
            uilabel(rg,'Text','Results package');
            app.Controls.ExportMode=uidropdown(rg,'Items',{'Fast — data only','Full — include native SD figures and Excel files'}, ...
                'ItemsData',{'fast','full'},'Value','fast','Tooltip','Applies to the Stress decomposition package.');
            uilabel(rg,'Text','Additional data');
            extras=uigridlayout(rg,[1 2]);extras.Padding=[0 0 0 0];
            app.Controls.ExportCurves=uicheckbox(extras,'Text','Decomposed curve CSV','Value',true);
            app.Controls.ExportWaveforms=uicheckbox(extras,'Text','Waveform and strain-rate CSV','Value',true);
            % Preserve the public exportResults option for script callers.
            app.Controls.ExportLissajous=uicheckbox(rg,'Text','Include Lissajous plots','Visible','off');
            app.Controls.ExportLissajous.Layout.Row=1;app.Controls.ExportLissajous.Layout.Column=1;

            panel=uipanel(body,'Title','Lissajous plots','FontWeight','bold');panel.Layout.Row=2;
            g=uigridlayout(panel,[8 2]);g.ColumnWidth={125,'1x'};g.Padding=[12 8 12 10];g.RowSpacing=6;
            g.RowHeight={30,82,54,30,0,30,30,28};
            uilabel(g,'Text','Strains to export');
            app.Controls.StrainMatchMode=uidropdown(g,'Items',{'Check measured strains','Target amplitude and tolerance'}, ...
                'ItemsData',{'checked','target'},'Value','target','ValueChangedFcn',@(~,~)app.showStrainMatchMode());
            picker=uigridlayout(g,[1 1]);picker.Layout.Row=2;picker.Layout.Column=[1 2];picker.Padding=[0 0 0 0];
            target=uigridlayout(picker,[2 4]);target.Layout.Row=1;target.Layout.Column=1;
            target.ColumnWidth={125,'1x',150,'1x'};target.RowHeight={28,26};target.Padding=[0 2 0 2];target.RowSpacing=6;
            uilabel(target,'Text','Target strain (%)');app.Controls.TargetStrain=uieditfield(target,'numeric','Value',1,'Limits',[eps Inf]);
            uilabel(target,'Text','Tolerance (% points)');app.Controls.StrainTolerance=uieditfield(target,'numeric','Value',.1,'Limits',[0 Inf]);
            app.button(target,'Use selected amplitude',@()app.useSelectedAmplitude());
            app.Controls.MatchInfo=uilabel(target,'Text','','WordWrap','on');
            app.Controls.MatchInfo.Layout.Row=2;app.Controls.MatchInfo.Layout.Column=[2 4];
            app.Controls.StrainChoices=uitable(picker,'Data',cell(0,3),'ColumnName',{'Export','Measured strain (%)','File'}, ...
                'ColumnEditable',[true false false],'ColumnFormat',{'logical','char','char'},'ColumnWidth',{66,154,'auto'}, ...
                'RowName',{},'UserData',cell(0,1),'Visible','off','Tooltip','Tick each file to export.');
            app.Controls.StrainChoices.Layout.Row=1;app.Controls.StrainChoices.Layout.Column=1;

            uilabel(g,'Text','Plot types');
            plots=uigridlayout(g,[2 2]);plots.Padding=[0 0 0 0];plots.RowHeight={24,24};plots.RowSpacing=4;
            app.Controls.IncludeStressStrain=uicheckbox(plots,'Text','Total stress vs strain','Value',true);
            app.Controls.IncludeStressRate=uicheckbox(plots,'Text','Total stress vs strain rate','Value',true);
            app.Controls.IncludeElasticStrain=uicheckbox(plots,'Text','Elastic stress vs strain','Value',false, ...
                'Tooltip','Run Stress decomposition for the selected files first.');
            app.Controls.IncludeViscousRate=uicheckbox(plots,'Text','Viscous stress vs strain rate','Value',false, ...
                'Tooltip','Run Stress decomposition for the selected files first.');
            uilabel(g,'Text','Axis scale');
            app.Controls.AxisScale=uidropdown(g,'Items',{'Physical units','Normalised','Physical and normalised'}, ...
                'ItemsData',{'dimensional','normalised','both'},'Value','dimensional','ValueChangedFcn',@(~,~)app.showStrainMatchMode());
            app.Controls.ScaleHint=uilabel(g,'Text',['Peaks are calculated per file over the plotted window. All stresses use the peak absolute total stress.'], ...
                'WordWrap','on','Visible','off','FontSize',11,'FontColor',[.35 .4 .48]);
            app.Controls.ScaleHint.Layout.Row=5;app.Controls.ScaleHint.Layout.Column=2;
            layoutLabel=uilabel(g,'Text','Figure layout');layoutLabel.Layout.Row=6;layoutLabel.Layout.Column=1;
            app.Controls.LissajousMode=uidropdown(g,'Items',{'Separate figures per file','Overlay matched files'}, ...
                'ItemsData',{'per_file','overlay'});app.Controls.LissajousMode.Layout.Row=6;app.Controls.LissajousMode.Layout.Column=2;
            uilabel(g,'Text','Time window');
            times=uigridlayout(g,[1 3]);times.ColumnWidth={'1x',42,66};times.Padding=[0 0 0 0];
            app.Controls.CycleMode=uidropdown(times,'Items',{'Last N estimated cycles','Entire available window'}, ...
                'ItemsData',{'last_n','all'},'ValueChangedFcn',@(~,~)app.showExportWindow());
            app.Controls.CycleCountLabel=uilabel(times,'Text','Cycles');
            app.Controls.LastNCycles=uieditfield(times,'numeric','Value',3,'Limits',[1 Inf],'RoundFractionalValues','on');
            uilabel(g,'Text','Figure formats');
            formats=uigridlayout(g,[1 3]);formats.ColumnWidth={65,65,'1x'};formats.Padding=[0 0 0 0];
            app.Controls.PNG=uicheckbox(formats,'Text','PNG','Value',true);
            app.Controls.PDF=uicheckbox(formats,'Text','PDF','Value',false,'Tooltip','Vector PDF');
            app.Controls.FIG=uicheckbox(formats,'Text','MATLAB FIG','Value',false,'Tooltip','Editable MATLAB figure');

            snapshot=uipanel(body,'Title','Workspace snapshot','FontWeight','bold');snapshot.Layout.Row=3;
            sg=uigridlayout(snapshot,[1 2]);sg.ColumnWidth={125,'1x'};sg.Padding=[12 8 12 8];
            uilabel(sg,'Text','Page to save');
            app.Controls.ViewPage=uidropdown(sg,'Items',{'Data & units','FT-LAOS','Stress decomposition','SPP','Export'}, ...
                'ItemsData',{'InputTab','FTTab','StressTab','SPPTab','ExportTab'},'Value','InputTab');
            app.Controls.ResultSettings=analysis;app.Controls.PlotSettings=panel;app.Controls.SnapshotSettings=snapshot;
            for n={'ExportScope','ExportAction','ExportMode','ExportCurves','ExportWaveforms','ExportLissajous','StrainMatchMode','StrainChoices', ...
                    'TargetStrain','StrainTolerance','IncludeStressStrain','IncludeStressRate','IncludeElasticStrain', ...
                    'IncludeViscousRate','AxisScale','LissajousMode','CycleMode','LastNCycles','PNG','PDF','FIG','ViewPage'}
                app.ActionControls{end+1}=app.Controls.(n{1});
            end
            app.showExportScope();
        end

        function showExportScope(app)
            c=app.Controls;scope=c.ExportScope.Value;
            showResults=ismember(scope,{'results','both'});showPlots=ismember(scope,{'plots','both'});
            c.ResultSettings.Visible=showResults;c.PlotSettings.Visible=showPlots;c.SnapshotSettings.Visible=strcmp(scope,'snapshot');
            c.ExportLissajous.Value=strcmp(scope,'both');
            if showPlots && ~c.ExportScope.UserData
                % The interactive picker starts with explicit files. Direct calls to
                % exportLissajous retain the original target-and-tolerance defaults.
                c.StrainMatchMode.Value='checked';c.ExportScope.UserData=true;
            end
            if strcmp(scope,'snapshot'),c.ExportAction.Text='Save PNG…';else,c.ExportAction.Text='Export…';end
            app.showStrainMatchMode();
        end

        function runExportSelection(app)
            scope=app.Controls.ExportScope.Value;
            if strcmp(scope,'snapshot')
                app.chooseView();
            else
                app.Controls.ExportLissajous.Value=strcmp(scope,'both');
                app.chooseExport(strcmp(scope,'plots'));
            end
        end

        function showExportWindow(app)
            c=app.Controls;showCount=strcmp(c.CycleMode.Value,'last_n');
            c.CycleCountLabel.Visible=showCount;c.LastNCycles.Visible=showCount;
        end

        function showStrainMatchMode(app)
            c=app.Controls;useList=strcmp(c.StrainMatchMode.Value,'checked');
            c.TargetStrain.Parent.Visible=~useList;c.StrainChoices.Visible=useList;
            showScale=~strcmp(c.AxisScale.Value,'dimensional');c.ScaleHint.Visible=showScale;
            g=c.AxisScale.Parent;heights=g.RowHeight;
            if useList,heights{2}=157;else,heights{2}=65;end
            heights{5}=30*showScale;g.RowHeight=heights;
            plotHeight=sum([heights{:}])+7*g.RowSpacing+g.Padding(2)+g.Padding(4)+26;
            body=c.PlotSettings.Parent;
            body.RowHeight={110*strcmp(c.ResultSettings.Visible,'on'),plotHeight*strcmp(c.PlotSettings.Visible,'on'), ...
                76*strcmp(c.SnapshotSettings.Visible,'on'),'1x'};
        end

        function refreshStrainChoices(app)
            choices=app.Controls.StrainChoices;
            % Store checked file identities across sorting, additions and removals.
            checkedPaths=choices.UserData(cell2mat(choices.Data(:,1)));
            ready=find(~cellfun(@isempty,{app.Entries.Preview}));
            levels=arrayfun(@(i)app.Entries(i).Preview.strainAmplitudePercent,ready);
            [levels,order]=sort(levels(:));
            entries=app.Entries(ready(order));
            paths=reshape({entries.Path},[],1);
            names=reshape({entries.Name},[],1);
            if numel(unique(names))<numel(names)
                [~,~,group]=unique(names);
                counts=accumarray(group,1);
                duplicates=counts(group)>1;
                names(duplicates)=paths(duplicates);
            end
            rows=[num2cell(ismember(paths,checkedPaths)),cellstr(compose('%.9g',levels)),names];
            choices.UserData=paths;
            if ~isequal(choices.Data,rows),choices.Data=rows;end
        end

        function inputDrop(app,g,row,pair,label,name,items,data)
            lab=uilabel(g,'Text',label);lab.Layout.Row=row;lab.Layout.Column=2*pair-1;
            c=uidropdown(g,'Items',items,'ItemsData',data,'ValueChangedFcn',@(~,~)app.safe(@()app.inputChanged()));
            c.Layout.Row=row;c.Layout.Column=2*pair;app.Controls.(name)=c;app.ActionControls{end+1}=c;
        end
        function inputNumber(app,g,row,pair,label,name,limits)
            lab=uilabel(g,'Text',label);lab.Layout.Row=row;lab.Layout.Column=2*pair-1;
            c=uieditfield(g,'numeric','Limits',limits,'Value',max(1,limits(1)),'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.safe(@()app.inputChanged()));
            c.Layout.Row=row;c.Layout.Column=2*pair;app.Controls.(name)=c;app.ActionControls{end+1}=c;
        end
        function populateInputControls(app)
            s=app.InputSettings;
            for name={'TimeUnit','StrainUnit','StressUnit','TimeColumn','StrainColumn','StressColumn','HeaderLines'}
                app.Controls.(name{1}).Value=s.(name{1});
            end
            d=s.Delimiter;if isempty(d),d='auto';elseif strcmp(d,sprintf('\t')),d='tab';elseif strcmp(d,' '),d='space';end
            if ~ismember(d,app.Controls.Delimiter.ItemsData)
                app.Controls.Delimiter.Items=[app.Controls.Delimiter.Items {d}];
                app.Controls.Delimiter.ItemsData=[app.Controls.Delimiter.ItemsData {d}];
            end
            app.Controls.Delimiter.Value=d;app.Controls.Sheet.Value=char(string(s.Sheet));
        end
        function inputChanged(app)
            if app.Updating,return;end
            s=struct();
            for name={'TimeUnit','StrainUnit','StressUnit','TimeColumn','StrainColumn','StressColumn','HeaderLines','Delimiter','Sheet'}
                s.(name{1})=app.Controls.(name{1}).Value;
            end
            n=str2double(s.Sheet);if isfinite(n)&&n>=1&&n==fix(n),s.Sheet=n;end
            try,app.setInputSettings(s);catch ME,app.populateInputControls();rethrow(ME);end
        end

        function button(app,parent,text,callback,color)
            b=uibutton(parent,'Text',text,'ButtonPushedFcn',@(~,~)app.safe(callback));
            if nargin>4,b.BackgroundColor=color;b.FontColor=[1 1 1];end
            app.ActionControls{end+1}=b;
        end
        function loadPreviews(app,indices)
            if isempty(indices),return;end
            selected=app.SelectedIndices(1);
            if any(indices==selected)
                indices=[selected indices(indices~=selected)];
            end
            lastUpdate=tic;
            for k=1:numel(indices)
                i=indices(k);
                if app.Exporting
                    app.exportProgress(.05*(k-1)/numel(indices),sprintf('Checking waveform %d / %d · %s',k,numel(indices),app.Entries(i).Name));
                elseif k<=2||toc(lastUpdate)>.12
                    app.setStatus(sprintf('Preparing waveforms %d / %d | %s',k,numel(indices),app.Entries(i).Name));
                    drawnow;lastUpdate=tic;
                end
                if app.CancelRequested,return;end
                app.loadPreview(i);
                if ~app.Exporting&&i==selected&&isequal(app.Tabs.SelectedTab,app.Controls.InputTab)
                    app.renderPreview();app.refreshTable(i);
                end
            end
        end
        function loadPreview(app,i)
            e=app.Entries(i);
            if ~isempty(e.Preview)&&SMS_LAOS_app_source_current(e.Preview.source),return;end
            try
                app.Entries(i).Preview=SMS_LAOS_app_preview(e.Path,app.InputSettings);
                app.Entries(i).PreviewError='';
            catch ME
                app.Entries(i).Preview=[];app.Entries(i).PreviewError=ME.message;
            end
        end
        function reportPreviews(app)
            ready=nnz(~cellfun(@isempty,{app.Entries.Preview}));
            failed=nnz(~cellfun(@isempty,{app.Entries.PreviewError}));
            pending=numel(app.Entries)-ready-failed;
            label='Waveforms';if app.CancelRequested,label='Load stopped';end
            app.setStatus(sprintf('%s | %d ready, %d input errors, %d pending.',label,ready,failed,pending));
        end
        function moduleChanged(app)
            if app.Updating||app.Busy,return;end
            app.resetBatchProgress();
            app.refresh();
        end
        function methodsChanged(app)
            app.resetBatchProgress();
            % The row state depends on every checked method, even off selection.
            app.refreshTable();app.refresh(app.SelectedIndices);
        end
        function resetBatchProgress(app)
            app.Controls.BatchProgress.Position(3)=0;
            app.Controls.BatchSummary.Text='Ready to analyze';
        end
        function showBatchProgress(app,label,steps,files,stepsPerFile)
            total=files*stepsPerFile;
            app.Controls.BatchProgress.Position(3)=steps/total;
            app.Controls.BatchSummary.Text=sprintf('%s · %d/%d files · %d%%', ...
                label,floor(steps/stepsPerFile),files,floor(100*steps/total));
        end
        function finishBatchDisplay(app,label,ids,steps,stepsPerFile)
            app.BatchRowStates={};
            app.refresh(unique([ids app.SelectedIndices]));
            app.showBatchProgress(label,steps,numel(ids),stepsPerFile);
            % Count only files fully processed by this run (earlier cached
            % results can still exist on rows untouched after Stop).
            completed=ids(1:floor(steps/stepsPerFile));
            states=app.Controls.FileTable.Data(completed,3);
            review=nnz(startsWith(states,'Review ('));errors=nnz(ismember(states,{'Error','Input error'}));
            summary=app.Controls.BatchSummary.Text;
            if review,summary=sprintf('%s · %d review',summary,review);end
            if errors,summary=sprintf('%s · %d error(s)',summary,errors);end
            app.Controls.BatchSummary.Text=summary;
            if ~isempty(app.SelectedIndices)&&strcmp(app.Figure.Visible,'on')
                scroll(app.Controls.FileTable,'row',app.SelectedIndices(1));
            end
        end
        function finishUpdate(app),if isvalid(app),app.Updating=false;end,end
        function syncFileLists(app)
            app.resetBatchProgress();
            paths={app.Entries.Path};
            app.FT.replaceFiles(paths,true);app.SD.replaceFiles(paths,true);app.SPP.replaceFiles(paths,true);
            app.syncSelection();
        end
        function syncSelection(app)
            app.showSourceFolder();
            if isempty(app.SelectedIndices),return;end
            app.FT.selectFile(app.SelectedIndices(1),false);app.SD.selectFile(app.SelectedIndices(1),false);
            app.SPP.selectFiles(app.SelectedIndices,false);
        end
        function showSourceFolder(app)
            label=app.Controls.SourceFolder;
            if isempty(app.SelectedIndices)
                label.Text='Folder: —';label.Tooltip='';return
            end
            folders=unique(string(cellfun(@fileparts,{app.Entries.Path},'UniformOutput',false)),'stable');
            selected=fileparts(app.Entries(app.SelectedIndices(1)).Path);
            [~,name,ext]=fileparts(selected);
            name=[name ext];
            if isempty(name),name=selected;end
            suffix='';
            if numel(folders)>1,suffix=sprintf(' (+%d)',numel(folders)-1);end
            label.Text=['Folder: ' name suffix];
            label.Tooltip=char(join([string(selected),folders(folders~=string(selected))],newline));
        end
        function refreshTable(app,indices)
            n=numel(app.Entries);table=app.Controls.FileTable;
            rows=table.Data;sizeChanged=~isequal(size(rows),[n 3]);
            if sizeChanged,rows=cell(n,3);end
            if nargin<2||sizeChanged,indices=1:n;end
            checked=[app.Controls.UseFT.Value app.Controls.UseStress.Value app.Controls.UseSPP.Value];
            names={'FT','SD','SPP'};
            checkedNames=names(checked);
            colors=table.BackgroundColor;colorChanged=size(colors,1)~=max(n,1);
            if colorChanged,colors=ones(max(n,1),3);indices=1:n;end
            changed=sizeChanged;
            for k=indices
                e=app.Entries(k);amp='—';
                if ~isempty(e.Preview),amp=sprintf('%.5g',e.Preview.strainAmplitudePercent);end
                states={app.FT.Entries(k).Status,app.SD.Entries(k).Status,app.SPP.Entries(k).Status};
                states=states(checked);
                if ~isempty(app.BatchRowStates)&&~isempty(app.BatchRowStates{k}),state=app.BatchRowStates{k};
                elseif ~isempty(e.PreviewError),state='Input error';
                elseif any(strcmp(states,'error')),state='Error';
                elseif any(strcmp(states,'stale')),state='Stale';
                elseif ~isempty(states)&&all(ismember(states,{'ok','warning'}))
                    if any(strcmp(states,'warning')),state='Review';else,state='Finished';end
                elseif any(ismember(states,{'ok','warning'})),state='Partial';
                elseif isempty(e.Preview),state='Queued';
                else,state='Pending';end
                switch state
                    case 'Finished',color=[.91 .97 .93];
                    case 'Review'
                        color=[1 .94 .80];
                        state=['Review (' strjoin(checkedNames(strcmp(states,'warning')),', ') ')'];
                    case {'Error','Input error'},color=[1 .89 .88];
                    case {'Running: FT','Running: SD','Running: SPP'},color=[.82 .91 1];
                    otherwise,color=[1 1 1];
                end
                if ~isequal(colors(k,:),color),colors(k,:)=color;colorChanged=true;end
                row={e.Name,amp,state};
                if ~isequal(rows(k,:),row),rows(k,:)=row;changed=true;end
            end
            if changed,table.Data=rows;end
            if colorChanged,table.BackgroundColor=colors;end
            if ~isequal(table.Selection(:),app.SelectedIndices(:)),table.Selection=app.SelectedIndices;end
            app.refreshSelectionDetails(checked,names);
        end
        function refreshSelectionDetails(app,checked,names)
            messages=strings(0,1);
            if isempty(app.SelectedIndices)
                app.Controls.SelectionStatus.Text='No file selected.';
                app.Controls.SelectionStatus.Tooltip='';
            else
                i=app.SelectedIndices(1);
                modules={app.FT,app.SD,app.SPP};
                status={'Off','Off','Off'};
                for j=find(checked)
                    entry=modules{j}.Entries(i);
                    status{j}=app.shortStatus(entry.Status);
                    if strcmp(entry.Status,'warning') && (isempty(app.BatchRowStates) || isempty(app.BatchRowStates{i}))
                        reasons=string(entry.Result.quality.messages);
                        messages=[messages; string(names{j}) + ": " + reasons(:)]; %#ok<AGROW>
                    end
                end
                app.Controls.SelectionStatus.Text=sprintf('FT: %s  |  SD: %s  |  SPP: %s',status{:});
                app.Controls.SelectionStatus.Tooltip=app.Entries(i).Path;
            end
            details=app.Controls.ReviewDetails;
            hasWarnings=~isempty(messages);
            if hasWarnings && ~isequal(string(details.Value(:)),messages)
                details.Value=cellstr(messages);
            elseif ~hasWarnings && any(strlength(string(details.Value))>0)
                details.Value={''};
            end
            if hasWarnings~=strcmp(details.Visible,'on')
                details.Parent.RowHeight{details.Layout.Row}=96*double(hasWarnings);
                details.Visible=hasWarnings;
            end
        end
        function renderPreview(app)
            app.Controls.RetryPreview.Visible='off';
            if isempty(app.SelectedIndices)||isempty(app.Entries(app.SelectedIndices(1)).Preview)
                for n=fieldnames(app.PreviewLines)',set(app.PreviewLines.(n{1}),'XData',[],'YData',[]);end
                app.Controls.PreviewNotes.Value={'Load data to inspect the measured input.'};
                if isempty(app.SelectedIndices)
                    app.Controls.PreviewInfo.Text='Load data to view waveforms, strain rate and frequency.';
                else
                    e=app.Entries(app.SelectedIndices(1));
                    if isempty(e.PreviewError)
                        app.Controls.PreviewInfo.Text=[e.Name ' | Waveform preview pending.'];
                    else
                        lines=cellstr(splitlines(string(e.PreviewError)));
                        summary=lines{1};
                        if numel(summary)>120,summary='Could not load the waveform. See the details below.';end
                        app.Controls.PreviewInfo.Text=[e.Name ' | ' summary];
                        app.Controls.PreviewNotes.Value=[lines(:);{e.Path}];
                        app.Controls.RetryPreview.Visible='on';
                    end
                end
                return;
            end
            e=app.Entries(app.SelectedIndices(1));P=e.Preview;
            current=SMS_LAOS_app_source_current(P.source);prefix='';if ~current,prefix='SOURCE CHANGED — reload / analyze before export. ';end
            app.Controls.PreviewInfo.Text=sprintf('%s%s | γ₀ ≈ %.5g %% | f ≈ %.6g Hz | ω ≈ %.6g rad/s',prefix,e.Name,P.strainAmplitudePercent,P.frequencyHz,P.omega);
            strainPercent=100*P.strain;
            set(app.PreviewLines.Strain,'XData',P.time,'YData',strainPercent);
            set(app.PreviewLines.Stress,'XData',P.time,'YData',P.stress);
            set(app.PreviewLines.Rate,'XData',P.time,'YData',P.strainRate);
            set(app.PreviewLines.RawLissajous,'XData',strainPercent,'YData',P.stress);
            notes={'Preview uses measured strain and original timestamps. Analysis methods retain their own frequency, derivative and cycle-selection rules.'};
            if isfield(P,'quality')&&isfield(P.quality,'messages'),notes=[notes reshape(cellstr(string(P.quality.messages)),1,[])];end
            app.Controls.PreviewNotes.Value=notes;
        end
        function renderFT(app)
            for n={'StrainSpectrum','StressSpectrum'},cla(app.Axes.(n{1}));end
            app.Controls.FTTable.Data={};
            app.Controls.FTQuality.Value={'Run FT-LAOS to inspect its quality diagnostics.'};
            app.Controls.FTInfo.Text='Set FT-LAOS parameters on the left, then analyze.';
            if isempty(app.SelectedIndices),return;end
            i=app.SelectedIndices(1);e=app.FT.Entries(i);
            if ~app.Controls.UseFT.Value||~app.Entries(i).FTDone||~ismember(e.Status,{'ok','warning'})
                app.Controls.FTInfo.Text='Select FT-LAOS and analyze this file. Current FT results only are displayed here.';return;
            end
            R=e.Result;app.Controls.FTInfo.Text=sprintf('%s | f = %.6g Hz | I3/I1 = %.5g | harmonics 1 and 3 (original v2 convention)',e.Name,R.freq_hz,R.I3_I1);
            plot(app.Axes.StrainSpectrum,R.freqs_plot,R.strain_amp_plot);xlim(app.Axes.StrainSpectrum,[0 max(5*R.freq_hz,5)]);xlabel(app.Axes.StrainSpectrum,'Frequency (Hz)');ylabel(app.Axes.StrainSpectrum,'Strain amplitude');title(app.Axes.StrainSpectrum,'Strain FFT');
            plot(app.Axes.StressSpectrum,R.freqs_plot,R.stress_amp_plot);xlim(app.Axes.StressSpectrum,[0 max(5*R.freq_hz,5)]);xlabel(app.Axes.StressSpectrum,'Frequency (Hz)');ylabel(app.Axes.StressSpectrum,'Stress amplitude (Pa)');title(app.Axes.StressSpectrum,'Stress FFT');
            app.Controls.FTTable.Data={'Frequency',R.freq_hz,'Hz';'Angular frequency',R.omega,'rad/s';'Selected cycles',R.n_cycles_used,'count';'I1',R.I1,'Pa';'I3',R.I3,'Pa';'I3 / I1',R.I3_I1,'ratio';'δ1',R.delta1,'rad';'δ3',R.delta3,'rad';'G′1',R.Gp1,'Pa';'G″1',R.Gpp1,'Pa';'G′3',R.Gp3,'Pa';'G″3',R.Gpp3,'Pa'};
            if R.quality.has_warnings,app.Controls.FTQuality.Value=R.quality.messages;
            else,app.Controls.FTQuality.Value={'No automatic quality flags. Inspect waveform, frequency selection and model limits before interpretation.'};end
        end
        function renderStressAvailability(app)
            available=false;
            if ~isempty(app.SelectedIndices)
                i=app.SelectedIndices(1);
                available=app.Controls.UseStress.Value&&app.Entries(i).StressDone&&ismember(app.SD.Entries(i).Status,{'ok','warning'});
            end
            app.SD.Tabs.Visible=available;
            app.SD.Controls.Banner.Visible=app.Controls.UseStress.Value;
        end
        function o=lissajousOptions(app,requireSelection)
            if nargin<2,requireSelection=true;end
            c=app.Controls;o=struct('TargetStrainPercent',c.TargetStrain.Value,'TolerancePercent',c.StrainTolerance.Value, ...
                'Mode',c.LissajousMode.Value,'AxisScale',c.AxisScale.Value,'CycleMode',c.CycleMode.Value,'LastNCycles',c.LastNCycles.Value, ...
                'IncludeStressStrain',c.IncludeStressStrain.Value,'IncludeStressRate',c.IncludeStressRate.Value, ...
                'IncludeElasticStrain',c.IncludeElasticStrain.Value,'IncludeViscousRate',c.IncludeViscousRate.Value, ...
                'FormatPNG',c.PNG.Value,'FormatPDF',c.PDF.Value,'FormatFIG',c.FIG.Value);
            if strcmp(c.StrainMatchMode.Value,'checked')
                choices=c.StrainChoices;
                o.SelectedSourcePaths=choices.UserData(cell2mat(choices.Data(:,1)));
                if requireSelection && isempty(o.SelectedSourcePaths)
                    error('MergedLAOS:LissajousSelection','Check at least one file under Strains to export.');
                end
            end
        end
        function useSelectedAmplitude(app)
            if isempty(app.SelectedIndices),error('MergedLAOS:Selection','Select a loaded file first.');end
            P=app.Entries(app.SelectedIndices(1)).Preview;
            if isempty(P),error('MergedLAOS:Preview','The selected file has no valid preview.');end
            app.Controls.TargetStrain.Value=P.strainAmplitudePercent;
            app.Controls.MatchInfo.Text=sprintf('Selected measured amplitude: %.6g %%',P.strainAmplitudePercent);
        end
        function tableSelected(app,indices)
            if app.Updating||isequal(indices(:),app.SelectedIndices(:)),return;end
            if app.Busy
                % Keep the list readable and scrollable while protecting the
                % original selection and the waveform it controls.
                app.Controls.FileTable.Selection=app.SelectedIndices;return;
            end
            if isempty(indices),return;end
            app.safe(@()app.selectFiles(indices));
        end
        function tabChanged(app)
            if app.Busy,app.TabChangedWhileBusy=true;return;end
            if ~app.Updating,app.refresh(app.SelectedIndices);end
        end
        function s=shortStatus(~,s)
            switch s
                case 'ok',s='OK';
                case 'warning',s='Warn';
                case 'error',s='Error';
                case 'stale',s='Stale';
                otherwise,s='—';
            end
        end
        function chooseFiles(app)
            [f,p]=uigetfile({'*.dat;*.csv;*.txt;*.tsv;*.xls;*.xlsx','Rheology data'},'Load data','MultiSelect','on');
            if isequal(f,0),return;end
            if ischar(f),f={f};end
            app.addFiles(cellfun(@(n)fullfile(p,n),f,'UniformOutput',false));
        end
        function chooseFolder(app)
            p=uigetdir(pwd,'Add a folder of data');if isequal(p,0),return;end;app.addFolder(p);
        end
        function loadDemo(app)
            s=SMS_LAOS_app_input_defaults();s.StrainUnit='decimal';app.setInputSettings(s);
            app.addFiles(fullfile(app.Root,'modules','ft','examples','SMS-LAOS app synthetic demo.dat'));
        end
        function showExport(app),app.Tabs.SelectedTab=app.Controls.ExportTab;end
        function chooseView(app)
            [f,p]=uiputfile('*.png','Save current workspace view','LAOS_view.png');
            if isequal(f,0),return;end
            app.saveView(fullfile(p,f),app.Controls.ViewPage.Value);app.setStatus(['View saved: ' fullfile(p,f)]);
        end
        function restoreView(app,tab)
            if isvalid(app)&&isvalid(app.Figure)&&isvalid(tab)&&~isequal(tab,app.Tabs.SelectedTab)
                app.Tabs.SelectedTab=tab;app.refresh(app.SelectedIndices);
            end
        end
        function showGuide(app)
            message=sprintf(['1. Choose Load data, Add folder or Load synthetic demo. On Data & units, confirm the time, strain and stress columns and units. Inspect the waveforms, strain rate and frequency.\n\n' ...
                '2. Check the methods you need and adjust their settings on the matching tabs. Choose Analyze selected or Analyze all.\n\n' ...
                '3. Watch the file list for progress. A Review row names each method with a quality warning. Click that row to read the reasons for that file.\n\n' ...
                '4. On Export, choose Analysis results, Lissajous plots, or Results and plots. For figures, tick the files, choose the plots and axis scale, then click Export. Normalised axes use peaks from each file’s plotted window. Run Stress decomposition first for elastic or viscous stress.']);
            uialert(app.Figure,message,'SMS-LAOS — User guide','Icon','info','Interpreter','none');
        end
        function chooseExport(app,onlyLissajous)
            app.showExport();p=uigetdir(pwd,'Select parent folder (a new output folder will be created)');
            if isequal(p,0),return;end
            tag='LAOS_results_';if onlyLissajous,tag='LAOS_Lissajous_';end
            folder=fullfile(p,[tag char(datetime('now','TimeZone','Europe/London','Format','yyyyMMdd_HHmmss_SSS'))]);
            if onlyLissajous,app.exportLissajous(folder);else,app.exportResults(folder);end
        end
        function lock(app,on)
            state='on';if on,state='off';end
            for k=1:numel(app.ActionControls),app.ActionControls{k}.Enable=state;end
            app.FT.setLocked(on);app.SD.setLocked(on);app.SPP.setLocked(on);app.Controls.Stop.Enable=on&&~app.Exporting;
            app.Controls.CancelExport.Enable=on&&app.Exporting;
            app.Controls.CancelExport.Visible=on&&app.Exporting;
        end
        function finish=startRun(app,exporting)
            app.Busy=true;app.CancelRequested=false;app.Exporting=exporting;
            finish=onCleanup(@()app.finishRun());
            app.lock(true);
        end
        function finishRun(app)
            if ~isvalid(app),return;end
            app.Busy=false;app.Exporting=false;app.lock(false);
            if app.CloseAfterRun,delete(app);
            elseif app.TabChangedWhileBusy,app.refresh(app.SelectedIndices);end
        end
        function requireIdle(app)
            if app.Busy,error('MergedLAOS:Busy','An operation is running. Wait for completion or stop analysis.');end
        end
        function setStatus(app,s),app.Controls.Status.Text=s;app.Controls.Status.Tooltip=s;end
        function safe(app,f)
            try,f();catch ME
                if isvalid(app)&&isvalid(app.Figure)&&~strcmp(ME.identifier,'MergedLAOS:ExportCancelled')
                    app.setStatus(ME.message);uialert(app.Figure,ME.message,'LAOS analysis','Interpreter','none');
                end
            end
        end
        function closeRequested(app)
            if app.Busy
                app.CloseAfterRun=true;if app.Exporting,app.cancelExport();else,app.requestCancel();end
                app.setStatus('The window will close when the current operation finishes.');
            else,delete(app);end
        end
    end
end
