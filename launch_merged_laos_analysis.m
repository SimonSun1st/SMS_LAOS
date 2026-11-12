function app = launch_merged_laos_analysis(varargin)
%LAUNCH_MERGED_LAOS_ANALYSIS Open SMS-LAOS using its original launcher name.
app = launch_SMS_LAOS(varargin{:});
if nargout == 0
    clear app;
end
end
