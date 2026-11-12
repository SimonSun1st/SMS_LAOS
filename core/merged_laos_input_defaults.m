function o=merged_laos_input_defaults(supplied)
%MERGED_LAOS_INPUT_DEFAULTS Shared file mapping and physical input units.
% These describe values in the acquisition file. Engines receive seconds,
% dimensionless strain and pascals; derived frequency/rate use Hz and s^-1.
o=struct('TimeUnit','s','StrainUnit','percent','StressUnit','Pa', ...
    'TimeColumn',1,'StrainColumn',2,'StressColumn',3, ...
    'HeaderLines',0,'Delimiter','','Sheet',1);
if nargin==0,return;end
if ~isstruct(supplied)||~isscalar(supplied)
    error('MergedLAOS:InputSettings','Input settings must be a scalar structure.');
end
for f=fieldnames(supplied)'
    if ~isfield(o,f{1}),error('MergedLAOS:InputSettings','Unknown input setting: %s',f{1});end
    o.(f{1})=supplied.(f{1});
end
for f={'TimeUnit','StrainUnit','StressUnit','Delimiter'}
    v=o.(f{1});
    if ~(ischar(v)&&(isrow(v)||isempty(v)))&&~(isstring(v)&&isscalar(v))
        error('MergedLAOS:InputSettings','%s must be scalar text.',f{1});
    end
    o.(f{1})=char(v);
end
if ~ismember(o.TimeUnit,{'s','ms','us','min','h'})
    error('MergedLAOS:InputUnits','TimeUnit must be s, ms, us, min or h.');
end
if ~ismember(o.StrainUnit,{'percent','decimal','millistrain','microstrain'})
    error('MergedLAOS:InputUnits','StrainUnit must be percent, decimal, millistrain or microstrain.');
end
if ~ismember(o.StressUnit,{'Pa','kPa','MPa','mPa','bar','psi','dyn/cm^2'})
    error('MergedLAOS:InputUnits','StressUnit must be Pa, kPa, MPa, mPa, bar, psi or dyn/cm^2 (case-sensitive).');
end
for f={'TimeColumn','StrainColumn','StressColumn'}
    v=o.(f{1});
    if ~isnumeric(v)||~isreal(v)||~isscalar(v)||~isfinite(v)||v<1||v~=fix(v)
        error('MergedLAOS:InputColumns','%s must be a positive integer scalar.',f{1});
    end
end
cols=[o.TimeColumn o.StrainColumn o.StressColumn];
if ~isnumeric(cols)||~isreal(cols)||numel(cols)~=3||any(~isfinite(cols))||any(cols<1)||any(cols~=fix(cols))||numel(unique(cols))~=3
    error('MergedLAOS:InputColumns','Choose three different positive integer column numbers.');
end
if ~isempty(o.HeaderLines)&&(~isnumeric(o.HeaderLines)||~isscalar(o.HeaderLines)||~isreal(o.HeaderLines)||~isfinite(o.HeaderLines)||o.HeaderLines<0||o.HeaderLines~=fix(o.HeaderLines))
    error('MergedLAOS:InputHeaders','HeaderLines must be empty (automatic) or a nonnegative integer.');
end
if strcmp(o.Delimiter,'auto'),o.Delimiter='';
elseif strcmp(o.Delimiter,'tab'),o.Delimiter=sprintf('\t');
elseif strcmp(o.Delimiter,'space'),o.Delimiter=' ';end
if isstring(o.Sheet)
    if ~isscalar(o.Sheet),error('MergedLAOS:InputSheet','Excel sheet must be a scalar name or positive integer.');end
    o.Sheet=char(o.Sheet);
end
if ischar(o.Sheet)
    if isempty(o.Sheet)||~isrow(o.Sheet),error('MergedLAOS:InputSheet','Excel sheet must be a nonempty scalar name.');end
    number=str2double(o.Sheet);
    if isfinite(number)&&number>=1&&number==fix(number),o.Sheet=number;end
elseif ~isnumeric(o.Sheet)||~isreal(o.Sheet)||~isscalar(o.Sheet)||~isfinite(o.Sheet)||o.Sheet<1||o.Sheet~=fix(o.Sheet)
    error('MergedLAOS:InputSheet','Excel sheet must be a name or positive integer.');
end
end
