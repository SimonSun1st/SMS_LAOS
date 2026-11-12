function state = sms_laos_export_plot(state,R,sampleName,cycleMode)
%SMS_LAOS_EXPORT_PLOT Reuse the original twelve-panel figure in one export.
% The first file is drawn by the untouched original plotting function.
% Later files replace complete numerical arrays, not sampled display data.
% State is private to the export operation and must be closed by its caller.
if isempty(state)
    fig=sms_laos_plot_v2(R,sampleName,cycleMode);
    try
        titles={'Raw Strain + Selected Region','Raw Stress + Selected Region', ...
            'Selected Strain vs Time','Selected Stress vs Time', ...
            'Total Stress-Strain Lissajous','Strain FFT','Stress FFT','', ...
            'Elastic Lissajous','Viscous Lissajous', ...
            'Total vs Reconstructed Stress','Raw vs Reconstructed Lissajous'};
        allAxes=findall(fig,'Type','axes');
        state=struct('Figure',fig,'Axes',gobjects(12,1),'Lines',{cell(12,1)}, ...
            'Boundaries',{cell(2,1)},'Stems',gobjects(2,1),'Text',gobjects(17,1));
        for k=1:12
            matches=arrayfun(@(ax)strcmp(ax.Title.String,titles{k}),allAxes);
            assert(sum(matches)==1,'SMSApp:PlotTemplate','The original plot template has unexpected axes.');
            state.Axes(k)=allAxes(matches);
            children=state.Axes(k).Children;
            isLine=arrayfun(@(h)strcmp(h.Type,'line'),children);
            state.Lines{k}=flipud(children(isLine));
        end
        for k=1:2
            children=state.Axes(k).Children;
            boundaries=children(arrayfun(@(h)strcmp(h.Type,'constantline'),children));
            [~,order]=sort(arrayfun(@(h)h.Value,boundaries));
            state.Boundaries{k}=boundaries(order);
            assert(numel(boundaries)==2,'SMSApp:PlotTemplate','Expected two interval boundaries.');
            stems=findobj(state.Axes(k+5),'Type','stem');
            assert(isscalar(stems),'SMSApp:PlotTemplate','Expected one FFT stem object.');
            state.Stems(k)=stems;
        end
        children=state.Axes(8).Children;
        labels=children(arrayfun(@(h)strcmp(h.Type,'text'),children));
        [~,order]=sort(arrayfun(@(h)h.Position(2),labels),'descend');
        assert(numel(labels)==17,'SMSApp:PlotTemplate','Expected the original seventeen result labels.');
        state.Text=labels(order);
    catch ME
        if isgraphics(fig), close(fig); end
        rethrow(ME);
    end
    return;
end
assert(isgraphics(state.Figure),'SMSApp:PlotTemplate','The export figure was closed before the batch completed.');
state.Figure.Name=sampleName;

% Creation order is retained for every line, including the selected overlays
% and the measured/reconstructed pairs used by the original legends.
set_curve(state.Lines{1}(1),R.time_raw,R.strain_raw);
set_curve(state.Lines{1}(2),R.time_raw(R.selected_mask),R.strain_raw(R.selected_mask));
set_curve(state.Lines{2}(1),R.time_raw,R.stress_raw);
set_curve(state.Lines{2}(2),R.time_raw(R.selected_mask),R.stress_raw(R.selected_mask));
for k=1:2
    state.Boundaries{k}(1).Value=R.t_start_use;
    state.Boundaries{k}(2).Value=R.t_end_use;
end
set_curve(state.Lines{3},R.time,R.strain);
set_curve(state.Lines{4},R.time,R.stress);
set_curve(state.Lines{5},R.strain,R.stress);
set_curve(state.Stems(1),R.freqs_plot,R.strain_amp_plot);
set_curve(state.Stems(2),R.freqs_plot,R.stress_amp_plot);
set_curve(state.Lines{9},R.strain,R.stress_elastic);
set_curve(state.Lines{10},R.gammadot_over_omega,R.stress_viscous);
set_curve(state.Lines{11}(1),R.time,R.stress);
set_curve(state.Lines{11}(2),R.time,R.stress_reconstructed);
set_curve(state.Lines{12}(1),R.strain,R.stress);
set_curve(state.Lines{12}(2),R.strain,R.stress_reconstructed);
for k=[1:7 9:12]
    state.Axes(k).XLimMode='auto';
    state.Axes(k).YLimMode='auto';
end
for k=6:7, state.Axes(k).XLim=[0 max(5*R.freq_hz,5)]; end

labels={['Sample: ' sampleName],sprintf('Mode = %s',cycleMode), ...
    sprintf('f = %.6f Hz',R.freq_hz),sprintf('\\omega = %.6f rad/s',R.omega), ...
    sprintf('Cycles used = %d',R.n_cycles_used),sprintf('I1 = %.4g Pa',R.I1), ...
    sprintf('I3 = %.4g Pa',R.I3),sprintf('I3/I1 = %.4g',R.I3_I1), ...
    sprintf('e1 = %.4g Pa, e3 = %.4g Pa',R.e1,R.e3), ...
    sprintf('v1 = %.4g Pa.s, v3 = %.4g Pa.s',R.v1,R.v3), ...
    sprintf('G''1 = %.4g Pa, G''''1 = %.4g Pa',R.Gp1,R.Gpp1), ...
    sprintf('G''3 = %.4g Pa, G''''3 = %.4g Pa',R.Gp3,R.Gpp3), ...
    sprintf('e3/e1 = %.4g, v3/v1 = %.4g',R.e3_e1,R.v3_v1), ...
    sprintf('S = %.4g, T = %.4g',R.S,R.T), ...
    sprintf('G_M'' = %.4g, G_L'' = %.4g',R.G_M_prime,R.G_L_prime), ...
    sprintf('eta_M'' = %.4g, eta_L'' = %.4g',R.eta_M_prime,R.eta_L_prime), ...
    sprintf('Residual RMS/I1 = %.4g',R.residual_rms_over_I1)};
for k=1:numel(labels), state.Text(k).String=labels{k}; end
sgtitle(state.Figure,['SMS-LAOS Analysis: ' sampleName],'Interpreter','none');
end

function set_curve(h,x,y)
set(h,'XData',x,'YData',y);
end
