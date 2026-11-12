function app = launch_SMS_LAOS(varargin)
%LAUNCH_SMS_LAOS Start SMS-LAOS using the original entry point.
appFolder = fullfile(fileparts(mfilename('fullpath')), 'SMS-LAOS app');
addpath(appFolder);
app = SMS_LAOS_app(varargin{:});
if nargout == 0
    clear app;
end
end
