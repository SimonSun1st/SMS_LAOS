function app = launch_merged_laos_analysis(varargin)
%LAUNCH_MERGED_LAOS_ANALYSIS Start SMS-LAOS using its legacy entry point.
app = launch_SMS_LAOS(varargin{:});
if nargout == 0
    clear app;
end
end
