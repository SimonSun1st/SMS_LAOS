function R=SMS_LAOS_app_analyze_FT_SD(path,options,inputSettings)
%SMS_LAOS_APP_ANALYZE_FT_SD Shared import/units adapter for frozen SMS v2.
% Input units are recorded separately from the unchanged engine settings.
if nargin<2,options=SMS_LAOS_app_FT_SD_defaults();end
if nargin<3,inputSettings=struct();end
options=SMS_LAOS_app_FT_SD_validate_options(options);
D=SMS_LAOS_app_read_input(path,inputSettings,'all_columns');data=D.data;
% Retain the original percent branch, including its floating-point order.
options.strain_is_percent=strcmp(D.settings.StrainUnit,'percent');
if options.strain_is_percent,data(:,2)=D.rawSelected(:,2);end
R=SMS_LAOS_app_FT_SD_core_v2(data,options.cycle_selection_mode,options.remove_first_cycles, ...
    options.remove_last_cycles,options.last_n_cycles,options.strain_is_percent, ...
    options.use_freq_range,options.freq_min,options.freq_max,options.use_alternating_odd_sign);
if ~SMS_LAOS_app_source_current(D.source),error('MergedLAOS:SourceChanged','The input changed during analysis. Reanalyse it.');end
R.settings=options;
R.source=struct('path',D.source.path,'name',D.source.name,'bytes',D.source.bytes, ...
    'datenum',D.source.datenum,'signature_meaning','File size and modification time; not a content hash.', ...
    'rows_read',D.source.rowsRead,'rows_used',D.source.rowsUsed,'rows_removed_nan',D.source.rowsRemovedNaN, ...
    'rows_removed_for_extra_columns',D.source.rowsRemovedForExtraColumns);
R.input_settings=D.settings;R.unit_conversion=D.conversion;
dt=diff(D.data(:,1));
q=struct('has_warnings',false,'messages',{{}}, ...
    'relative_sampling_step_deviation',max(abs(dt-median(dt)))/median(dt), ...
    'sample_rate_hz',1/mean(dt),'third_harmonic_below_nyquist',3*R.freq_hz<.5/mean(dt), ...
    'residual_rms_over_I1',R.residual_rms_over_I1,'residual_review_threshold',.1,'sampling_review_threshold',.01);
q.notes={ ...
    'The numerical engine is the original SMS_LAOS_v2 implementation. Diagnostics do not change its results.', ...
    'Cycle selection trims a time range; it does not automatically establish steady state.', ...
    'S, T and stress reconstruction use only the first and third terms.', ...
    'A reconstruction residual can reflect higher harmonics, frequency/cycle selection, sampling, differentiation noise or conventions.', ...
    'Shared input units are converted to seconds, decimal strain and pascals before analysis; input_settings and unit_conversion record the original units.'};
if q.relative_sampling_step_deviation>q.sampling_review_threshold
    q.messages{end+1}=sprintf('Sampling steps vary by %.3g%% relative to the median. The original FFT still uses the mean time step; no resampling was applied.',100*q.relative_sampling_step_deviation);
end
if ~q.third_harmonic_below_nyquist
    q.messages{end+1}='The third harmonic reaches or exceeds the Nyquist frequency. Third-harmonic quantities are not resolved by this sampling rate.';
end
if D.source.rowsRemovedForExtraColumns>0
    q.messages{end+1}=sprintf('The legacy import removed %d rows because an unselected column contained NaN, even though the selected time/strain/stress columns were numeric.',D.source.rowsRemovedForExtraColumns);
end
if ~isfinite(R.residual_rms_over_I1)||R.residual_rms_over_I1>q.residual_review_threshold
    q.messages{end+1}=sprintf('Reconstruction RMS/I1 = %.4g. The 0.10 review threshold is a diagnostic heuristic, not a physical validity test.',R.residual_rms_over_I1);
end
if any(~isfinite([R.I3_I1 R.e3_e1 R.v3_v1 R.S R.T]))
    q.messages{end+1}='One or more ratio metrics are non-finite. Inspect denominators and signal amplitudes; exact values are retained in MAT results.';
end
q.has_warnings=~isempty(q.messages);R.quality=q;
end
