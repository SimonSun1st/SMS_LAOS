% =========================================================================
% SMS-LAOS Rheology Analysis Script
% Full script with FAST MODE + GM/GL/S + etaM/etaL/T
% Applies alternating odd-harmonic prefactor to G'3 and G''3
% while KEEPING the user's convention:
%   e3 = -Gp3
%   v3 =  Gpp3 / omega
% Copyright (c) 2026 Yuchen Sun
% All rights reserved.
%
% This code is provided for viewing and academic reference only.
% No reuse, redistribution, modification, or commercial use is permitted without prior written permission from the author.
% =========================================================================
% FAST MODE:
%   fast_mode = true
%   - no plots saved
%   - no .fig saved
%   - no selected-cycle csv saved
%   - only one result csv saved
%
% FULL MODE:
%   fast_mode = false
%   - save png plots
%   - save fig files
%   - save selected-cycle csv
%   - save xlsx + csv
%
% INPUT:
%   Reads only *.dat files
%
% OUTPUT:
%   Never writes *.dat
%   Writes only .csv / .xlsx / .png / .fig
%
% CYCLE SELECTION MODES:
%   'trim_ends'    -> remove first N and last M cycles, keep middle complete cycles
%   'last_n_cycles'-> keep only the last N complete cycles
% =========================================================================

clear; clc; close all;
set(0, 'DefaultFigureVisible', 'off');

%% ========================= USER SETTINGS ================================
folder_path = 'folderpath';
file_list = dir(fullfile(folder_path, '*.dat'));

if isempty(file_list)
    error('No .dat files found in the specified folder.');
end

% ---- Speed control ----
fast_mode = false;

% ---- Cycle selection mode ----
% Options:
%   'trim_ends'
%   'last_n_cycles'
cycle_selection_mode = 'trim_ends';

% For 'trim_ends'
remove_first_cycles = 3;
remove_last_cycles  = 3;

% For 'last_n_cycles'
last_n_cycles = 5;

% If strain column is in percent (e.g. 50 means 50%), set true
% If strain column is already decimal (e.g. 0.5 means 50%), set false
strain_is_percent = false;

% Optional frequency search range (Hz)
use_freq_range = false;
freq_min = 0.01;
freq_max = 10;

% Apply alternating odd-harmonic sign prefactor at Fourier coefficient level:
% sign_n = (-1)^((n-1)/2) for odd n
% n = 1 -> +1, n = 3 -> -1
use_alternating_odd_sign = true;

% ---- Settings controlled by fast_mode ----
if fast_mode
    save_plots = false;
    save_fig_files = false;
    save_selected_data_csv = false;
    save_excel = false;
    save_csv = true;
else
    save_plots = true;
    save_fig_files = true;
    save_selected_data_csv = true;
    save_excel = true;
    save_csv = true;
end

% Output folders
plot_folder = fullfile(folder_path, 'SMS_LAOS_Plots');
selected_data_folder = fullfile(folder_path, 'SMS_LAOS_SelectedCSV');

if ~exist(plot_folder, 'dir') && (save_plots || save_fig_files)
    mkdir(plot_folder);
end

if ~exist(selected_data_folder, 'dir') && save_selected_data_csv
    mkdir(selected_data_folder);
end

%% ========================= RESULTS HEADER ===============================
results = cell(length(file_list)+1, 25);
results(1,:) = { ...
    'Filename', ...
    'Detected Frequency (Hz)', ...
    'Angular Frequency (rad/s)', ...
    'Cycles Used', ...
    'I1 (Pa)', ...
    'I3 (Pa)', ...
    'I3/I1', ...
    'delta1 (rad)', ...
    'delta3 (rad)', ...
    'G''1 (Pa)', ...
    'G''''1 (Pa)', ...
    'G''3 (Pa)', ...
    'G''''3 (Pa)', ...
    'e1 (Pa)', ...
    'v1 (Pa.s)', ...
    'e3 (Pa)', ...
    'v3 (Pa.s)', ...
    'e3/e1', ...
    'v3/v1', ...
    'G_M_prime (Pa)', ...
    'G_L_prime (Pa)', ...
    'S', ...
    'eta_M_prime (Pa.s)', ...
    'eta_L_prime (Pa.s)', ...
    'T'};

