function plot_dff_raster_with_stim(dff_signals, stim_slices, slice_indices, volume_range)
    % Plot ΔF/F raster with stimulus overlay using z-score normalization per ROI.
    % Args:
    %   dff_signals - [num_slices, num_volumes, num_rois] ΔF/F matrix
    %   stim_slices - [slice_idx, volume_idx, slice_time, stim_status] matrix
    %   slice_indices - Vector of slice indices to visualize (e.g., 1:20)
    %   volume_range - Volume range (e.g., 1:200, 50:150) to display

    % Validate inputs
    [num_slices, num_volumes, num_rois] = size(dff_signals);
    if any(slice_indices < 1) || any(slice_indices > num_slices)
        error('Invalid slice indices. Select slices between 1 and %d.', num_slices);
    end
    if any(volume_range < 1) || any(volume_range > num_volumes)
        error('Invalid volume range. Must be between 1 and %d.', num_volumes);
    end

    % Collect all ROIs from specified slices
    dff_selected = [];
    for i = 1:length(slice_indices)
        slice_idx = slice_indices(i);
        dff_selected = [dff_selected, squeeze(dff_signals(slice_idx, volume_range, :))];
    end

    % Z-score normalization per ROI (column-wise), then clip to [-2, 3]
    zscore_signals = zscore(dff_selected, 0, 1);  % mean/std normalization per ROI
    zscore_signals = min(max(zscore_signals, -2), 3);  % clip values

    % Sort ROIs by STD of z-scored signal
    std_values = std(zscore_signals, 0, 1);
    [~, sort_idx] = sort(std_values, 'descend');
    sorted_signals = zscore_signals(:, sort_idx);

    % Extract stimulus onset times for selected slices
    stim_times = stim_slices(ismember(stim_slices(:,1), slice_indices) & stim_slices(:,4) == 1, 3);

    % Plot
    figure('Position', [100, 100, 1000, 600]);
    imagesc(sorted_signals');  % ROIs on Y-axis
    colormap('hot');
    cbar = colorbar;
    ylabel(cbar, 'Z-scored dF/F (Clipped [-2, 3])', 'FontSize', 12, 'FontWeight', 'bold');

    % Overlay stimulus events
    hold on;
    y_limits = ylim;
    for i = 1:length(stim_times)
        x = stim_times(i);
        fill([x x+0.05 x+0.05 x], [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
             [0.5, 0.5, 0.5], 'EdgeColor', 'none', 'FaceAlpha', 0.3);
    end
    hold off;

    % Annotate axes
    xlabel('Time (s)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('ROI Index (Sorted by STD)', 'FontSize', 12, 'FontWeight', 'bold');
    title(sprintf('dF/F Raster Plot with Stimulus Overlay (Volumes %d:%d)', ...
        volume_range(1), volume_range(end)), 'FontSize', 14, 'FontWeight', 'bold');
    grid on;
end