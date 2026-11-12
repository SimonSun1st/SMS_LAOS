function current=SMS_LAOS_app_source_current(source)
% File metadata check; deliberately not described as a content hash.
current=false;
if ~isstruct(source)||~all(isfield(source,{'path','bytes','datenum'})),return;end
d=dir(source.path);
current=~isempty(d)&&~d(1).isdir&&d(1).bytes==source.bytes&&d(1).datenum==source.datenum;
end
