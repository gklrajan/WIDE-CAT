function create_dff_max_projection(dff_signals, hex_rois, volume_range)
    % Generate depth-coded max intensity projection from dF/F data for a user-specified volume range.
    % Uses alpha blending instead of max() for overlapping ROIs.
    % 
    % Args:
    %   dff_signals - [num_slices, num_volumes, num_rois] dF/F matrix
    %   hex_rois - Cell array containing ROI masks per slice
    %   volume_range - Range of volumes to consider (e.g., 1:10, 50:200)

    [num_slices, total_volumes, num_rois] = size(dff_signals);
    
    % Validate volume range
    if any(volume_range < 1) || any(volume_range > total_volumes)
        error('Invalid volume range. Must be between 1 and %d.', total_volumes);
    end

    % Initialize max intensity and depth maps
    max_intensity_per_roi = zeros(1, num_rois, 'single'); % Max intensity per ROI
    max_depth_per_roi = zeros(1, num_rois, 'single'); % Depth per ROI

    % Iterate through slices to compute max intensity and depth over selected volume range
    for s = 1:num_slices
        dff_plane = squeeze(dff_signals(s, volume_range, :)); % Extract user-defined range
        current_max = max(dff_plane, [], 1); % Max dF/F per ROI in the selected time window
        update_mask = current_max > max_intensity_per_roi;
        max_intensity_per_roi(update_mask) = current_max(update_mask);
        max_depth_per_roi(update_mask) = s;
    end

    % Get image dimensions from first ROI mask
    [rows, cols] = size(hex_rois{1}{1});

    % Initialize the depth-coded projection and alpha mask
    depth_coded_projection = zeros(rows, cols, 3, 'single'); % RGB image
    alpha_mask = zeros(rows, cols, 'single'); % Alpha blending mask

    % Define a colormap for depth coding
    cmap = jet(num_slices);

    % Iterate over ROIs and apply blending
    for r = 1:num_rois
        roi_mask = hex_rois{1}{r}; % ROI mask
        roi_intensity = max_intensity_per_roi(r);
        roi_depth = max_depth_per_roi(r);
        roi_depth = max(1, min(size(cmap, 1), roi_depth)); % Ensure valid depth index

        % RGB color from colormap
        color = cmap(roi_depth, :);

        % Blend using an alpha factor (higher ROI intensity means stronger contribution)
        alpha_factor = 0.5; % Adjust blending strength (0 to 1)
        roi_contribution = alpha_factor * roi_mask * roi_intensity;

        % Apply blending to each color channel
        for c = 1:3
            depth_coded_projection(:, :, c) = depth_coded_projection(:, :, c) + ...
                                              (1 - alpha_mask) .* roi_contribution * color(c);
        end

        % Update alpha mask to prevent over-replacing pixels
        alpha_mask = alpha_mask + (1 - alpha_mask) .* roi_mask * alpha_factor;
    end

    % Normalize the final RGB image
    depth_coded_projection = mat2gray(depth_coded_projection);

    % Display the final projection
    figure;
    imshow(depth_coded_projection);
    title(sprintf('Depth-coded Max Intensity Projection (Volumes %d-%d)', min(volume_range), max(volume_range)));

    % Add colorbar to indicate depth mapping
    colormap(cmap);
    cbar = colorbar('Ticks', linspace(0, 1, num_slices), 'TickLabels', 1:num_slices);
    ylabel(cbar, 'Depth (z-plane)', 'FontSize', 12, 'FontWeight', 'bold');
end