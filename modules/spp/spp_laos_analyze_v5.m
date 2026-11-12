function R = spp_laos_analyze_v5(file_or_data, varargin)
%SPP_LAOS_ANALYZE_V5 Average-state and continuous cycle-evolution analysis.
% R=spp_laos_analyze_v5(D,'AnalysisMode','cycle_evolution');
% D is a file or a struct with t [s], gamma, sigma [Pa]. All v3 options are
% accepted; TrimCycles now defaults to [0 0]. The frozen legacy core is used
% unchanged for import, boundary detection and selected-cycle averages.
% New options: AnalysisMode='average'|'cycle_evolution',
% AveragingPolicy='stable_tail'|'manual', MinStableCycles=5,
% StationarityTolerance=.05, HarmonicStationarityTolerance=.25,
% HarmonicMaxOrder=15, HarmonicFloor=.001,
% AssessSmoothingSensitivity=true.
% HarmonicFloor is an empirical significance screen relative to I1, not an
% independently estimated noise floor or an automatic harmonic truncation.
% The separate harmonic tolerance limits complex coefficient RANGE and total
% fitted trend, not a coefficient of variation or a confidence interval.
%
% A stable tail is an engineering screen within the observed time window,
% not proof of material equilibrium. No passing tail means average=[];
% there is no silent fallback. Explicit CycleNumbers override TrimCycles.
% Evolution uses local polynomial derivatives at ACTUAL sample times and
% local SVD planes with no periodic wrapping or interpolation across gaps.
% Harmonics of evolving cycles are descriptive coefficients, not steady-state
% harmonics. WorkInput is integral(sigma dgamma), not necessarily dissipation.
% All measured even components are preserved. No relaxation time is fitted.

