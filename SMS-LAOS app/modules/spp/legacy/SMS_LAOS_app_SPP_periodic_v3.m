function R = SMS_LAOS_app_SPP_periodic_v3(file_or_data, varargin)
%SMS_LAOS_APP_SPP_PERIODIC_V3 Periodic LAOS, with auditable local-plane SPP.
% R = SMS_LAOS_app_SPP_periodic_v3(D,'StrainUnit','percent');
% D has real vector fields t [s], gamma, sigma [Pa], or is a file path.
% Column indices always refer to the ORIGINAL file, including text columns.
%
% The estimator is a finite-window approximation to the SPP osculating plane:
% sigma ~= Gt_storage*gamma + Gt_loss*(gammadot/omega) + sigma_d.
% It uses centered/scaled weighted least squares (SVD), NOT normal equations.
% Computation uses N unique phase points on [0,2*pi); no ramp is subtracted.
% No automatic despiking or deletion of negative moduli is performed.
%
% Main options (name/value):
% TimeColumn/StrainColumn/StressColumn = 1/2/3; HeaderLines = 0 (auto header);
% Sheet = 1; Delimiter = '' (auto); StrainUnit = 'decimal' | 'percent';
% Omega = [] (refine FFT estimate) or positive frequency used to GUIDE cycle
% detection. Actual selected crossing intervals define R.period and R.omega.
% DetectCyclesFrom = 'gamma' | 'stress'; TrimCycles = [3 3];
% SelectionMode = 'average' | 'single_middle' | 'single_manual';
% CycleNumbers = [] (one number required for either single mode);
% PointsPerCycle = 1001; CycleTolerance = .15; MaxGapFactor = 5;
% SmoothFraction = .02 (FULL window / cycle); SmoothWindow = [] (override);
% SmoothOrder = 3; StrainRateMode = 'analytic_sine_fit' | 'numerical';
% DerivativeMode = 'finite_difference' | 'sgolay'; FDOrder = 3|5|7|9
% (FDOrder denotes stencil POINT COUNT, retained for v2 compatibility).
% FitWindowFraction = .015 (HALF window / cycle); FitHalfWindow = [] override;
% FitWeighting = 'triangular' | 'uniform'; ConditionThreshold = 1e6
% (condition of SCALED WEIGHTED DESIGN, not v2's unscaled normal matrix);
% MaskThreshold = 0 (optional minimum smallest/largest design singular value);
% MinStrainFitR2 = .99; MaxStrainFitNRMSE = .05; DuplicateTimePolicy='error'
% or 'mean'; StoreRaw=true; MakePlots=true; Verbose=true.
% AssessWindowSensitivity=true additionally fits 2/3 and 5/3 of the chosen
% half-window. A >20% combined-modulus RMS change raises a diagnostic warning
% (an engineering screening threshold, NOT a statistical confidence bound).
%
% Inspect R.quality.messages, R.proc.strain_fit_info, R.analysis_cycle,
% R.proc.fit_residual_rms and R.proc.fit_condition before interpretation.
% Averaging phase-aligns measured cycles; uncertainty among cycles is retained.

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
p.addParameter('TrimCycles',[3 3],@(x) isnumeric(x) && isreal(x) && numel(x)==2 && all(isfinite(x(:))) && all(x(:)>=0) && all(x(:)==fix(x(:))));
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
p.parse(varargin{:});
o = p.Results;
N = o.PointsPerCycle;
if isempty(o.FitHalfWindow), half = max(2,round(o.FitWindowFraction*N)); else, half = o.FitHalfWindow; end
if isempty(o.SmoothWindow)
    win = max(o.SmoothOrder+2,round(o.SmoothFraction*N));
    if mod(win,2)==0, win=win+1; end
else
    win = o.SmoothWindow;
end
if 2*half+1>=N || win>=N || win<=o.SmoothOrder
    error('SPPv3:Window','Fit/smoothing windows must be smaller than N; smoothing order must be smaller than its window.');
end

[t,g,s,import_info] = import_data(file_or_data,o);
if strcmpi(o.StrainUnit,'percent'), g=g/100; end
[t,g,s,clean_info] = clean_data(t,g,s,o);
if isempty(o.Omega)
    [omega_ref,freq_info] = refine_frequency(t,g);
else
    omega_ref=o.Omega;
    freq_info=struct('method','user_guide','omega',omega_ref);
end
if strcmpi(o.DetectCyclesFrom,'gamma'), ref=g; else, ref=s; end
cycles = find_cycles(t,ref,omega_ref,o);
selected = choose_cycles(cycles.n_cycles,o);
period = median(cycles.end_t(selected)-cycles.start_t(selected));
omega = 2*pi/period;
cycle = resample_cycles(t,g,s,cycles,selected,N,period);
phase = (0:N-1)'*2*pi/N;
tc = (0:N-1)'*period/N;
gs = periodic_sg(cycle.gamma,win,o.SmoothOrder,0,period/N);
ss = periodic_sg(cycle.sigma,win,o.SmoothOrder,0,period/N);
[gf,dgf,sine_info] = sine_fit(phase,gs,omega);
[~,~,raw_sine_info] = sine_fit(phase,cycle.gamma,omega);
sine_info.before_smoothing = raw_sine_info;
sine_info.harmonic_distortion_2_to_9 = strain_thd(phase,cycle.gamma);
switch lower(o.StrainRateMode)
    case 'analytic_sine_fit'
        gu=gf; dg=dgf;
    case 'numerical'
        gu=gs;
        if strcmpi(o.DerivativeMode,'sgolay')
            dg=periodic_sg(cycle.gamma,win,o.SmoothOrder,1,period/N);
        else
            dg=periodic_fd(gs,period/N,o.FDOrder);
        end
end
x = dg/omega;
[gp,gpp,sd,valid,condition,residual,center_residual] = plane_fit(gu,x,ss,half,o);
q = make_quality(cycle,cycles,selected,sine_info,valid,condition,residual,ss,omega,omega_ref,clean_info,o);
sensitivity=struct('half_window',{},'fraction',{},'Gt_storage',{},'Gt_loss',{}, ...
    'sigma_d',{},'valid_fraction',{},'common_valid_fraction',{},'combined_rms_change',{},'storage_rms_change',{},'loss_rms_change',{});
q.max_window_combined_rms_change=NaN;
if o.AssessWindowSensitivity
    windows=unique(max(2,min(floor((N-2)/2),round(half*[2/3 1 5/3]))));
    for k=1:numel(windows)
        if windows(k)==half, ap=gp; av=gpp; ad=sd; am=valid;
        else, [ap,av,ad,am]=plane_fit(gu,x,ss,windows(k),o); end
        common=valid&am;
        scale_p=sqrt(mean(gp(common).^2)); scale_v=sqrt(mean(gpp(common).^2));
        ep=sqrt(mean((ap(common)-gp(common)).^2)); ev=sqrt(mean((av(common)-gpp(common)).^2));
        sensitivity(k)=struct('half_window',windows(k),'fraction',windows(k)/N, ...
            'Gt_storage',ap,'Gt_loss',av,'sigma_d',ad,'valid_fraction',mean(am), ...
            'common_valid_fraction',mean(common),'combined_rms_change',hypot(ep,ev)/max(hypot(scale_p,scale_v),realmin), ...
            'storage_rms_change',ep/max(scale_p,realmin),'loss_rms_change',ev/max(scale_v,realmin));
    end
    q.max_window_combined_rms_change=max([sensitivity.combined_rms_change]);
    if q.max_window_combined_rms_change>.2
        q.messages{end+1}='Local moduli change by more than 20% RMS across nearby fit windows; sharp features are not robust to analysis scale.';
    end
    if any([sensitivity.common_valid_fraction]<.95)
        q.messages{end+1}='Window-sensitivity comparison has fewer than 95% common valid phase points.';
    end
    q.has_warnings=~isempty(q.messages);
end

R = struct();
R.version='3.0';
R.method='finite-window weighted local-plane approximation to SPP';
R.import_info=import_info;
R.cleaning=clean_info;
if o.StoreRaw, R.raw=struct('t',t,'gamma',g,'sigma',s); end
R.omega=omega; R.period=period; R.reference_omega=omega_ref;
R.frequency_info=freq_info;
R.cycles=cycles; R.selected_cycles=selected;
R.analysis_cycle=cycle;
R.proc=struct('t',tc,'t_norm',phase/(2*pi),'phase',phase, ...
    'gamma',gu,'gamma_raw_processed',gs,'sigma',ss,'gammadot',dg,'x',x, ...
    'strain_fit_info',sine_info,'mask_valid',valid,'fit_condition',condition, ...
    'fit_residual_rms',residual,'center_reconstruction_residual',center_residual);
R.proc.window_sensitivity=sensitivity;
R.Gt_storage=gp; R.Gt_loss=gpp; R.sigma_d=sd;
R.settings=o;
R.effective_settings=struct('FitHalfWindow',half,'FitWindowFraction',half/N, ...
    'SmoothWindow',win,'SmoothFraction',win/N,'endpoint_excluded',true);
R.quality=q;
if o.Verbose
    fprintf('SPP v3: %d valid cycles; selected %s; omega %.8g rad/s; %.1f%% valid phase points.\n',cycles.n_cycles,mat2str(selected),omega,100*q.valid_fraction);
    for k=1:numel(q.messages), warning('SPPv3:Quality','%s',q.messages{k}); end
end
if o.MakePlots, plot_result(R); end
end

function [t,g,s,info] = import_data(input,o)
info=struct('strain_unit_input',o.StrainUnit,'stress_unit','Pa','time_unit','s');
if isstruct(input) && isscalar(input)
    for name={'t','gamma','sigma'}
        if ~isfield(input,name{1}), error('SPPv3:Input','Input needs t, gamma and sigma.'); end
    end
    t=input.t; g=input.gamma; s=input.sigma;
    info.source='struct'; return
end
if ~(ischar(input) || (isstring(input) && isscalar(input)))
    error('SPPv3:Input','Input must be a scalar struct or a file path.');
end
path=char(input);
if ~isfile(path), error('SPPv3:Input','File does not exist: %s',path); end
[~,~,ext]=fileparts(path);
if any(strcmpi(ext,{'.xls','.xlsx'}))
    T=readcell(path,'Sheet',o.Sheet);
    if o.HeaderLines>0, T=T(o.HeaderLines+1:end,:); end
    cols=[o.TimeColumn o.StrainColumn o.StressColumn];
    if size(T,2)<max(cols), error('SPPv3:Columns','Requested column exceeds file width.'); end
    z=cell(1,3);
    for k=1:3, z{k}=numeric_column(T(:,cols(k))); end
    info.column_names={};
elseif any(strcmpi(ext,{'.dat','.txt','.csv','.tsv'}))
    args={'FileType','text','VariableNamingRule','preserve'};
    if ~isempty(o.Delimiter), args=[args {'Delimiter',o.Delimiter}]; end
    io=detectImportOptions(path,args{:});
    if o.HeaderLines>0, io.DataLines=[o.HeaderLines+1 Inf]; end
    T=readtable(path,io);
    cols=[o.TimeColumn o.StrainColumn o.StressColumn];
    if width(T)<max(cols), error('SPPv3:Columns','Requested column exceeds file width.'); end
    z=cell(1,3);
    for k=1:3, z{k}=numeric_column(T{:,cols(k)}); end
    info.column_names=T.Properties.VariableNames(cols);
else
    error('SPPv3:Input','Unsupported extension: %s',ext);
end
t=z{1}; g=z{2}; s=z{3};
info.source=path; info.columns=cols;
end

function y = numeric_column(x)
if isnumeric(x) || islogical(x), y=double(x); return; end
if iscell(x)
    y=nan(size(x));
    for k=1:numel(x)
        if isnumeric(x{k}) && isscalar(x{k}), y(k)=double(x{k});
        elseif ischar(x{k}) || (isstring(x{k}) && isscalar(x{k})), y(k)=str2double(x{k}); end
    end
else
    y=str2double(string(x));
end
end

function [t,g,s,info] = clean_data(t,g,s,o)
v={t,g,s};
for k=1:3
    if ~isnumeric(v{k}) || ~isreal(v{k}) || ~isvector(v{k})
        error('SPPv3:Input','t, gamma and sigma must be real numeric vectors.');
    end
end
if numel(t)~=numel(g) || numel(t)~=numel(s), error('SPPv3:Input','Input vectors must have equal lengths.'); end
t=double(t(:)); g=double(g(:)); s=double(s(:));
info.n_input=numel(t);
keep=isfinite(t)&isfinite(g)&isfinite(s);
info.nonfinite_rows_removed=sum(~keep);
t=t(keep); g=g(keep); s=s(keep);
info.sorted=any(diff(t)<0);
[t,ix]=sort(t); g=g(ix); s=s(ix);
info.duplicate_rows=numel(t)-numel(unique(t));
if info.duplicate_rows>0
    if strcmpi(o.DuplicateTimePolicy,'error')
        error('SPPv3:DuplicateTime','Duplicate timestamps found; inspect data or explicitly set DuplicateTimePolicy to mean.');
    end
    [t,~,group]=unique(t); g=accumarray(group,g,[],@mean); s=accumarray(group,s,[],@mean);
end
if numel(t)<20 || any(diff(t)<=0), error('SPPv3:Input','Need at least 20 distinct increasing timestamps.'); end
info.n_clean=numel(t); info.median_dt=median(diff(t));
info.relative_dt_spread=max(abs(diff(t)-info.median_dt))/info.median_dt;
info.large_gap_count=sum(diff(t)>o.MaxGapFactor*info.median_dt);
if max(g)-min(g)<=eps(max(1,max(abs(g))))
    error('SPPv3:NoStrain','Strain has no resolvable oscillation.');
end
end

function [omega,info] = refine_frequency(t,y)
% Central record avoids the common first-cycle amplitude transition.
n=numel(t); lo=max(1,floor(.1*n)); hi=min(n,ceil(.9*n));
tt=t(lo:hi)-t(lo); yy=y(lo:hi);
nu=min(16384,numel(tt)); tu=linspace(0,tt(end),nu)';
yu=interp1(tt,yy,tu,'linear'); yu=yu-mean(yu);
Y=fft(yu); P=abs(Y(2:floor(nu/2))).^2;
[pk,ii]=max(P);
if isempty(ii) || pk<=0, error('SPPv3:Frequency','Cannot identify a periodic strain signal.'); end
df=1/(nu*(tu(2)-tu(1))); f0=ii*df;
% Bounded continuous-frequency least squares refines FFT-bin quantization.
ns=min(4096,numel(tt)); ix=unique(round(linspace(1,numel(tt),ns)));
tf=tt(ix); yf=yy(ix);
fun=@(w) sine_sse(w,tf,yf);
lower=2*pi*max(df*.2,f0-.75*df); upper=2*pi*(f0+.75*df);
[omega,sse]=fminbnd(fun,lower,upper,optimset('TolX',1e-10,'Display','off'));
info=struct('method','central-record FFT plus sine least-squares refinement', ...
    'fft_omega',2*pi*f0,'omega',omega,'sse',sse,'resampled_for_fft',true);
end

function val = sine_sse(w,t,y)
X=[sin(w*t) cos(w*t) ones(size(t))]; b=X\y;
val=sum((y-X*b).^2);
end

function c = find_cycles(t,y,w,o)
T=2*pi/w; dt=median(diff(t)); tr=t-t(1);
% Phase-guided assignment resolves noisy recrossings without joining gaps.
sel=unique(round(linspace(max(1,round(.1*numel(t))),round(.9*numel(t)),min(4096,numel(t)))));
X=[sin(w*tr(sel)) cos(w*tr(sel)) ones(numel(sel),1)]; b=X\y(sel);
phase=atan2(b(2),b(1));
win=max(5,2*floor(.03*T/dt/2)+1); win=min(win,2*floor((numel(y)-1)/2)+1);
coef=sg_kernel(win,3,0,dt);
ys=conv(y,flipud(coef),'same')-b(3);
ix=find(ys(1:end-1)<=0 & ys(2:end)>0);
ct=t(ix)-ys(ix).*(t(ix+1)-t(ix))./(ys(ix+1)-ys(ix));
% Ignore only filter-padding edge contamination, not complete interior cycles.
ct=ct(ct>=t(1)+win*dt/2 & ct<=t(end)-win*dt/2);
k0=ceil((phase)/ (2*pi)); k1=floor((w*tr(end)+phase)/(2*pi));
labels=(k0:k1)'; target=t(1)+(2*pi*labels-phase)/w;
assigned=nan(size(target));
for k=1:numel(target)
    cand=find(abs(ct-target(k))<=.2*T);
    if ~isempty(cand), [~,j]=min(abs(ct(cand)-target(k))); assigned(k)=ct(cand(j)); end
end
start=assigned(1:end-1); finish=assigned(2:end);
duration=finish-start;
valid=isfinite(start)&isfinite(finish)&abs(duration/T-1)<=o.CycleTolerance;
gaps=find(diff(t)>o.MaxGapFactor*dt);
for k=find(valid)'
    if any(t(gaps)<finish(k) & t(gaps+1)>start(k)), valid(k)=false; end
end
if ~any(valid), error('SPPv3:Cycles','No complete valid cycles; inspect frequency, signal and timestamp gaps.'); end
c=struct('start_t',start(valid),'end_t',finish(valid), ...
    'n_cycles',sum(valid),'expected_cycle_labels',labels(valid), ...
    'candidate_start_t',start,'candidate_end_t',finish,'candidate_valid',valid, ...
    'crossings',ct,'reference_period',T,'detection_smooth_window',win);
c.start_idx=arrayfun(@(a) find(t>=a,1,'first'),c.start_t);
c.end_idx=arrayfun(@(a) find(t<=a,1,'last'),c.end_t);
end

function chosen = choose_cycles(n,o)
if ~isempty(o.CycleNumbers)
    chosen=unique(o.CycleNumbers(:)');
    if any(chosen>n), error('SPPv3:Selection','CycleNumbers exceed detected cycle count.'); end
    if ~strcmpi(o.SelectionMode,'average') && numel(chosen)~=1
        error('SPPv3:Selection','Single-cycle mode requires exactly one CycleNumbers entry.');
    end
    return
end
first=1+o.TrimCycles(1); last=n-o.TrimCycles(2);
if last<first, error('SPPv3:Selection','TrimCycles removed all complete cycles.'); end
switch lower(o.SelectionMode)
    case 'average', chosen=first:last;
    case 'single_middle', chosen=first+floor((last-first)/2);
    otherwise, error('SPPv3:Selection','single_manual requires one CycleNumbers entry.');
end
end

function a = resample_cycles(t,g,s,c,chosen,N,period)
u=(0:N)'/N; m=numel(chosen);
gm=zeros(N,m); sm=zeros(N,m); closure=zeros(m,2);
for k=1:m
    j=chosen(k); tq=c.start_t(j)+u*(c.end_t(j)-c.start_t(j));
    lo=max(1,find(t<=tq(1),1,'last')-1); hi=min(numel(t),find(t>=tq(end),1,'first')+1);
    gq=interp1(t(lo:hi),g(lo:hi),tq,'pchip'); sq=interp1(t(lo:hi),s(lo:hi),tq,'pchip');
    gm(:,k)=gq(1:N); sm(:,k)=sq(1:N);
    closure(k,:)=[gq(end)-gq(1) sq(end)-sq(1)];
end
ph=(0:N-1)'*2*pi/N; H=[sin(ph) cos(ph) ones(N,1)];
gb=H\gm; sb=H\sm;
gamp=hypot(gb(1,:),gb(2,:));
cycle_sine_nrmse=sqrt(mean((gm-H*gb).^2,1))./max(gamp,realmin);
a=struct('t',(0:N-1)'*period/N,'phase',ph,'gamma',mean(gm,2), ...
    'sigma',mean(sm,2),'gamma_cycles',gm,'sigma_cycles',sm, ...
    'gamma_std',std(gm,0,2),'sigma_std',std(sm,0,2),'mode','phase_average', ...
    'periods',c.end_t(chosen)-c.start_t(chosen),'closure_difference',closure, ...
    'strain_amplitudes',gamp,'strain_sine_nrmse_by_cycle',cycle_sine_nrmse, ...
    'stress_first_harmonic_amplitudes',hypot(sb(1,:),sb(2,:)), ...
    'stress_rms_by_cycle',sqrt(mean((sm-mean(sm,1)).^2,1)));
if m==1, a.mode='single'; end
end

function k = sg_kernel(win,ord,derivative,dt)
h=(win-1)/2; z=(-h:h)'/h; V=z.^(0:ord);
P=pinv(V);
k=P(derivative+1,:)'*factorial(derivative)/(h*dt)^derivative;
end

function y = periodic_sg(x,win,ord,derivative,dt)
h=(win-1)/2; k=sg_kernel(win,ord,derivative,dt);
xx=[x(end-h+1:end);x;x(1:h)];
y=conv(xx,flipud(k),'valid');
end

function d = periodic_fd(x,dt,points)
h=(points-1)/2; z=(-h:h)';
V=z.^(0:points-1); rhs=zeros(points,1); rhs(2)=1;
coef=V'\rhs;
d=zeros(size(x));
for j=1:points, d=d+coef(j)*circshift(x,-z(j))/dt; end
end

function [f,df,info] = sine_fit(ph,y,w)
H=[sin(ph) cos(ph) ones(size(ph))]; b=H\y;
f=H*b; df=w*(b(1)*cos(ph)-b(2)*sin(ph));
res=y-f; sst=sum((y-mean(y)).^2); amp=hypot(b(1),b(2));
info=struct('method','analytic_sine_fit','A',b(1),'B',b(2),'C',b(3), ...
    'amplitude',amp,'phase',atan2(b(2),b(1)),'r2',1-sum(res.^2)/max(sst,realmin), ...
    'nrmse',sqrt(mean(res.^2))/max(amp,realmin),'residual',res);
end

function ratio = strain_thd(ph,g)
H=ones(numel(ph),19);
for k=1:9, H(:,2*k)=sin(k*ph); H(:,2*k+1)=cos(k*ph); end
b=H\g;
ratio=sqrt(sum(b(4:end).^2))/max(hypot(b(2),b(3)),realmin);
end

function [gp,gpp,sd,mask,conds,rmsres,centerres] = plane_fit(g,x,s,half,o)
N=numel(g); gp=nan(N,1); gpp=gp; sd=gp; conds=gp; rmsres=gp; centerres=gp; mask=false(N,1);
off=(-half:half)';
if strcmpi(o.FitWeighting,'uniform'), weights=ones(size(off)); else, weights=half+1-abs(off); end
weights=weights/sum(weights); sw=sqrt(weights);
for i=1:N
    ix=mod(i-1+off,N)+1;
    Z=[g(ix) x(ix)]; mu=weights'*Z; Z=Z-mu;
    scale=sqrt(weights'*(Z.^2));
    if any(~isfinite(scale)) || any(scale<=realmin), continue; end
    A=[Z./scale ones(size(off))].*sw;
    [U,S,V]=svd(A,0); sv=diag(S);
    conds(i)=sv(1)/sv(end);
    if ~isfinite(conds(i)) || conds(i)>o.ConditionThreshold || sv(end)/sv(1)<=max(o.MaskThreshold,eps*max(size(A)))
        continue
    end
    sy=s(ix); sy0=weights'*sy;
    b=V*((U'*((sy-sy0).*sw))./sv);
    slope=b(1:2)./scale'; intercept=sy0+b(3)-mu*slope;
    if any(~isfinite([slope;intercept])), continue; end
    gp(i)=slope(1); gpp(i)=slope(2); sd(i)=intercept; mask(i)=true;
    r=sy-([g(ix) x(ix)]*slope+intercept);
    rmsres(i)=sqrt(sum(weights.*r.^2));
    centerres(i)=s(i)-(gp(i)*g(i)+gpp(i)*x(i)+sd(i));
end
end

function q = make_quality(a,c,chosen,fit,valid,conds,residual,s,w,wref,clean,o)
q=struct(); q.valid_fraction=mean(valid);
q.median_scaled_design_condition=median(conds(valid),'omitnan');
q.strain_amplitude_cv=std(a.strain_amplitudes)/max(mean(a.strain_amplitudes),realmin);
q.stress_rms_cv=std(a.stress_rms_by_cycle)/max(mean(a.stress_rms_by_cycle),realmin);
q.period_cv=std(a.periods)/mean(a.periods);
q.strain_closure_relative=max(abs(a.closure_difference(:,1)))/max(mean(a.strain_amplitudes),realmin);
q.stress_closure_relative=max(abs(a.closure_difference(:,2)))/max(mean(a.stress_rms_by_cycle),realmin);
q.mean_cycle_stress_variation_rms=sqrt(mean(a.sigma_std.^2))/max(sqrt(mean((s-mean(s)).^2)),realmin);
q.local_fit_residual_relative=sqrt(mean(residual(valid).^2))/max(sqrt(mean((s-mean(s)).^2)),realmin);
q.max_cycle_strain_sine_nrmse=max(a.strain_sine_nrmse_by_cycle);
q.strain_sine_acceptable=fit.r2>=o.MinStrainFitR2 && fit.before_smoothing.nrmse<=o.MaxStrainFitNRMSE && q.max_cycle_strain_sine_nrmse<=o.MaxStrainFitNRMSE;
nedge=max(1,min(3,floor(numel(chosen)/2)));
v=a.stress_first_harmonic_amplitudes;
q.stress_harmonic_drift_relative=(mean(v(end-nedge+1:end))-mean(v(1:nedge)))/max(mean(v),realmin);
q.frequency_relative_change=w/wref-1;
q.rejected_candidate_cycles=sum(~c.candidate_valid);
q.n_selected=numel(chosen); q.messages={};
if ~q.strain_sine_acceptable, q.messages{end+1}='Measured strain does not meet sine-fit quality criteria; inspect residuals before using analytic strain rate.'; end
if q.valid_fraction<.95, q.messages{end+1}='Fewer than 95% of phase points have an identifiable local plane.'; end
if q.strain_amplitude_cv>.05 || q.stress_rms_cv>.05 || q.mean_cycle_stress_variation_rms>.05
    q.messages{end+1}='Selected cycles differ by more than 5%; inspect stationarity before phase averaging.';
end
if q.stress_closure_relative>.05, q.messages{end+1}='Measured endpoint stress mismatch exceeds 5% of cycle RMS; no closure ramp was applied.'; end
if q.strain_closure_relative>.05, q.messages{end+1}='Measured endpoint strain mismatch exceeds 5% of strain amplitude; inspect cycle boundaries and numerical derivative seams.'; end
if q.period_cv>.02, q.messages{end+1}='Selected cycle periods vary by more than 2%; phase averaging uses a representative median period.'; end
if abs(q.frequency_relative_change)>.02, q.messages{end+1}='Selected measured frequency differs from the guide frequency by more than 2%.'; end
if clean.sorted, q.messages{end+1}='Input timestamps were sorted; confirm this is one continuous acquisition.'; end
if clean.nonfinite_rows_removed>0, q.messages{end+1}=sprintf('%d nonfinite rows were excluded.',clean.nonfinite_rows_removed); end
if clean.duplicate_rows>0, q.messages{end+1}=sprintf('%d duplicate timestamp rows were explicitly averaged.',clean.duplicate_rows); end
if clean.large_gap_count>0, q.messages{end+1}='Timestamp gaps were found; cycles overlapping large gaps were rejected.'; end
q.has_warnings=~isempty(q.messages);
q.interpretation='Local-plane validity is numerical; it does not establish physical accuracy or window independence.';
end

function plot_result(R)
ph=R.proc.t_norm; g=R.proc.gamma; s=R.proc.sigma;
figure('Name','SPP LAOS v3 - signal and quality','Color','w');
tiledlayout(3,2);
nexttile; plot(ph,R.analysis_cycle.gamma,'Color',[.65 .65 .65]); hold on; plot(ph,g,'b'); xlabel('Cycle phase'); ylabel('Strain'); legend('Measured average','Used for fit');
nexttile; plot(ph,R.analysis_cycle.sigma_cycles,'Color',[.8 .8 .8]); hold on; plot(ph,s,'k','LineWidth',1.2); xlabel('Cycle phase'); ylabel('Stress (Pa)');
nexttile; plot(ph,R.Gt_storage,ph,R.Gt_loss); xlabel('Cycle phase'); ylabel('Transient modulus (Pa)'); legend('G_t storage','G_t loss');
nexttile; plot(ph,R.sigma_d); xlabel('Cycle phase'); ylabel('Displacement stress (Pa)');
nexttile; plot(R.Gt_storage,R.Gt_loss); xlabel('G_t storage (Pa)'); ylabel('G_t loss (Pa)'); title('Cole-Cole');
nexttile; semilogy(ph,R.proc.fit_condition); xlabel('Cycle phase'); ylabel('Scaled design condition');
figure('Name','SPP LAOS v3 - Lissajous','Color','w'); tiledlayout(1,2);
nexttile; scatter(g,s,12,R.Gt_storage,'filled'); xlabel('Strain'); ylabel('Stress (Pa)'); colorbar; title('Colour: G_t storage (Pa)');
nexttile; scatter(R.proc.x,s,12,R.Gt_loss,'filled'); xlabel('Strain rate / omega'); ylabel('Stress (Pa)'); colorbar; title('Colour: G_t loss (Pa)');
end
