function out = sms_laos_core_v2(data, cycle_selection_mode, remove_first_cycles, remove_last_cycles, ...
    last_n_cycles, strain_is_percent, use_freq_range, freq_min, freq_max, use_alternating_odd_sign)

    % -------- Raw data --------
    time_raw   = data(:,1);
    strain_raw = data(:,2);
    stress_raw = data(:,3);

    if strain_is_percent
        strain_raw = strain_raw / 100;
    end

    strain_raw_plot = strain_raw;
    stress_raw_plot = stress_raw;

    % Remove DC offset for analysis
    strain_raw = strain_raw - mean(strain_raw);
    stress_raw = stress_raw - mean(stress_raw);

    % -------- Sampling info --------
    dt_raw = mean(diff(time_raw));
    Fs_raw = 1 / dt_raw;
    N_raw = length(time_raw);

    if N_raw < 10
        error('Too few raw data points.');
    end

    % -------- Frequency detection from raw strain --------
    strain_fft_raw = fft(strain_raw);
    freqs_raw = (0:N_raw-1) * (Fs_raw / N_raw);

    halfN = floor(N_raw/2);
    freqs_pos = freqs_raw(2:halfN);
    amp_pos = abs(strain_fft_raw(2:halfN));

    if isempty(freqs_pos)
        error('Frequency detection failed: empty positive frequency range.');
    end

    if use_freq_range
        valid_idx = (freqs_pos >= freq_min) & (freqs_pos <= freq_max);

        if ~any(valid_idx)
            error('No frequencies found inside the specified search range.');
        end

        freqs_search = freqs_pos(valid_idx);
        amp_search = amp_pos(valid_idx);
        [~, idx_max] = max(amp_search);
        freq_hz = freqs_search(idx_max);
    else
        [~, idx_max] = max(amp_pos);
        freq_hz = freqs_pos(idx_max);
    end

    if isempty(freq_hz) || freq_hz <= 0
        error('Invalid detected frequency.');
    end

    omega = 2*pi*freq_hz;
    T_period = 1 / freq_hz;

    % -------- Cycle selection --------
    switch lower(cycle_selection_mode)
        case 'trim_ends'
            t_start_use = time_raw(1) + remove_first_cycles * T_period;
            t_end_limit = time_raw(end) - remove_last_cycles * T_period;

            if t_end_limit <= t_start_use
                error('Not enough signal left after removing first/last cycles.');
            end

            usable_duration = t_end_limit - t_start_use;
            n_cycles_available = floor(usable_duration / T_period);

            if n_cycles_available < 1
                error('No complete cycles remain in the middle section.');
            end

            t_end_use = t_start_use + n_cycles_available * T_period;
            idx_keep = (time_raw >= t_start_use) & (time_raw < t_end_use);

        case 'last_n_cycles'
            total_duration = time_raw(end) - time_raw(1);
            total_cycles_available = floor(total_duration / T_period);

            if total_cycles_available < last_n_cycles
                error('Not enough cycles in the signal to extract the requested last_n_cycles.');
            end

            t_end_use = time_raw(end);
            t_start_use = t_end_use - last_n_cycles * T_period;
            idx_keep = (time_raw >= t_start_use) & (time_raw <= t_end_use);
            n_cycles_available = last_n_cycles;

        otherwise
            error('Unknown cycle_selection_mode. Use ''trim_ends'' or ''last_n_cycles''.');
    end

    time = time_raw(idx_keep);
    strain = strain_raw(idx_keep);
    stress = stress_raw(idx_keep);

    if numel(time) < 10
        error('Too few points after cycle selection.');
    end

    % Re-zero time
    time = time - time(1);

    % Remove mean again after cropping
    strain = strain - mean(strain);
    stress = stress - mean(stress);

    % -------- FFT on selected cycles --------
    N = length(time);
    dt = mean(diff(time));
    Fs = 1 / dt;

    strain_fft = fft(strain);
    stress_fft = fft(stress);
    freqs = (0:N-1) * (Fs / N);

    [~, idx1] = min(abs(freqs - freq_hz));
    [~, idx3] = min(abs(freqs - 3*freq_hz));

    % -------- Harmonic amplitudes --------
    I1 = 2 * abs(stress_fft(idx1)) / N;
    I3 = 2 * abs(stress_fft(idx3)) / N;
    gamma0 = 2 * abs(strain_fft(idx1)) / N;

    if gamma0 == 0
        error('gamma0 is zero. Check strain signal.');
    end

    if I1 ~= 0
        I3_I1 = I3 / I1;
    else
        I3_I1 = NaN;
    end

    % -------- Phase differences --------
    phi_stress_1 = angle(stress_fft(idx1));
    phi_stress_3 = angle(stress_fft(idx3));
    phi_strain_1 = angle(strain_fft(idx1));

    delta1 = phi_stress_1 - phi_strain_1;
    delta3 = phi_stress_3 - 3*phi_strain_1;

    delta1 = atan2(sin(delta1), cos(delta1));
    delta3 = atan2(sin(delta3), cos(delta3));

    % -------- Fourier coefficients, raw --------
    Gp1  = (I1/gamma0) * cos(delta1);
    Gpp1 = (I1/gamma0) * sin(delta1);

    Gp3  = (I3/gamma0) * cos(delta3);
    Gpp3 = (I3/gamma0) * sin(delta3);

    % -------- Optional alternating odd-harmonic prefactor --------
    if use_alternating_odd_sign
        sign1 = (-1)^((1-1)/2);   % +1
        sign3 = (-1)^((3-1)/2);   % -1
    else
        sign1 = 1;
        sign3 = 1;
    end

    Gp1  = sign1 * Gp1;
    Gpp1 = sign1 * Gpp1;
    Gp3  = sign3 * Gp3;
    Gpp3 = sign3 * Gpp3;

    % -------- Chebyshev coefficients, keep user's convention --------
    e1 = Gp1;
    v1 = Gpp1 / omega;

    e3 = -Gp3;
    v3 =  Gpp3 / omega;

    if e1 ~= 0
        e3_e1 = e3 / e1;
    else
        e3_e1 = NaN;
    end

    if v1 ~= 0
        v3_v1 = v3 / v1;
    else
        v3_v1 = NaN;
    end

    % -------- SMS-LAOS intracycle measures --------
    G_M_prime = e1 - 3*e3;
    G_L_prime = e1 + e3;

    eta_M_prime = v1 - 3*v3;
    eta_L_prime = v1 + v3;

    if G_L_prime ~= 0
        S = (G_L_prime - G_M_prime) / G_L_prime;
    else
        S = NaN;
    end

    if eta_L_prime ~= 0
        T = (eta_L_prime - eta_M_prime) / eta_L_prime;
    else
        T = NaN;
    end

    % -------- Elastic / viscous Lissajous decomposition --------
    % This uses the first + third Chebyshev terms calculated above.
    %
    % Elastic:
    %   sigma_elastic = gamma0 * [e1*T1(x) + e3*T3(x)]
    %   x = strain/gamma0
    %
    % Viscous:
    %   sigma_viscous = gamma0*omega * [v1*T1(y) + v3*T3(y)]
    %   y = strain_rate/(omega*gamma0)

    gammadot = gradient(strain, time);

    x_cheb = strain / gamma0;
    y_cheb = gammadot / (omega * gamma0);

    % Limit small numerical overshoot/noise outside [-1, 1].
    x_cheb = max(min(x_cheb, 1), -1);
    y_cheb = max(min(y_cheb, 1), -1);

    T1x = x_cheb;
    T3x = 4*x_cheb.^3 - 3*x_cheb;

    T1y = y_cheb;
    T3y = 4*y_cheb.^3 - 3*y_cheb;

    stress_elastic = gamma0 * (e1*T1x + e3*T3x);
    stress_viscous = gamma0 * omega * (v1*T1y + v3*T3y);

    stress_reconstructed = stress_elastic + stress_viscous;
    stress_residual = stress - stress_reconstructed;

    gammadot_over_omega = gammadot / omega;

    residual_rms = sqrt(mean(stress_residual.^2));

    if I1 ~= 0
        residual_rms_over_I1 = residual_rms / I1;
    else
        residual_rms_over_I1 = NaN;
    end

    % -------- FFT data for plotting --------
    halfN2 = floor(N/2);
    freqs_plot = freqs(1:halfN2);
    strain_amp_plot = 2 * abs(strain_fft(1:halfN2)) / N;
    stress_amp_plot = 2 * abs(stress_fft(1:halfN2)) / N;

    % -------- Output --------
    out = struct();

    out.time_raw = time_raw;
    out.strain_raw = strain_raw_plot;
    out.stress_raw = stress_raw_plot;

    out.selected_mask = idx_keep;
    out.t_start_use = t_start_use;
    out.t_end_use = t_end_use;

    out.time = time;
    out.strain = strain;
    out.stress = stress;

    out.gammadot = gammadot;
    out.gammadot_over_omega = gammadot_over_omega;

    out.x_cheb = x_cheb;
    out.y_cheb = y_cheb;

    out.stress_elastic = stress_elastic;
    out.stress_viscous = stress_viscous;
    out.stress_reconstructed = stress_reconstructed;
    out.stress_residual = stress_residual;

    out.residual_rms = residual_rms;
    out.residual_rms_over_I1 = residual_rms_over_I1;

    out.freq_hz = freq_hz;
    out.omega = omega;
    out.period = T_period;
    out.n_cycles_used = n_cycles_available;

    out.I1 = I1;
    out.I3 = I3;
    out.I3_I1 = I3_I1;
    out.gamma0 = gamma0;

    out.delta1 = delta1;
    out.delta3 = delta3;

    out.Gp1 = Gp1;
    out.Gpp1 = Gpp1;
    out.Gp3 = Gp3;
    out.Gpp3 = Gpp3;

    out.e1 = e1;
    out.v1 = v1;
    out.e3 = e3;
    out.v3 = v3;

    out.e3_e1 = e3_e1;
    out.v3_v1 = v3_v1;

    out.G_M_prime = G_M_prime;
    out.G_L_prime = G_L_prime;
    out.S = S;

    out.eta_M_prime = eta_M_prime;
    out.eta_L_prime = eta_L_prime;
    out.T = T;

    out.freqs_plot = freqs_plot;
    out.strain_amp_plot = strain_amp_plot;
    out.stress_amp_plot = stress_amp_plot;
end

