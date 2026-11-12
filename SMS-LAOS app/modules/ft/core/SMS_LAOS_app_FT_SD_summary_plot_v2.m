function fig_sum = SMS_LAOS_app_FT_SD_summary_plot_v2(entries)
%SMS_LAOS_APP_FT_SD_SUMMARY_PLOT_V2 Original six-panel summary of the supplied entries.
summary_names=cell(1,numel(entries));
summary_freq=zeros(1,numel(entries));
summary_I3I1=summary_freq; summary_e3e1=summary_freq; summary_v3v1=summary_freq;
summary_S=summary_freq; summary_T=summary_freq;
for k=1:numel(entries)
    [~,summary_names{k}]=fileparts(entries(k).Name);
    R=entries(k).Result;
    summary_freq(k)=R.freq_hz; summary_I3I1(k)=R.I3_I1;
    summary_e3e1(k)=R.e3_e1; summary_v3v1(k)=R.v3_v1;
    summary_S(k)=R.S; summary_T(k)=R.T;
end
    fig_sum = figure('Name', 'SMS-LAOS Summary', ...
        'Position', [100 100 1200 1100], ...
        'Visible', 'off');

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
end
