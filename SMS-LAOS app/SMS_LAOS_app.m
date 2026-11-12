function app = SMS_LAOS_app(varargin)
%SMS_LAOS_APP Open the SMS-LAOS application.
root = fileparts(mfilename('fullpath'));
addpath(root, fullfile(root, 'app'), fullfile(root, 'core'), ...
    fullfile(root, 'modules', 'ft', 'core'), fullfile(root, 'modules', 'ft', 'app'), ...
    fullfile(root, 'modules', 'spp'), fullfile(root, 'modules', 'spp', 'app'), ...
    fullfile(root, 'modules', 'spp', 'legacy'));
app = SMS_LAOS_app_window(varargin{:});
if nargout == 0
    clear app;
end
end
