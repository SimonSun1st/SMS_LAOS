function D=SMS_LAOS_app_read_input(path,settings,policy)
%SMS_LAOS_APP_READ_INPUT Read original input and convert physical units to SI.
% policy='selected': remove rows missing a selected column; strict time.
% policy='all_columns': preserve the legacy SMS any-column-NaN filter.
% policy='spp': leave cleaning, sorting and duplicate policies to SPP v5.
if nargin<2,settings=struct();end
if nargin<3,policy='selected';end
settings=SMS_LAOS_app_input_defaults(settings);
policy=validatestring(policy,{'selected','all_columns','spp'});
if ~(ischar(path)&&isrow(path))&&~(isstring(path)&&isscalar(path))
    error('MergedLAOS:InputPath','Input path must be scalar text.');
end
path=char(path);if ~isfile(path),error('MergedLAOS:InputPath','File not found: %s',path);end
[ok,attr]=fileattrib(path);if ok,path=attr.Name;end %#ok<FILEATTRIB>
[~,name,ext]=fileparts(path);
if ~ismember(lower(ext),{'.dat','.txt','.csv','.tsv','.xls','.xlsx'})
    error('MergedLAOS:InputFormat','Use DAT, CSV, TXT, TSV, XLS or XLSX data.');
end
before=signature(path);cols=[settings.TimeColumn settings.StrainColumn settings.StressColumn];
if ismember(lower(ext),{'.xls','.xlsx'})
    args={'Sheet',settings.Sheet};
    if ~isempty(settings.HeaderLines)&&settings.HeaderLines>0,args=[args {'Range',sprintf('A%d',settings.HeaderLines+1)}];end
else
    args={'FileType','text'};
    if ~isempty(settings.HeaderLines),args=[args {'NumHeaderLines',settings.HeaderLines}];end
    if ~isempty(settings.Delimiter),args=[args {'Delimiter',settings.Delimiter}];end
end
try
    matrix=readmatrix(path,args{:});
catch readError
    accessError=input_access_error(path,before.Bytes);
    if isempty(accessError),rethrow(readError);end
    throwAsCaller(addCause(accessError,readError));
end
if ~isnumeric(matrix)||~ismatrix(matrix)||size(matrix,2)<max(cols)
    error('MergedLAOS:InputColumns','The selected columns are not available in this file.');
end
selected=matrix(:,cols);nanSelected=any(isnan(selected),2);nanAny=any(isnan(matrix),2);
switch policy
    case 'all_columns',removed=nanAny;
    case 'selected',removed=nanSelected;
    otherwise,removed=false(size(nanSelected));
end
raw=selected(~removed,:);
if ~isreal(raw),error('MergedLAOS:InputData','Input values must be real numbers.');end
if ~strcmp(policy,'spp')
    if size(raw,1)<10||any(~isfinite(raw),'all')
        error('MergedLAOS:PreviewData','At least 10 finite numeric rows are required after removing header/missing rows.');
    end
    if any(diff(raw(:,1))<=0)
        error('MergedLAOS:PreviewTime','Time must strictly increase; duplicate/decreasing timestamps are not changed automatically.');
    end
end
[factors,divisors]=conversion(settings);data=raw;
% Division preserves the original percent-strain arithmetic exactly.
for k=1:3
    if divisors(k)~=1,data(:,k)=data(:,k)/divisors(k);
    elseif factors(k)~=1,data(:,k)=data(:,k)*factors(k);end
end
if any(isfinite(raw)&~isfinite(data),'all')
    error('MergedLAOS:UnitOverflow','Converting the selected input units overflowed finite numeric values. Check units and data magnitudes.');
end
if ~strcmp(policy,'spp')&&any(diff(data(:,1))<=0)
    error('MergedLAOS:PreviewTime','Time conversion does not retain distinct increasing timestamps. Check the time unit and numeric precision.');
