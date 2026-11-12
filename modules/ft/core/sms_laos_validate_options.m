function options = sms_laos_validate_options(supplied)
%SMS_LAOS_VALIDATE_OPTIONS Merge supplied settings with the original defaults.
options=sms_laos_defaults();
if nargin==0, return; end
if ~isstruct(supplied) || ~isscalar(supplied)
    error('SMSApp:Settings','Settings must be a scalar structure.');
end
names=fieldnames(supplied);
for k=1:numel(names)
    name=names{k};
    if ~isfield(options,name), error('SMSApp:Settings','Unknown setting: %s',name); end
    options.(name)=supplied.(name);
end
if ~(ischar(options.cycle_selection_mode) && isrow(options.cycle_selection_mode)) && ...
        ~(isstring(options.cycle_selection_mode) && isscalar(options.cycle_selection_mode))
    error('SMSApp:Settings','Cycle selection mode must be scalar text.');
end
options.cycle_selection_mode=char(options.cycle_selection_mode);
if ~any(strcmp(options.cycle_selection_mode,{'trim_ends','last_n_cycles'}))
    error('SMSApp:Settings','Cycle selection must be trim_ends or last_n_cycles.');
end
for name={'remove_first_cycles','remove_last_cycles','last_n_cycles'}
    n=name{1}; v=options.(n);
    if ~isnumeric(v) || ~isscalar(v) || ~isreal(v) || ~isfinite(v) || v<0 || v~=fix(v)
        error('SMSApp:Settings','%s must be a non-negative integer.',n);
    end
end
if options.last_n_cycles<1, error('SMSApp:Settings','last_n_cycles must be at least 1.'); end
for name={'strain_is_percent','use_freq_range','use_alternating_odd_sign','fast_mode','save_curve_csv'}
    n=name{1}; v=options.(n);
    if ~(islogical(v) || isnumeric(v)) || ~isscalar(v) || ~isreal(v) || ~isfinite(v) || ~any(v==[0 1])
        error('SMSApp:Settings','%s must be true or false.',n);
    end
    options.(n)=logical(v);
end
for name={'freq_min','freq_max'}
    n=name{1}; v=options.(n);
    if ~isnumeric(v) || ~isscalar(v) || ~isreal(v) || ~isfinite(v) || v<=0
        error('SMSApp:Settings','%s must be a positive finite number in Hz.',n);
    end
end
if options.freq_max<=options.freq_min
    error('SMSApp:Settings','Maximum frequency must be greater than minimum frequency.');
end
end
