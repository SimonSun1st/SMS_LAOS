function fig = SMS_LAOS_app_FT_SD_plot_v2(out, sample_name, cycle_selection_mode)

    fig = figure('Name', sample_name, ...
        'Position', [80 50 1700 1200], ...
        'Visible', 'off');

    subplot(3,4,1)
    plot(out.time_raw, out.strain_raw, '-', 'LineWidth', 1.0); hold on
    plot(out.time_raw(out.selected_mask), out.strain_raw(out.selected_mask), '-', 'LineWidth', 1.5)
    xline(out.t_start_use, '--')
    xline(out.t_end_use, '--')
    xlabel('Time (s)')
    ylabel('Strain')
    title('Raw Strain + Selected Region')
    grid on

    subplot(3,4,2)
    plot(out.time_raw, out.stress_raw, '-', 'LineWidth', 1.0); hold on
    plot(out.time_raw(out.selected_mask), out.stress_raw(out.selected_mask), '-', 'LineWidth', 1.5)
    xline(out.t_start_use, '--')
    xline(out.t_end_use, '--')
    xlabel('Time (s)')
    ylabel('Stress (Pa)')
    title('Raw Stress + Selected Region')
    grid on

    subplot(3,4,3)
    plot(out.time, out.strain, 'LineWidth', 1.2)
    xlabel('Time (s)')
    ylabel('Strain')
    title('Selected Strain vs Time')
    grid on

    subplot(3,4,4)
    plot(out.time, out.stress, 'LineWidth', 1.2)
    xlabel('Time (s)')
    ylabel('Stress (Pa)')
    title('Selected Stress vs Time')
    grid on

    subplot(3,4,5)
    plot(out.strain, out.stress, 'LineWidth', 1.2)
    xlabel('Strain')
    ylabel('Stress (Pa)')
    title('Total Stress-Strain Lissajous')
    grid on

    subplot(3,4,6)
    stem(out.freqs_plot, out.strain_amp_plot, 'filled')
    xlim([0, max(5*out.freq_hz, 5)])
    xlabel('Frequency (Hz)')
    ylabel('Amplitude')
    title('Strain FFT')
    grid on

    subplot(3,4,7)
    stem(out.freqs_plot, out.stress_amp_plot, 'filled')
    xlim([0, max(5*out.freq_hz, 5)])
    xlabel('Frequency (Hz)')
    ylabel('Amplitude (Pa)')
    title('Stress FFT')
    grid on

    subplot(3,4,8)
    axis off
    text(0, 1.00, ['Sample: ' sample_name], 'FontSize', 9, 'Interpreter', 'none')
    text(0, 0.93, sprintf('Mode = %s', cycle_selection_mode), 'FontSize', 9, 'Interpreter', 'none')
    text(0, 0.86, sprintf('f = %.6f Hz', out.freq_hz), 'FontSize', 9)
    text(0, 0.79, sprintf('\\omega = %.6f rad/s', out.omega), 'FontSize', 9)
    text(0, 0.72, sprintf('Cycles used = %d', out.n_cycles_used), 'FontSize', 9)
    text(0, 0.65, sprintf('I1 = %.4g Pa', out.I1), 'FontSize', 9)
    text(0, 0.58, sprintf('I3 = %.4g Pa', out.I3), 'FontSize', 9)
    text(0, 0.51, sprintf('I3/I1 = %.4g', out.I3_I1), 'FontSize', 9)
    text(0, 0.44, sprintf('e1 = %.4g Pa, e3 = %.4g Pa', out.e1, out.e3), 'FontSize', 9)
    text(0, 0.37, sprintf('v1 = %.4g Pa.s, v3 = %.4g Pa.s', out.v1, out.v3), 'FontSize', 9)
    text(0, 0.30, sprintf('G''1 = %.4g Pa, G''''1 = %.4g Pa', out.Gp1, out.Gpp1), 'FontSize', 9)
    text(0, 0.23, sprintf('G''3 = %.4g Pa, G''''3 = %.4g Pa', out.Gp3, out.Gpp3), 'FontSize', 9)
    text(0, 0.16, sprintf('e3/e1 = %.4g, v3/v1 = %.4g', out.e3_e1, out.v3_v1), 'FontSize', 9)
    text(0, 0.09, sprintf('S = %.4g, T = %.4g', out.S, out.T), 'FontSize', 9)
    text(0, 0.02, sprintf('G_M'' = %.4g, G_L'' = %.4g', out.G_M_prime, out.G_L_prime), 'FontSize', 9)
    text(0, -0.05, sprintf('eta_M'' = %.4g, eta_L'' = %.4g', out.eta_M_prime, out.eta_L_prime), 'FontSize', 9)
    text(0, -0.12, sprintf('Residual RMS/I1 = %.4g', out.residual_rms_over_I1), 'FontSize', 9)

    subplot(3,4,9)
    plot(out.strain, out.stress_elastic, 'LineWidth', 1.2)
    xlabel('Strain')
    ylabel('$\sigma_{\mathrm{elastic}}$ (Pa)', 'Interpreter', 'latex')
    title('Elastic Lissajous')
    grid on

    subplot(3,4,10)
    plot(out.gammadot_over_omega, out.stress_viscous, 'LineWidth', 1.2)
    xlabel('$\dot{\gamma}/\omega$', 'Interpreter', 'latex')
    ylabel('$\sigma_{\mathrm{viscous}}$ (Pa)', 'Interpreter', 'latex')
    title('Viscous Lissajous')
    grid on

    subplot(3,4,11)
    plot(out.time, out.stress, 'LineWidth', 1.2); hold on
    plot(out.time, out.stress_reconstructed, '--', 'LineWidth', 1.2)
    xlabel('Time (s)')
    ylabel('Stress (Pa)')
    title('Total vs Reconstructed Stress')
    legend('Raw selected stress', 'Elastic + viscous', 'Location', 'best')
    grid on

    subplot(3,4,12)
    plot(out.strain, out.stress, 'LineWidth', 1.0); hold on
    plot(out.strain, out.stress_reconstructed, '--', 'LineWidth', 1.2)
    xlabel('Strain')
    ylabel('Stress (Pa)')
    title('Raw vs Reconstructed Lissajous')
    legend('Raw total', 'Reconstructed', 'Location', 'best')
    grid on

    sgtitle(['SMS-LAOS Analysis: ' sample_name], 'Interpreter', 'none')
end