p = inputParser;
posint = @(x) isnumeric(x) && isreal(x) && isscalar(x) && isfinite(x) && x>=1 && x==fix(x);
nonneg = @(x) isnumeric(x) && isreal(x) && isscalar(x) && isfinite(x) && x>=0;
positive = @(x) nonneg(x) && x>0;
flag = @(x) isscalar(x) && (islogical(x) || (isnumeric(x) && ismember(x,[0 1])));
choice = @(x,c) (ischar(x) || (isstring(x) && isscalar(x))) && any(strcmpi(x,c));
p.addParameter('TimeColumn',1,posint);
p.addParameter('StrainColumn',2,posint);
p.addParameter('StressColumn',3,posint);
p.addParameter('HeaderLines',0,@(x) nonneg(x) && x==fix(x));
p.addParameter('Sheet',1);
p.addParameter('Delimiter','',@(x) ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter('StrainUnit','decimal',@(x) choice(x,{'decimal','percent'}));
p.addParameter('Omega',[],@(x) isempty(x) || positive(x));
p.addParameter('DetectCyclesFrom','gamma',@(x) choice(x,{'gamma','stress'}));
p.addParameter('TrimCycles',[0 0],@(x) isnumeric(x) && isreal(x) && numel(x)==2 && all(isfinite(x(:))) && all(x(:)>=0) && all(x(:)==fix(x(:))));
p.addParameter('CycleNumbers',[],@(x) isnumeric(x) && isreal(x) && all(isfinite(x(:))) && all(x(:)>=1) && all(x(:)==fix(x(:))));
p.addParameter('SelectionMode','average',@(x) choice(x,{'average','single_middle','single_manual'}));
p.addParameter('PointsPerCycle',1001,@(x) posint(x) && x>=101);
p.addParameter('CycleTolerance',.15,@(x) positive(x) && x<.5);
p.addParameter('MaxGapFactor',5,@(x) positive(x) && x>1);
p.addParameter('SmoothFraction',.02,@(x) positive(x) && x<.5);
p.addParameter('SmoothWindow',[],@(x) isempty(x) || (posint(x) && x>=5 && mod(x,2)==1));
p.addParameter('SmoothOrder',3,@(x) posint(x) && x<=9);
p.addParameter('DerivativeMode','finite_difference',@(x) choice(x,{'finite_difference','sgolay'}));
p.addParameter('FDOrder',5,@(x) isscalar(x) && isnumeric(x) && ismember(x,[3 5 7 9]));
p.addParameter('StrainRateMode','analytic_sine_fit',@(x) choice(x,{'analytic_sine_fit','numerical'}));
p.addParameter('FitWindowFraction',.015,@(x) positive(x) && x<.25);
p.addParameter('FitHalfWindow',[],@(x) isempty(x) || (posint(x) && x>=2));
p.addParameter('FitWeighting','triangular',@(x) choice(x,{'triangular','uniform'}));
p.addParameter('ConditionThreshold',1e6,@(x) positive(x) && x>1);
p.addParameter('MaskThreshold',0,@(x) nonneg(x) && x<1);
p.addParameter('MinStrainFitR2',.99,@(x) nonneg(x) && x<=1);
p.addParameter('MaxStrainFitNRMSE',.05,positive);
p.addParameter('DuplicateTimePolicy','error',@(x) choice(x,{'error','mean'}));
p.addParameter('AssessWindowSensitivity',true,flag);
p.addParameter('StoreRaw',true,flag);
p.addParameter('MakePlots',true,flag);
p.addParameter('Verbose',true,flag);
p.addParameter('AnalysisMode','average',@(x) choice(x,{'average','cycle_evolution'}));
p.addParameter('AveragingPolicy','stable_tail',@(x) choice(x,{'stable_tail','manual'}));
p.addParameter('MinStableCycles',5,@(x) posint(x) && x>=2);
p.addParameter('StationarityTolerance',.05,@(x) positive(x) && x<1);
p.addParameter('HarmonicStationarityTolerance',.25,@(x) positive(x) && x<1);
p.addParameter('HarmonicMaxOrder',15,@(x) posint(x) && x>=7);
p.addParameter('HarmonicFloor',.001,@(x) positive(x) && x<1);
p.addParameter('AssessSmoothingSensitivity',true,flag);
p.parse(varargin{:});
o=p.Results;
for name={'AnalysisMode','AveragingPolicy','SelectionMode','StrainRateMode','DerivativeMode','FitWeighting','StrainUnit','DetectCyclesFrom','DuplicateTimePolicy'}
    o.(name{1})=lower(char(o.(name{1})));
end
o.TrimCycles=reshape(o.TrimCycles,1,[]); o.CycleNumbers=unique(o.CycleNumbers(:)');
N=o.PointsPerCycle;
if o.HarmonicMaxOrder>floor((N-1)/2)
    error('SPPv5:Harmonics','HarmonicMaxOrder exceeds the resampled phase-grid Nyquist limit.');
end
legacy_names=setdiff(fieldnames(o),{'AnalysisMode','AveragingPolicy','MinStableCycles', ...
    'StationarityTolerance','HarmonicStationarityTolerance','HarmonicMaxOrder','HarmonicFloor','AssessSmoothingSensitivity'});
legacy=struct(); for k=1:numel(legacy_names), legacy.(legacy_names{k})=o.(legacy_names{k}); end
legacy_dir=fullfile(fileparts(mfilename('fullpath')),'legacy');
old_path=path; restore_path=onCleanup(@()path(old_path)); %#ok<NASGU>
addpath(legacy_dir,'-begin');
probe=legacy; probe.TrimCycles=[0 0]; probe.CycleNumbers=[];
probe.SelectionMode='average'; probe.StoreRaw=true; probe.MakePlots=false;
probe.Verbose=false; probe.AssessWindowSensitivity=false;
a=as_pairs(probe);
base=spp_laos_from_periodic_data_v3(file_or_data,a{:});
C=base.cycles.n_cycles;
if isempty(o.CycleNumbers)
    eligible=(1+o.TrimCycles(1)):(C-o.TrimCycles(2));
else
    eligible=o.CycleNumbers;
end
if isempty(eligible) || any(eligible>C)
    error('SPPv5:Selection','Cycle selection is empty or exceeds the detected valid-cycle count.');
end
[ev,complex_harmonics]=cycle_descriptors(base,o);
[tail,diag]=find_stable_tail(ev,complex_harmonics,eligible,o);
selection=struct('eligible_cycles',eligible,'analyzed_cycles',[], ...
    'average_cycles',[],'stable_tail_cycles',tail,'stationarity_pass',~isempty(tail), ...
    'status','','diagnostics',diag);
R=struct('version','5.0','analysis_mode',o.AnalysisMode,'settings',o, ...
    'omega',base.omega,'period',base.period,'average',[], ...
    'evolution',ev,'selection',selection,'quality',struct('has_warnings',false,'messages',{{}}), ...
    'smoothing_sensitivity',[]);
R.import_info=base.import_info; R.cleaning=base.cleaning;
R.cycles=base.cycles; R.reference_omega=base.reference_omega;
R.frequency_info=base.frequency_info;
R.effective_settings=base.effective_settings;
if o.StoreRaw, R.raw=base.raw; end
messages={};
if strcmp(o.AnalysisMode,'average')
    if strcmp(o.AveragingPolicy,'stable_tail')
        selected=tail;
        if isempty(selected)
            R.selection.status='no_stable_tail';
            messages{end+1}='No contiguous final suffix passed the stationarity screen. No averaged SPP curve was generated; inspect cycle diagnostics or explicitly choose manual analysis.';
            messages{end+1}=stationarity_failure_message(diag);
        else
            R.selection.status='stable_tail_selected';
        end
    else
        selected=manual_selection(eligible,o);
        R.selection.status='manual_selection';
        chosen_metrics=stationarity_metrics(ev,complex_harmonics,selected,o);
        R.selection.stationarity_pass=chosen_metrics.pass;
        R.selection.diagnostics.manual_metrics=chosen_metrics;
        if ~chosen_metrics.pass
            messages{end+1}='Manual selection does not pass the stationarity screen (or has too few cycles). Its averaged/single-cycle curve is a user-selected descriptor, not a verified steady response.';
        end
    end
    if ~isempty(selected)
        avopt=legacy; avopt.CycleNumbers=selected; avopt.TrimCycles=[0 0];
        % Selection is already resolved. Preserve legacy single semantics when used.
        if strcmp(o.AveragingPolicy,'stable_tail'), avopt.SelectionMode='average'; end
        avopt.MakePlots=false; avopt.Verbose=false;
        a=as_pairs(avopt); av=spp_laos_from_periodic_data_v3(file_or_data,a{:});
        R.average=av; R.omega=av.omega; R.period=av.period;
        R.effective_settings=av.effective_settings;
        R.selection.average_cycles=selected; R.selection.analyzed_cycles=selected;
        R.evolution.cycle_table.InAverage(selected)=true;
        messages=[messages av.quality.messages]; %#ok<AGROW>
        if o.AssessSmoothingSensitivity
            R.smoothing_sensitivity=smoothing_sensitivity(file_or_data,av,avopt);
            z=R.smoothing_sensitivity;
            if any(z.combined_rms_change>.2)
                messages{end+1}='Nearby smoothing windows change the averaged local moduli by more than 20% combined RMS; inspect both component sensitivities before interpreting sharp features.';
            end
        end
    end
else
    R.selection.analyzed_cycles=eligible; R.selection.status='cycle_evolution';
    R.period=median(ev.cycle_table.Period_s(eligible)); R.omega=2*pi/R.period;
    R.evolution=continuous_spp(ev,eligible,R.omega,o,base.effective_settings);
    R.effective_settings.StrainRateMode='continuous_local_polynomial';
    R.effective_settings.DerivativeMode='local_polynomial_actual_time';
    if isempty(tail)
        messages{end+1}='No final eligible suffix passed the stationarity screen. Cycle harmonics and local SPP curves are time-resolved descriptors of the measured evolution.';
        messages{end+1}=stationarity_failure_message(diag);
    end
    if any(R.evolution.cycle_table.ValidSPPFraction(eligible)<.95)
        messages{end+1}='Some cycles have fewer than 95% valid continuous SPP points. Block-edge support and local-plane conditioning are explicitly masked.';
    end
end
R.evolution.cycle_table.Included(eligible)=true;
if base.cleaning.sorted, messages{end+1}='Input timestamps were sorted; confirm this was one continuous acquisition.'; end
if base.cleaning.nonfinite_rows_removed>0, messages{end+1}='Nonfinite input rows were excluded before cycle detection.'; end
if base.cleaning.duplicate_rows>0, messages{end+1}='Duplicate timestamps were averaged under the explicitly selected duplicate-time policy.'; end
if base.cleaning.large_gap_count>0, messages{end+1}='Timestamp gaps were found. Overlapping cycles were rejected, original cycle labels retained, and evolution fitting does not cross the gaps.'; end
if any(ev.cycle_table.StrainFitNRMSE(eligible)>o.MaxStrainFitNRMSE)
    messages{end+1}='Some measured cycles depart from a sinusoidal strain waveform. Inspect input harmonics and strain-fit residuals.';
end
messages=unique(messages,'stable');
R.quality=struct('has_warnings',~isempty(messages),'messages',{messages}, ...
    'interpretation','Numerical and repeatability diagnostics do not establish material origin. Even harmonics describe measured asymmetry; work input need not equal dissipation.', ...
    'stationarity_threshold_kind','engineering screen, not confidence interval or proof of equilibrium');
if o.Verbose
    fprintf('SPP v5 %s: %d valid cycles; eligible %s; status %s.\n',o.AnalysisMode,C,mat2str(eligible),R.selection.status);
    for k=1:numel(messages), warning('SPPv5:Quality','%s',messages{k}); end
end
if o.MakePlots, plot_v5(R); end
end

function a=as_pairs(s)
n=fieldnames(s); a=cell(1,2*numel(n));
for k=1:numel(n), a{2*k-1}=n{k}; a{2*k}=s.(n{k}); end
end

function selected=manual_selection(eligible,o)
if ~isempty(o.CycleNumbers)
    selected=eligible;
    if ~strcmp(o.SelectionMode,'average') && numel(selected)~=1
        error('SPPv5:Selection','Single-cycle mode requires exactly one CycleNumbers entry.');
    end
elseif strcmp(o.SelectionMode,'single_middle')
    selected=eligible(1+floor((numel(eligible)-1)/2));
elseif strcmp(o.SelectionMode,'single_manual')
    error('SPPv5:Selection','single_manual requires one explicit CycleNumbers entry.');
else
    selected=eligible;
end
end

function [ev,ch]=cycle_descriptors(base,o)
a=base.analysis_cycle; c=base.cycles; raw=base.raw;
g=a.gamma_cycles; s=a.sigma_cycles; [N,C]=size(g);
phase=(0:N-1)'*2*pi/N; H=[sin(phase) cos(phase) ones(N,1)];
gb=H\g; strainamp=hypot(gb(1,:),gb(2,:)); psi=atan2(gb(2,:),gb(1,:));
orders=(1:o.HarmonicMaxOrder)';
sa=2/N*sin(phase*orders')'*s; co=2/N*cos(phase*orders')'*s;
ch=(sa+1i*co).*exp(-1i*orders*psi);
amp=abs(ch); hp=angle(ch)*180/pi;
duration=c.end_t-c.start_t; mid=(c.start_t+c.end_t)/2;
time=c.start_t'+(0:N-1)'/N*duration';
strainclose=abs(a.closure_difference(:,1))./max(strainamp',realmin);
stressrms=sqrt(mean((s-mean(s,1)).^2,1))';
stressclose=abs(a.closure_difference(:,2))./max(stressrms,realmin);
work=zeros(C,1); waveform=nan(C,1);
for k=1:C
    ix=find(raw.t>c.start_t(k) & raw.t<c.end_t(k));
    tq=[c.start_t(k);raw.t(ix);c.end_t(k)];
    % Use exactly the same local interpolant as the imported measured cycle.
    lo=max(1,find(raw.t<=tq(1),1,'last')-1);
    hi=min(numel(raw.t),find(raw.t>=tq(end),1,'first')+1);
    gq=interp1(raw.t(lo:hi),raw.gamma(lo:hi),tq,'pchip');
    sq=interp1(raw.t(lo:hi),raw.sigma(lo:hi),tq,'pchip');
    work(k)=sum((sq(1:end-1)+sq(2:end))/2.*diff(gq));
    if k>1 && contiguous(c,k-1,k)
        waveform(k)=sqrt(mean((s(:,k)-s(:,k-1)).^2))/max(mean(stressrms(k-1:k)),realmin);
    end
end
CycleIndex=(1:C)'; OriginalCycleLabel=c.expected_cycle_labels(:);
StartTime_s=c.start_t; EndTime_s=c.end_t; MidTime_s=mid;
ElapsedTime_s=mid-c.start_t(1); Period_s=duration;
StrainAmplitude=strainamp'; StrainPercent=100*StrainAmplitude;
StressPeakPositive_Pa=max(s,[],1)'; StressPeakNegative_Pa=min(s,[],1)';
G1Storage_Pa=real(ch(1,:))'./max(StrainAmplitude,realmin);
G1Loss_Pa=imag(ch(1,:))'./max(StrainAmplitude,realmin);
I1_Pa=amp(1,:)'; I2_Pa=amp(2,:)'; I3_Pa=amp(3,:)';
I5_Pa=amp(5,:)'; I7_Pa=amp(7,:)';
I2I1=I2_Pa./max(I1_Pa,realmin); I3I1=I3_Pa./max(I1_Pa,realmin);
I5I1=I5_Pa./max(I1_Pa,realmin); I7I1=I7_Pa./max(I1_Pa,realmin);
Phase2_deg=hp(2,:)'; Phase3_deg=hp(3,:)'; Phase5_deg=hp(5,:)'; Phase7_deg=hp(7,:)';
WorkInput_J_m3=work; StrainClosureRelative=strainclose; StressClosureRelative=stressclose;
StrainFitNRMSE=a.strain_sine_nrmse_by_cycle'; WaveformChangeRelative=waveform;
Included=false(C,1); InAverage=false(C,1); ValidSPPFraction=nan(C,1);
ct=table(CycleIndex,OriginalCycleLabel,StartTime_s,EndTime_s,MidTime_s,ElapsedTime_s, ...
    Period_s,StrainAmplitude,StrainPercent,StressPeakPositive_Pa,StressPeakNegative_Pa, ...
    G1Storage_Pa,G1Loss_Pa,I1_Pa,I2_Pa,I3_Pa,I5_Pa,I7_Pa,I2I1,I3I1,I5I1,I7I1, ...
    Phase2_deg,Phase3_deg,Phase5_deg,Phase7_deg,WorkInput_J_m3,StrainClosureRelative, ...
    StressClosureRelative,StrainFitNRMSE,WaveformChangeRelative,Included,InAverage,ValidSPPFraction);
K=numel(orders);
CycleIndex=repelem((1:C)',K); OriginalCycleLabel=repelem(c.expected_cycle_labels(:),K);
MidTime_s=repelem(mid,K); ElapsedTime_s=repelem(mid-c.start_t(1),K);
Order=repmat(orders,C,1); SineCoefficient_Pa=real(ch(:)); CosineCoefficient_Pa=imag(ch(:));
Amplitude_Pa=amp(:); RelativeAmplitude=reshape(amp./max(amp(1,:),realmin),[],1);
Phase_deg=hp(:);
ht=table(CycleIndex,OriginalCycleLabel,MidTime_s,ElapsedTime_s,Order, ...
    SineCoefficient_Pa,CosineCoefficient_Pa,Amplitude_Pa,RelativeAmplitude,Phase_deg);
ev=struct('cycle_table',ct,'harmonics',ht,'phase',phase,'gamma',g,'sigma',s,'time',time, ...
    'Gt_storage',[],'Gt_loss',[],'valid',[],'sigma_d',[],'fit_condition',[], ...
    'fit_residual_rms',[],'gamma_used',[],'sigma_used',[],'gammadot',[],'x',[], ...
    'strain_fundamental_phase',psi(:),'stress_dc',mean(s,1)', ...
    'method','Per-cycle measured descriptors; continuous SPP is evaluated only in cycle_evolution mode.', ...
    'harmonic_convention','sigma=sum[a_n sin(n theta)+b_n cos(n theta)]; theta is phase relative to each measured strain fundamental; phase=atan2(b_n,a_n).', ...
    'harmonic_interpretation','For evolving or nonclosing cycles these are window-dependent descriptive Fourier coefficients, not steady-state harmonics.', ...
    'time_origin','ElapsedTime_s is measured from the first detected valid cycle start; it is not necessarily time since loading began.', ...
    'work_interpretation','WorkInput_J_m3 is measured integral(sigma dgamma) over the actual interval, including signed changes; it need not equal irreversible dissipation.');
end

function yes=contiguous(c,j,k)
tol=1e-7*max(1,median(c.end_t-c.start_t));
yes=(c.expected_cycle_labels(k)==c.expected_cycle_labels(j)+1) && abs(c.start_t(k)-c.end_t(j))<=tol;
end

function [tail,d]=find_stable_tail(ev,ch,eligible,o)
% Only suffixes ending at the FINAL eligible cycle can qualify. A gap or an
% explicitly omitted cycle splits the sequence; no suffix can cross it.
ct=ev.cycle_table; tail=[]; first=numel(eligible);
while first>1
    j=eligible(first-1); k=eligible(first);
    if k~=j+1 || ct.OriginalCycleLabel(k)~=ct.OriginalCycleLabel(j)+1 || ...
            abs(ct.StartTime_s(k)-ct.EndTime_s(j))>1e-7*max(1,median(ct.Period_s))
        break
    end
    first=first-1;
end
finalblock=eligible(first:end); candidates=struct([]);
for j=1:(numel(finalblock)-o.MinStableCycles+1)
    use=finalblock(j:end); m=stationarity_metrics(ev,ch,use,o);
    row=rmfield(m,{'harmonic_orders','harmonic_significant','harmonic_change_relative','harmonic_trend_relative'});
    row.FirstCycle=use(1); row.LastCycle=use(end); row.CycleCount=numel(use);
    if isempty(candidates), candidates=row;
    else, candidates(end+1)=orderfields(row,candidates(1)); end %#ok<AGROW>
    if isempty(tail) && m.pass, tail=use; end
end
if isempty(candidates)
    candidate_table=table();
else
    candidate_table=struct2table(candidates);
end
d=struct('tolerance',o.StationarityTolerance,'harmonic_tolerance',o.HarmonicStationarityTolerance, ...
    'minimum_cycles',o.MinStableCycles, ...
    'harmonic_floor_relative_to_I1',o.HarmonicFloor,'harmonic_orders',[2 3 5 7], ...
    'harmonic_floor_interpretation','Empirical significance screen, not an independently measured noise floor or harmonic truncation.', ...
    'final_contiguous_block',finalblock,'candidate_table',candidate_table, ...
    'eligible_metrics',stationarity_metrics(ev,ch,eligible,o),'selected_metrics',[], ...
    'best_candidate',[], ...
    'criterion','Bulk waveform/amplitude/period/closure changes must be <= tolerance. For n=2,3,5,7 with max cycle amplitude >= harmonic_floor*mean(I1), complex-coefficient range and total linear trend divided by max(mean harmonic amplitude,harmonic_floor*mean(I1)) must be <= harmonic_tolerance. These separate engineering limits are not noise estimates, CV limits or confidence intervals.', ...
    'interpretation','A passing observed suffix is stable within the stated tolerance and duration; it does not prove material equilibrium or independent repeatability.');
if ~isempty(tail), d.selected_metrics=stationarity_metrics(ev,ch,tail,o); end
if ~isempty(candidates)
    [~,best]=min([candidates.maximum_screen_ratio]); d.best_candidate=candidates(best);
end
end

function message=stationarity_failure_message(d)
if isempty(d.best_candidate)
    message=sprintf('Final contiguous eligible block has %d cycles; at least %d are required. No shorter fallback is used.',numel(d.final_contiguous_block),d.minimum_cycles);
else
    b=d.best_candidate;
    message=sprintf('Best tested final suffix, cycles %d-%d: worst screen is %s = %.4g, limit %.4g (%.2f times limit). Other failing metrics remain in selection.diagnostics.candidate_table.', ...
        b.FirstCycle,b.LastCycle,b.worst_metric,b.worst_value,b.worst_limit,b.maximum_screen_ratio);
end
end

function m=stationarity_metrics(ev,ch,use,o)
ct=ev.cycle_table; u=use(:)'; t=ct.MidTime_s(u); n=numel(u);
g=ev.gamma(:,u); s=ev.sigma(:,u);
ga=ct.StrainAmplitude(u); i1=ct.I1_Pa(u);
sr=sqrt(mean((s-mean(s,1)).^2,1));
gscale=max(mean(ga),realmin); sscale=max(mean(sr),realmin);
m=struct(); m.strain_amplitude_range=relative_range(ga,gscale);
m.stress_amplitude_range=relative_range(i1,max(mean(i1),realmin));
m.stress_rms_range=relative_range(sr,sscale);
m.period_range=relative_range(ct.Period_s(u),mean(ct.Period_s(u)));
m.strain_waveform_scatter=sqrt(mean(std(g,0,2).^2))/gscale;
m.stress_waveform_scatter=sqrt(mean(std(s,0,2).^2))/sscale;
m.strain_waveform_total_trend=total_trend(g,t)/gscale;
m.stress_waveform_total_trend=total_trend(s,t)/sscale;
m.strain_closure=max(ct.StrainClosureRelative(u));
m.stress_closure=max(ct.StressClosureRelative(u));
harm=[2 3 5 7]; hc=ch(harm,u); scale=mean(abs(hc),2);
significant=max(abs(hc),[],2)>=o.HarmonicFloor*max(mean(i1),realmin);
change=zeros(4,1); drift=zeros(4,1);
for k=1:4
    pairdist=abs(hc(k,:).'-hc(k,:));
    change(k)=max(pairdist,[],'all')/max(scale(k),o.HarmonicFloor*max(mean(i1),realmin));
    drift(k)=total_trend(hc(k,:),t)/max(scale(k),o.HarmonicFloor*max(mean(i1),realmin));
end
m.harmonic_orders=harm; m.harmonic_significant=significant';
m.harmonic_change_relative=change'; m.harmonic_trend_relative=drift';
if any(significant)
    m.max_significant_harmonic_change=max(change(significant));
    m.max_significant_harmonic_trend=max(drift(significant));
else
    m.max_significant_harmonic_change=0; m.max_significant_harmonic_trend=0;
end
delta=diff(u); lab=diff(ct.OriginalCycleLabel(u));
m.contiguous=all(delta==1) && all(lab==1);
scalar_names={'strain_amplitude_range','stress_amplitude_range','stress_rms_range', ...
    'period_range','strain_waveform_scatter','stress_waveform_scatter', ...
    'strain_waveform_total_trend','stress_waveform_total_trend','strain_closure', ...
    'stress_closure','max_significant_harmonic_change','max_significant_harmonic_trend'};
values=cellfun(@(f)m.(f),scalar_names);
limits=[repmat(o.StationarityTolerance,1,10) repmat(o.HarmonicStationarityTolerance,1,2)];
[m.maximum_screen_ratio,worst]=max(values./limits);
m.worst_metric=scalar_names{worst}; m.worst_value=values(worst); m.worst_limit=limits(worst);
m.pass=n>=o.MinStableCycles && m.contiguous && all(isfinite(values)) && all(values<=limits);
end

function z=relative_range(y,scale)
z=(max(y)-min(y))/max(scale,realmin);
end

function z=total_trend(y,t)
% Fitted change across the WHOLE window, not a per-cycle increment.
if numel(t)<2, z=0; return; end
tau=t(:)-mean(t); slope=y*tau/max(sum(tau.^2),realmin);
z=sqrt(mean(abs(slope).^2))*(max(t)-min(t));
end

function ev=continuous_spp(ev,eligible,omega,o,eff)
[N,C]=size(ev.gamma); empty=nan(N,C);
gp=empty; gpp=empty; sd=empty; cond=empty; res=empty; cr=empty;
gu=empty; su=empty; dg=empty; valid=false(N,C); blockid=zeros(C,1);
ct=ev.cycle_table; starts=[1 find(diff(eligible)~=1 | ...
    diff(ct.OriginalCycleLabel(eligible))'~=1 | ...
    abs(ct.StartTime_s(eligible(2:end))-ct.EndTime_s(eligible(1:end-1)))'>1e-7*max(1,median(ct.Period_s)))+1];
ends=[starts(2:end)-1 numel(eligible)];
h=(eff.SmoothWindow-1)/2; half=eff.FitHalfWindow;
for b=1:numel(starts)
    use=eligible(starts(b):ends(b)); blockid(use)=b;
    time=reshape(ev.time(:,use),[],1); g=reshape(ev.gamma(:,use),[],1); s=reshape(ev.sigma(:,use),[],1);
    L=numel(time); gs=nan(L,1); ss=gs; derivative=gs;
    for i=(h+1):(L-h)
        ix=i+(-h:h); tau=time(ix)-time(i); scale=max(abs(tau));
        V=(tau/scale).^(0:o.SmoothOrder);
        coeff=V\[g(ix) s(ix)];
        gs(i)=coeff(1,1); ss(i)=coeff(1,2); derivative(i)=coeff(2,1)/scale;
    end
    x=derivative/omega;
    [p,v,d,m,k,r,center]=continuous_planes(gs,x,ss,half,h,o);
    gp(:,use)=reshape(p,N,[]); gpp(:,use)=reshape(v,N,[]); sd(:,use)=reshape(d,N,[]);
    valid(:,use)=reshape(m,N,[]); cond(:,use)=reshape(k,N,[]);
    res(:,use)=reshape(r,N,[]); cr(:,use)=reshape(center,N,[]);
    gu(:,use)=reshape(gs,N,[]); su(:,use)=reshape(ss,N,[]); dg(:,use)=reshape(derivative,N,[]);
end
ev.Gt_storage=gp; ev.Gt_loss=gpp; ev.sigma_d=sd; ev.valid=valid;
ev.fit_condition=cond; ev.fit_residual_rms=res; ev.center_reconstruction_residual=cr;
ev.gamma_used=gu; ev.sigma_used=su; ev.gammadot=dg; ev.x=dg/omega;
ev.cycle_table.ValidSPPFraction(:)=NaN;
ev.cycle_table.ValidSPPFraction(eligible)=mean(valid(:,eligible),1)';
ev.contiguous_block=blockid;
ev.method='Nonwrapped continuous-time local polynomial smoothing and strain derivative; centered/scaled weighted SVD local-plane fit. Finite-window geometric descriptor.';
ev.effective_settings=struct('SmoothWindow',eff.SmoothWindow,'SmoothOrder',o.SmoothOrder, ...
    'FitHalfWindow',half,'omega_for_normalized_rate',omega, ...
    'strain_rate_method','local_polynomial_actual_time','context_cycles',eligible, ...
    'edge_mask_points_per_block',h+half,'uses_periodic_wrapping',false, ...
    'average_only_options_ignored',{{'StrainRateMode','DerivativeMode','FDOrder'}});
end

function [gp,gpp,sd,mask,conds,rmsres,centerres]=continuous_planes(g,x,s,half,h,o)
L=numel(g); gp=nan(L,1); gpp=gp; sd=gp; conds=gp; rmsres=gp; centerres=gp; mask=false(L,1);
off=(-half:half)';
if strcmp(o.FitWeighting,'uniform'), weights=ones(size(off)); else, weights=half+1-abs(off); end
weights=weights/sum(weights); sw=sqrt(weights);
for i=(h+half+1):(L-h-half)
    ix=i+off; Z=[g(ix) x(ix)]; mu=weights'*Z; Z=Z-mu;
    scale=sqrt(weights'*(Z.^2));
    if any(~isfinite(scale)) || any(scale<=realmin), continue; end
    A=[Z./scale ones(size(off))].*sw; [U,S,V]=svd(A,0); sv=diag(S);
    conds(i)=sv(1)/sv(end);
    if ~isfinite(conds(i)) || conds(i)>o.ConditionThreshold || sv(end)/sv(1)<=max(o.MaskThreshold,eps*max(size(A))), continue; end
    sy=s(ix); sy0=weights'*sy; coef=V*((U'*((sy-sy0).*sw))./sv);
    slope=coef(1:2)./scale'; intercept=sy0+coef(3)-mu*slope;
    if any(~isfinite([slope;intercept])), continue; end
    gp(i)=slope(1); gpp(i)=slope(2); sd(i)=intercept; mask(i)=true;
    r=sy-([g(ix) x(ix)]*slope+intercept);
    rmsres(i)=sqrt(sum(weights.*r.^2));
    centerres(i)=s(i)-(gp(i)*g(i)+gpp(i)*x(i)+sd(i));
end
end

function z=smoothing_sensitivity(input,av,opt)
N=av.settings.PointsPerCycle; w0=av.effective_settings.SmoothWindow;
windows=round(w0*[2/3 1 5/3]); windows=windows+mod(windows+1,2);
wmin=max(5,av.settings.SmoothOrder+2); wmin=wmin+mod(wmin+1,2);
wmax=N-1; wmax=wmax-mod(wmax+1,2);
windows=unique(max(wmin,min(wmax,windows))); K=numel(windows);
z=struct('windows',windows,'fractions',windows/N,'phase',av.proc.phase, ...
    'Gt_storage',nan(N,K),'Gt_loss',nan(N,K),'valid',false(N,K), ...
    'storage_rms_change',nan(1,K),'loss_rms_change',nan(1,K), ...
    'combined_rms_change',nan(1,K),'common_valid_fraction',nan(1,K), ...
    'reference_index',find(windows==w0,1));
for k=1:K
    if windows(k)==w0
        p=av.Gt_storage; v=av.Gt_loss; valid=av.proc.mask_valid;
    else
        opt.SmoothWindow=windows(k); opt.AssessWindowSensitivity=false;
        a=as_pairs(opt); r=spp_laos_from_periodic_data_v3(input,a{:});
        p=r.Gt_storage; v=r.Gt_loss; valid=r.proc.mask_valid;
    end
    common=valid & av.proc.mask_valid;
    z.Gt_storage(:,k)=p; z.Gt_loss(:,k)=v; z.valid(:,k)=valid;
    ep=sqrt(mean((p(common)-av.Gt_storage(common)).^2));
    ev=sqrt(mean((v(common)-av.Gt_loss(common)).^2));
    sp=sqrt(mean(av.Gt_storage(common).^2)); sv=sqrt(mean(av.Gt_loss(common).^2));
    z.storage_rms_change(k)=ep/max(sp,realmin); z.loss_rms_change(k)=ev/max(sv,realmin);
    z.combined_rms_change(k)=hypot(ep,ev)/max(hypot(sp,sv),realmin);
    z.common_valid_fraction(k)=mean(common);
end
end

function plot_v5(R)
ct=R.evolution.cycle_table; use=R.selection.eligible_cycles;
figure('Name','SPP LAOS v5 - cycle diagnostics','Color','w'); tiledlayout(2,2);
nexttile; plot(ct.ElapsedTime_s,ct.StrainPercent,'o-'); xlabel('Elapsed observed time (s)'); ylabel('Strain amplitude (%)');
nexttile; plot(ct.ElapsedTime_s,[ct.G1Storage_Pa ct.G1Loss_Pa],'o-'); xlabel('Elapsed observed time (s)'); ylabel('Fundamental modulus (Pa)'); legend('G1 storage','G1 loss');
nexttile; semilogy(ct.ElapsedTime_s,[ct.I2I1 ct.I3I1 ct.I5I1 ct.I7I1],'o-'); xlabel('Elapsed observed time (s)'); ylabel('Descriptive harmonic amplitude / I1'); legend('I2/I1','I3/I1','I5/I1','I7/I1');
nexttile;
if ~isempty(R.average)
    plot(R.average.Gt_storage,R.average.Gt_loss); title(R.selection.status,'Interpreter','none');
elseif ~isempty(R.evolution.Gt_storage)
    plot(R.evolution.Gt_storage(:,use),R.evolution.Gt_loss(:,use)); title('Measured cycle evolution');
else
    text(.05,.5,'No stable suffix: averaged SPP curve withheld.','Units','normalized');
end
xlabel('G_t storage (Pa)'); ylabel('G_t loss (Pa)');
end
