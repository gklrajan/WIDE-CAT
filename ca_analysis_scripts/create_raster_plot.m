function create_raster_plot(matfile_path, stim_slices, stim_duration)
    % Load full dF/F signals from MAT file
    mat_obj = matfile(matfile_path, 'Writable', false);
    dff_signals = mat_obj.dff_signals;

    % Extract timepoints for stimulus from `stim_slices`
    stim_times = stim_slices(stim_slices(:, 4) == 1, 3); % Stim onsets in seconds

    % Normalize signals for better visualization
    all_data = [];
    for z = 1:length(dff_signals)
        all_data = [all_data; dff_signals(z).data]; % Concatenate all planes
    end
    normalized_signals = (all_data - min(all_data, [], 'all')) ./ ...
                         (max(all_data, [], 'all') - min(all_data, [], 'all'));

    % Plot the raster
    figure('Position', [100, 100, 1200, 600]); % Larger figure size for clarity
    imagesc(normalized_signals'); % Transpose to have ROIs on y-axis
    colormap('hot');
    cbar = colorbar;
    ylabel(cbar, 'Normalized Activity', 'FontSize', 12, 'FontWeight', 'bold');
    hold on;

    % Overlay stimulus shading
    for stim = stim_times'
        fill([stim, stim + stim_duration, stim + stim_duration, stim], ...
             [0, 0, size(normalized_signals, 2), size(normalized_signals, 2)], ...
             [0.5, 0.5, 0.5], 'EdgeColor', 'none', 'FaceAlpha', 0.1); % Gray shading
    end

    % Annotate
    xlabel('Time (frames)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('ROI Index', 'FontSize', 12, 'FontWeight', 'bold');
    title('Raster Plot of ROI Activity with Stimulus Times', 'FontSize', 14, 'FontWeight', 'bold');

    % Adjust axes
    ax = gca;
    ax.FontSize = 10;
    ax.XGrid = 'on';
    ax.YGrid = 'on';
    ax.GridColor = [0.5, 0.5, 0.5];
    ax.GridAlpha = 0.5;
    ax.Box = 'on';

    % Add legend for stimulus shading
    legend({'Stimulus Period'}, 'Location', 'northoutside', 'Orientation', 'horizontal');
end