summary_names = {};
summary_freq = [];
summary_I3I1 = [];
summary_e3e1 = [];
summary_v3v1 = [];
summary_S = [];
summary_T = [];

fprintf('\n--- Starting SMS-LAOS Analysis ---\n');
fprintf('Fast mode: %d\n', fast_mode);
fprintf('Cycle selection mode: %s\n\n', cycle_selection_mode);

%% ========================= MAIN LOOP ====================================
for k = 1:length(file_list)
    file_name = fullfile(folder_path, file_list(k).name);
    [~, base_name, ~] = fileparts(file_list(k).name);

    fprintf('Processing file %d/%d: %s\n', k, length(file_list), base_name);

    % -------- Read raw data (.dat input only) --------
    data = readmatrix(file_name, 'FileType', 'text');
    data = data(~any(isnan(data),2), :);

    if size(data,2) < 3
        fprintf('  Skipping %s (less than 3 numeric columns)\n\n', base_name);
        continue;
    end

    % Use first 3 columns only: time, strain, stress
    data = data(:,1:3);

    try
        % -------- Analyze --------
        out = analyze_sms_laos( ...
            data, ...
            cycle_selection_mode, ...
            remove_first_cycles, ...
            remove_last_cycles, ...
            last_n_cycles, ...
            strain_is_percent, ...
            use_freq_range, ...
            freq_min, ...
            freq_max, ...
            use_alternating_odd_sign);

        % -------- Store results --------
        results{k+1,1}  = base_name;
        results{k+1,2}  = out.freq_hz;
        results{k+1,3}  = out.omega;
        results{k+1,4}  = out.n_cycles_used;
        results{k+1,5}  = out.I1;
        results{k+1,6}  = out.I3;
        results{k+1,7}  = out.I3_I1;
        results{k+1,8}  = out.delta1;
        results{k+1,9}  = out.delta3;
        results{k+1,10} = out.Gp1;
        results{k+1,11} = out.Gpp1;
        results{k+1,12} = out.Gp3;
        results{k+1,13} = out.Gpp3;
        results{k+1,14} = out.e1;
        results{k+1,15} = out.v1;
        results{k+1,16} = out.e3;
        results{k+1,17} = out.v3;
        results{k+1,18} = out.e3_e1;
        results{k+1,19} = out.v3_v1;
        results{k+1,20} = out.G_M_prime;
        results{k+1,21} = out.G_L_prime;
        results{k+1,22} = out.S;
        results{k+1,23} = out.eta_M_prime;
        results{k+1,24} = out.eta_L_prime;
        results{k+1,25} = out.T;

        % -------- Summary arrays --------
        summary_names{end+1} = base_name;
        summary_freq(end+1) = out.freq_hz;
        summary_I3I1(end+1) = out.I3_I1;
        summary_e3e1(end+1) = out.e3_e1;
        summary_v3v1(end+1) = out.v3_v1;
        summary_S(end+1) = out.S;
        summary_T(end+1) = out.T;

        % -------- Print summary --------
        fprintf('  f = %.6f Hz, cycles = %d, I3/I1 = %.6g, e3/e1 = %.6g, v3/v1 = %.6g\n', ...
            out.freq_hz, out.n_cycles_used, out.I3_I1, out.e3_e1, out.v3_v1);
        fprintf('  G_M'' = %.6g Pa, G_L'' = %.6g Pa, S = %.6g\n', ...
            out.G_M_prime, out.G_L_prime, out.S);
        fprintf('  eta_M'' = %.6g Pa.s, eta_L'' = %.6g Pa.s, T = %.6g\n\n', ...
            out.eta_M_prime, out.eta_L_prime, out.T);

        % -------- Save selected data as CSV --------
        if save_selected_data_csv
            selected_table = table(out.time, out.strain, out.stress, ...
                'VariableNames', {'Time_s', 'Strain', 'Stress_Pa'});
            writetable(selected_table, ...
                fullfile(selected_data_folder, [base_name '_selected_cycles.csv']));
        end

        % -------- Plot and save hidden figures --------
        if save_plots || save_fig_files
            fig = plot_sms_laos_results(out, base_name, cycle_selection_mode);

            if save_plots
                saveas(fig, fullfile(plot_folder, [base_name '_SMS_LAOS.png']));
            end

            if save_fig_files
                savefig(fig, fullfile(plot_folder, [base_name '_SMS_LAOS.fig']));
            end

            close(fig);
        end

    catch ME
        fprintf('  Error processing %s: %s\n\n', base_name, ME.message);
    end
