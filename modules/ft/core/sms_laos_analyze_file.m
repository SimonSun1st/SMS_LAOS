function R = sms_laos_analyze_file(path, options)
%SMS_LAOS_ANALYZE_FILE Read legacy .dat data and call the unchanged v2 core.
% Import deliberately preserves the original script's order: readmatrix,
% remove rows with NaN in ANY column, then retain columns 1, 2 and 3.
% Diagnostics never resample, smooth, rephase or change the core result.
if nargin<2, options=sms_laos_defaults(); end
options=sms_laos_validate_options(options);
if ~(ischar(path) && isrow(path)) && ~(isstring(path) && isscalar(path))
    error('SMSApp:Input','Input path must be scalar text.');
end
path=char(path);
if ~isfile(path), error('SMSApp:Input','Input file does not exist: %s',path); end
[ok,attr]=fileattrib(path); if ok, path=attr.Name; end
[~,name,ext]=fileparts(path);
if ~strcmpi(ext,'.dat'), error('SMSApp:Input','The original SMS input format is .dat.'); end
before=dir(path);
data=readmatrix(path,'FileType','text');
if ~isnumeric(data) || ~ismatrix(data) || size(data,2)<3
    error('SMSApp:Input','Expected at least three numeric columns: time (s), strain, stress (Pa).');
end
nanRows=any(isnan(data),2);
extraColumnNaNRows=sum(nanRows & ~any(isnan(data(:,1:3)),2));
rowsRead=size(data,1);
data=data(~nanRows,:);
data=data(:,1:3);
if size(data,1)<10, error('SMSApp:Input','Fewer than 10 rows remain after the original NaN-row filtering.'); end
if ~isreal(data) || any(~isfinite(data),'all')
    error('SMSApp:Input','Time, strain and stress must be real, finite values.');
end
dt=diff(data(:,1));
if any(dt<=0)
    error('SMSApp:Input','Time must be strictly increasing; duplicate or decreasing timestamps cannot be analyzed.');
end
R=sms_laos_core_v2(data,options.cycle_selection_mode, ...
    options.remove_first_cycles,options.remove_last_cycles,options.last_n_cycles, ...
    options.strain_is_percent,options.use_freq_range,options.freq_min, ...
    options.freq_max,options.use_alternating_odd_sign);
after=dir(path);
if isempty(after) || before.bytes~=after.bytes || before.datenum~=after.datenum
    error('SMSApp:SourceChanged','The input changed during analysis. Analyze the file again.');
end
R.settings=options;
R.source=struct('path',path,'name',[name ext],'bytes',before.bytes, ...
    'datenum',before.datenum,'signature_meaning','File size and modification time; not a content hash.', ...
    'rows_read',rowsRead,'rows_used',size(data,1),'rows_removed_nan',sum(nanRows), ...
    'rows_removed_for_extra_columns',extraColumnNaNRows);
q=struct('has_warnings',false,'messages',{{}}, ...
    'relative_sampling_step_deviation',max(abs(dt-median(dt)))/median(dt), ...
    'sample_rate_hz',1/mean(dt),'third_harmonic_below_nyquist',3*R.freq_hz<.5/mean(dt), ...
    'residual_rms_over_I1',R.residual_rms_over_I1, ...
    'residual_review_threshold',0.10,'sampling_review_threshold',0.01);
q.notes={ ...
    'The numerical engine is the original SMS_LAOS_v2 implementation. Diagnostics do not change its results.', ...
    'Cycle selection trims a time range; it does not automatically establish steady state.', ...
    'S, T and stress reconstruction use only the first and third terms.', ...
    'A reconstruction residual can reflect higher harmonics, frequency/cycle selection, sampling, differentiation noise or conventions.', ...
    'Time is interpreted as seconds, stress as Pa; the strain-unit setting must match the input.'};
if q.relative_sampling_step_deviation>q.sampling_review_threshold
    q.messages{end+1}=sprintf('Sampling steps vary by %.3g%% relative to the median. The original FFT still uses the mean time step; no resampling was applied.',100*q.relative_sampling_step_deviation);
end
if ~q.third_harmonic_below_nyquist
    q.messages{end+1}='The third harmonic reaches or exceeds the Nyquist frequency. Third-harmonic quantities are not resolved by this sampling rate.';
end
if extraColumnNaNRows>0
    q.messages{end+1}=sprintf('The legacy import removed %d rows because an extra column contained NaN, even though the first three columns were numeric.',extraColumnNaNRows);
end
if ~isfinite(R.residual_rms_over_I1) || R.residual_rms_over_I1>q.residual_review_threshold
    q.messages{end+1}=sprintf('Reconstruction RMS/I1 = %.4g. The 0.10 review threshold is a diagnostic heuristic, not a physical validity test.',R.residual_rms_over_I1);
end
metrics=[R.I3_I1 R.e3_e1 R.v3_v1 R.S R.T];
if any(~isfinite(metrics))
    q.messages{end+1}='One or more ratio metrics are non-finite. Inspect denominators and signal amplitudes; exact values are retained in MAT results.';
end
q.has_warnings=~isempty(q.messages);
R.quality=q;
end
