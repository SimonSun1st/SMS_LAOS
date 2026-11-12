function R=merged_laos_analyze_spp(path,options,inputSettings)
%MERGED_LAOS_ANALYZE_SPP SI import adapter preserving the frozen SPP v5 engine.
if nargin<2,options=struct();end
if nargin<3,inputSettings=struct();end
if ~isstruct(options)||~isscalar(options),error('MergedLAOS:SPPOptions','SPP options must be a scalar structure.');end
D=merged_laos_read_input(path,inputSettings,'spp');
engine=options;
% A normalized struct is already column-mapped. No file importer is invoked
% by the engine; native cleaning/sorting/duplicate handling remains active.
engine.TimeColumn=1;engine.StrainColumn=2;engine.StressColumn=3;
engine.HeaderLines=0;engine.Delimiter='';engine.Sheet=1;engine.StrainUnit='decimal';
names=fieldnames(engine);values=struct2cell(engine);args=reshape([names values]',1,[]);
data=struct('t',D.data(:,1),'gamma',D.data(:,2),'sigma',D.data(:,3));
R=spp_laos_analyze_v5(data,args{:});
if ~merged_laos_source_current(D.source),error('MergedLAOS:SourceChanged','The input changed during analysis. Reanalyse it.');end
R.input_settings=D.settings;R.unit_conversion=D.conversion;R.source=D.source;
R.source.engineInputRows=D.source.rowsUsed;R.source.rowsUsed=R.cleaning.n_clean;
R.source.engineNonfiniteRowsRemoved=R.cleaning.nonfinite_rows_removed;
R.import_info.original_source=D.source.path;R.import_info.source=D.source.path;
R.import_info.columns=[D.settings.TimeColumn D.settings.StrainColumn D.settings.StressColumn];
R.import_info.input_settings=D.settings;R.import_info.unit_conversion=D.conversion;
if ~isempty(R.average)
    R.average.import_info.original_source=D.source.path;R.average.import_info.source=D.source.path;
    R.average.import_info.input_settings=D.settings;R.average.import_info.unit_conversion=D.conversion;
end
end