end

%% ========================= SAVE RESULT TABLES ===========================
if save_excel
    output_excel = fullfile(folder_path, 'SMS_LAOS_results_full.xlsx');
    try
        writecell(results, output_excel);
        fprintf('\nResults saved to Excel:\n%s\n', output_excel);
    catch
        warning('Could not save Excel file. Make sure it is not open.');
    end
end

if save_csv
    if fast_mode
        output_csv = fullfile(folder_path, 'SMS_LAOS_results_fast.csv');
    else
        output_csv = fullfile(folder_path, 'SMS_LAOS_results_full.csv');
    end
    try
        writecell(results, output_csv);
        fprintf('\nResults saved to CSV:\n%s\n', output_csv);
    catch
        warning('Could not save CSV file.');
    end
end

%% ========================= SUMMARY PLOTS ================================
if ~isempty(summary_names) && (save_plots || save_fig_files)
    fig_sum = figure('Name', 'SMS-LAOS Summary', 'Position', [100 100 1200 1100], 'Visible', 'off');

    x = 1:numel(summary_names);

    subplot(6,1,1)
    plot(x, summary_freq, 'o-', 'LineWidth', 1.2)
    xticks(x)
    xticklabels(summary_names)
    xtickangle(45)
    ylabel('f (Hz)')
    title('Detected Frequency')
    grid on

    subplot(6,1,2)
    plot(x, summary_I3I1, 'o-', 'LineWidth', 1.2)
    xticks(x)
    xticklabels(summary_names)
    xtickangle(45)
    ylabel('I3/I1')
    title('Harmonic Ratio')
    grid on

    subplot(6,1,3)
    plot(x, summary_e3e1, 'o-', 'LineWidth', 1.2)
    xticks(x)
    xticklabels(summary_names)
    xtickangle(45)
    ylabel('e3/e1')
    title('Elastic Nonlinearity Ratio')
    grid on

    subplot(6,1,4)
    plot(x, summary_v3v1, 'o-', 'LineWidth', 1.2)
    xticks(x)
    xticklabels(summary_names)
    xtickangle(45)
    ylabel('v3/v1')
    title('Viscous Nonlinearity Ratio')
    grid on

    subplot(6,1,5)
    plot(x, summary_S, 'o-', 'LineWidth', 1.2)
    xticks(x)
    xticklabels(summary_names)
    xtickangle(45)
    ylabel('S')
    title('Strain-Stiffening Ratio')
    grid on

    subplot(6,1,6)
    plot(x, summary_T, 'o-', 'LineWidth', 1.2)
    xticks(x)
    xticklabels(summary_names)
    xtickangle(45)
    ylabel('T')
    title('Shear-Thickening Ratio')
    grid on

    sgtitle('SMS-LAOS Summary')

    if save_plots
        saveas(fig_sum, fullfile(plot_folder, 'SMS_LAOS_summary.png'));
    end
    if save_fig_files
        savefig(fig_sum, fullfile(plot_folder, 'SMS_LAOS_summary.fig'));
    end

    close(fig_sum);
end

fprintf('\n--- Analysis Completed ---\n');
fprintf('This script only READS .dat files and does NOT create any .dat outputs.\n');

