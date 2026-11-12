function P = merged_laos_preview(path, options)
%MERGED_LAOS_PREVIEW Read measured waveforms before choosing an analysis.
% Displayed arrays retain acquired sample times after unit conversion; no resampling,
% smoothing, phase alignment or stress reconstruction is applied. The
% frequency estimate is for preview/window selection, not an override of
% the independent SMS or SPP frequency/cycle calculations.
if nargin < 2, options = struct(); end
defaults = merged_laos_input_defaults();
defaults.FrequencyMin=[];defaults.FrequencyMax=[];
options = merge_options(defaults, options);
frequencyMin=options.FrequencyMin;frequencyMax=options.FrequencyMax;
inputSettings=rmfield(options,{'FrequencyMin','FrequencyMax'});
D=merged_laos_read_input(path,inputSettings,'selected');
options=D.settings;options.FrequencyMin=frequencyMin;options.FrequencyMax=frequencyMax;
t=D.data(:,1);strain=D.data(:,2);stress=D.data(:,3);
rate = gradient(strain,t);
[frequency,estimate] = estimate_frequency(t,strain,options.FrequencyMin,options.FrequencyMax);
[amp,amplitudes] = measured_amplitude(t,strain,frequency);
if ~merged_laos_source_current(D.source)
    error('MergedLAOS:SourceChanged','The source changed while preparing the preview. Load it again.');
end
messages = {};
steps = diff(t);
typicalStep = median(steps);
variation = max(abs(steps-typicalStep))/typicalStep;
if variation>0.01
    messages{end+1}='Sampling intervals vary by more than 1%. The preview keeps actual timestamps; the FFT seed uses the mean interval.';
end
if estimate.relativeResidual>0.1
    messages{end+1}='Strain is not closely described by one sinusoid. The displayed frequency and strain amplitude are descriptive estimates; inspect the waveform.';
end
if numel(amplitudes)<2
    messages{end+1}='Fewer than two complete estimated periods are available; frequency and amplitude require review.';
end
if ~isempty(amplitudes) && max(abs(amplitudes-median(amplitudes)))/max(median(amplitudes),eps)>0.05
    messages{end+1}='Measured strain amplitude varies by more than 5% across estimated periods. The file amplitude is their median; inspect individual cycles before comparing strain levels.';
end
P = struct('time',t,'strain',strain,'stress',stress,'strainRate',rate, ...
    'frequencyHz',frequency,'omega',2*pi*frequency,'strainAmplitudePercent',100*amp, ...
    'cycleStrainAmplitudesPercent',100*amplitudes,'frequencyEstimate',estimate, ...
    'amplitudeMethod','Median half peak-to-peak amplitude of complete estimated periods; whole-record half range if no complete period.', ...
    'source',D.source,'unit_conversion',D.conversion, ...
    'options',options,'quality',struct('has_warnings',~isempty(messages),'messages',{messages}, ...
        'relativeSamplingStepDeviation',variation,'notes',{{ ...
        'Preview retains measured strain/stress values and timestamps; no DC subtraction is applied to displayed/exported waveforms.', ...
        'Strain rate is gradient(strain,time), using actual timestamps and without smoothing.', ...
        'Frequency is a preview estimate; each analysis retains its own frequency and cycle selection.', ...
        'Only rows missing a selected preview column are removed. The legacy SMS importer also removes rows missing any extra column.', ...
        'Input values are converted using the shared units; preview/export time is s, strain is dimensionless, stress is Pa and strain rate is s^-1.'}}));
end

function o = merge_options(o,s)
if ~isstruct(s) || ~isscalar(s), error('MergedLAOS:PreviewOptions','Options must be a scalar structure.'); end
for f=fieldnames(s)'
    if ~isfield(o,f{1}), error('MergedLAOS:PreviewOptions','Unknown preview setting: %s',f{1}); end
    o.(f{1})=s.(f{1});
end
o.StrainUnit=char(o.StrainUnit);
end

function [f,info] = estimate_frequency(t,g,low,high)
duration=t(end)-t(1); fs=1/mean(diff(t)); n=numel(t);
if isempty(low),low=max(eps,0.5/duration);end
if isempty(high),high=fs/2;end
if ~isscalar(low)||~isscalar(high)||~isfinite(low)||~isfinite(high)||low<=0||high<=low
    error('MergedLAOS:PreviewFrequency','Frequency bounds must be positive finite values with maximum greater than minimum.');
end
high=min(high,fs/2);
y=g-mean(g);
if max(abs(y))<=eps(max(1,max(abs(g))))*100
    error('MergedLAOS:PreviewFrequency','The strain signal is constant or too small to estimate a frequency.');
end
F=fft(y); frequencies=(0:floor(n/2))'*(fs/n);
amplitudes=2*abs(F(1:numel(frequencies)))/n;
allowed=frequencies>=low & frequencies<=high & frequencies>0;
if ~any(allowed),error('MergedLAOS:PreviewFrequency','No FFT bins fall within the specified frequency range.');end
indices=find(allowed);[~,j]=max(amplitudes(indices));index=indices(j);seed=frequencies(index);
% Fit the dominant strain period using acquired timestamps. A linear trend
% is a nuisance term for frequency estimation only and never alters arrays.
tt=t-t(1); lower=max(low,seed-fs/n);upper=min(high,seed+fs/n);
if upper<=lower,error('MergedLAOS:PreviewFrequency','The usable frequency interval is empty.');end
f=fminbnd(@(q)sinusoid_error(q,tt,y),lower,upper,optimset('Display','off','TolX',max(1e-10,seed*1e-8)));
[sse,fit]=sinusoid_error(f,tt,y);
% Guard narrow limits: fminbnd does not evaluate the interval endpoints.
for q=[lower upper seed]
    [trial,beta]=sinusoid_error(q,tt,y);
    if trial<sse,f=q;sse=trial;fit=beta;end
end
info=struct('method','Dominant demeaned-strain FFT peak refined by least-squares sinusoid plus linear trend at actual timestamps.', ...
    'seedFrequencyHz',seed,'frequencyHz',f,'frequencyMinHz',low,'frequencyMaxHz',high, ...
    'relativeResidual',sqrt(sse/sum(y.^2)),'fittedStrainAmplitude',hypot(fit(1),fit(2)), ...
    'fftFrequencyHz',frequencies,'fftAmplitude',amplitudes);
end

function [sse,beta] = sinusoid_error(f,t,y)
X=[sin(2*pi*f*t),cos(2*pi*f*t),ones(size(t)),t/max(t(end),eps)];
beta=X\y; residual=y-X*beta;sse=sum(residual.^2);
end

function [a,all] = measured_amplitude(t,g,f)
period=1/f; count=floor((t(end)-t(1))/period+1e-8);all=nan(count,1);
% Time is strictly increasing. Carry the first sample of the next period
% forward so each sample is visited once, using the same [start,end) rule.
first=1;
nSamples=numel(t);
for k=1:count
    next=first;
    boundary=t(1)+k*period;
    while next<=nSamples && t(next)<boundary
        next=next+1;
    end
    if next-first>=3
        values=g(first:next-1);
        all(k)=0.5*(max(values)-min(values));
    end
    first=next;
end
all=all(isfinite(all));
if isempty(all),a=0.5*(max(g)-min(g));else,a=median(all);end
end