end
after=signature(path);
if ~isequal(before,after),error('MergedLAOS:SourceChanged','The source changed while reading. Load it again.');end
source=struct('path',path,'name',[name ext],'bytes',before.Bytes,'datenum',before.ModifiedDatenum, ...
    'signature',before,'signatureMeaning','File size and modification time, not a content hash.', ...
    'rowsRead',size(matrix,1),'rowsUsed',size(data,1),'rowsRemovedNaN',sum(removed), ...
    'rowsRemovedForExtraColumns',sum(removed&~nanSelected),'rowPolicy',policy);
unitConversion=struct('inputTimeUnit',settings.TimeUnit,'inputStrainUnit',settings.StrainUnit, ...
    'inputStressUnit',settings.StressUnit,'timeFactorToSeconds',factors(1), ...
    'strainFactorToDecimal',factors(2),'stressFactorToPa',factors(3), ...
    'internalTimeUnit','s','internalStrainUnit','decimal','internalStressUnit','Pa', ...
    'derivedFrequencyUnit','Hz','derivedAngularFrequencyUnit','rad/s','derivedStrainRateUnit','1/s', ...
    'notes','Unit conversion only; no resampling, smoothing, DC removal or phase alignment.');
D=struct('data',data,'rawSelected',raw,'source',source,'settings',settings,'conversion',unitConversion);
end

function issue=input_access_error(path,expectedBytes)
issue=[];
if ~isfile(path)
    issue=MException('MergedLAOS:InputPath','File is missing. Locate it and load it again: %s',path);
    return
end
macOneDrive=ismac&&~isempty(regexpi(path,'/Library/CloudStorage/OneDrive[^/]*/','once'));
if macOneDrive
    % Inspect metadata only after readmatrix fails. POSIX single quoting
    % preserves spaces, apostrophes and shell metacharacters in file paths.
    quotedPath="'" + replace(string(path), "'", "'\''") + "'";
    [rc,flags]=system(char("/usr/bin/stat -f '%Sf' -- " + quotedPath));
    if rc==0 && any(strcmp(strsplit(strtrim(flags),','),'dataless'))
        issue=MException('MergedLAOS:CloudFileUnavailable','%s\n%s', ...
            'OneDrive has not downloaded this file.', ...
            'In Finder, choose "Always Keep on This Device" for the file or folder. Wait for the download, then retry.');
        return
    end
end
% Some providers permit fopen but fail at the first read. A readable file
% keeps its original readmatrix error (for example an invalid workbook sheet).
fid=fopen(path,'rb');
if fid>=0
    closeFile=onCleanup(@()fclose(fid)); %#ok<NASGU>
    firstByte=fread(fid,1,'*uint8');
    if ~isempty(firstByte)||expectedBytes==0,return;end
end
if macOneDrive
    issue=MException('MergedLAOS:InputRead', ...
        'MATLAB cannot read this OneDrive file. Check the download in Finder and MATLAB read access, then retry.');
else
    issue=MException('MergedLAOS:InputRead','MATLAB cannot read this file. Check the file location and read permissions, then retry: %s',path);
end
end

function s=signature(path)
d=dir(path);
if isempty(d)||d(1).isdir,s=struct('Exists',false,'Bytes',NaN,'ModifiedDatenum',NaN);
else,s=struct('Exists',true,'Bytes',d(1).bytes,'ModifiedDatenum',d(1).datenum);end
end
function [f,d]=conversion(o)
f=[1 1 1];d=[1 1 1];
switch o.TimeUnit
    case 'ms',d(1)=1e3;f(1)=1e-3;
    case 'us',d(1)=1e6;f(1)=1e-6;
    case 'min',f(1)=60;
    case 'h',f(1)=3600;
end
switch o.StrainUnit
    case 'percent',d(2)=100;f(2)=.01;
    case 'millistrain',d(2)=1e3;f(2)=1e-3;
    case 'microstrain',d(2)=1e6;f(2)=1e-6;
end
switch o.StressUnit
    case 'kPa',f(3)=1e3;
    case 'MPa',f(3)=1e6;
    case 'mPa',d(3)=1e3;f(3)=1e-3;
    case 'bar',f(3)=1e5;
    case 'psi',f(3)=.45359237*9.80665/.0254^2;
    case 'dyn/cm^2',d(3)=10;f(3)=.1;
end
end