%% =========================================================================
% FUNCTION: analyze_sms_laos
% =========================================================================
function out = analyze_sms_laos(data, cycle_selection_mode, remove_first_cycles, remove_last_cycles, ...
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

    % -------- Fourier coefficients (raw) --------
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

    % -------- Chebyshev coefficients (keep your convention) --------
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

%% =========================================================================
% FUNCTION: plot_sms_laos_results
% =========================================================================
function fig = plot_sms_laos_results(out, sample_name, cycle_selection_mode)

    fig = figure('Name', sample_name, ...
        'Position', [80 50 1600 950], ...
        'Visible', 'off');

    subplot(2,4,1)
    plot(out.time_raw, out.strain_raw, '-', 'LineWidth', 1.0); hold on
    plot(out.time_raw(out.selected_mask), out.strain_raw(out.selected_mask), '-', 'LineWidth', 1.5)
    xline(out.t_start_use, '--')
    xline(out.t_end_use, '--')
    xlabel('Time (s)')
    ylabel('Strain')
    title('Raw Strain + Selected Region')
    grid on

    subplot(2,4,2)
    plot(out.time_raw, out.stress_raw, '-', 'LineWidth', 1.0); hold on
    plot(out.time_raw(out.selected_mask), out.stress_raw(out.selected_mask), '-', 'LineWidth', 1.5)
    xline(out.t_start_use, '--')
    xline(out.t_end_use, '--')
    xlabel('Time (s)')
    ylabel('Stress (Pa)')
    title('Raw Stress + Selected Region')
    grid on

    subplot(2,4,3)
    plot(out.time, out.strain, 'LineWidth', 1.2)
    xlabel('Time (s)')
    ylabel('Strain')
    title('Selected Strain vs Time')
    grid on

    subplot(2,4,4)
    plot(out.time, out.stress, 'LineWidth', 1.2)
    xlabel('Time (s)')
    ylabel('Stress (Pa)')
    title('Selected Stress vs Time')
    grid on

    subplot(2,4,5)
    plot(out.strain, out.stress, 'LineWidth', 1.2)
    xlabel('Strain')
    ylabel('Stress (Pa)')
    title('Stress-Strain Lissajous')
    grid on

    subplot(2,4,6)
    stem(out.freqs_plot, out.strain_amp_plot, 'filled')
    xlim([0, max(5*out.freq_hz, 5)])
    xlabel('Frequency (Hz)')
    ylabel('Amplitude')
    title('Strain FFT')
    grid on

    subplot(2,4,7)
    stem(out.freqs_plot, out.stress_amp_plot, 'filled')
    xlim([0, max(5*out.freq_hz, 5)])
    xlabel('Frequency (Hz)')
    ylabel('Amplitude (Pa)')
    title('Stress FFT')
    grid on

    subplot(2,4,8)
    axis off
text(0, 1.00, ['Sample: ' sample_name], 'FontSize', 10, 'Interpreter', 'none')
text(0, 0.93, sprintf('Mode = %s', cycle_selection_mode), 'FontSize', 10, 'Interpreter', 'none')
text(0, 0.86, sprintf('f = %.6f Hz', out.freq_hz), 'FontSize', 10)
text(0, 0.79, sprintf('\\omega = %.6f rad/s', out.omega), 'FontSize', 10)
text(0, 0.72, sprintf('Cycles used = %d', out.n_cycles_used), 'FontSize', 10)
text(0, 0.65, sprintf('I1 = %.4g Pa', out.I1), 'FontSize', 10)
text(0, 0.58, sprintf('I3 = %.4g Pa', out.I3), 'FontSize', 10)
text(0, 0.51, sprintf('I3/I1 = %.4g', out.I3_I1), 'FontSize', 10)
text(0, 0.44, sprintf('e1 = %.4g Pa, e3 = %.4g Pa', out.e1, out.e3), 'FontSize', 10)
text(0, 0.37, sprintf('v1 = %.4g Pa.s, v3 = %.4g Pa.s', out.v1, out.v3), 'FontSize', 10)
text(0, 0.30, sprintf('G''1 = %.4g Pa, G''''1 = %.4g Pa', out.Gp1, out.Gpp1), 'FontSize', 10)
text(0, 0.23, sprintf('G''3 = %.4g Pa, G''''3 = %.4g Pa', out.Gp3, out.Gpp3), 'FontSize', 10)
text(0, 0.16, sprintf('e3/e1 = %.4g, v3/v1 = %.4g', out.e3_e1, out.v3_v1), 'FontSize', 10)
text(0, 0.09, sprintf('S = %.4g, T = %.4g', out.S, out.T), 'FontSize', 10)
text(0, 0.02, sprintf('G_M'' = %.4g, G_L'' = %.4g', out.G_M_prime, out.G_L_prime), 'FontSize', 10)
text(0, -0.05, sprintf('eta_M'' = %.4g, eta_L'' = %.4g', out.eta_M_prime, out.eta_L_prime), 'FontSize', 10)

    sgtitle(['SMS-LAOS Analysis: ' sample_name], 'Interpreter', 'none')
end
