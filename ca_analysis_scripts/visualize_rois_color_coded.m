function visualize_rois_color_coded(matfile_path, roi_signals, hex_rois, plane_idx, stim_periods)
    % Efficiently visualize ROI masks color-coded by activity (STD-based)
    
    % Load stack plane from matfile
    mat_obj = matfile(matfile_path, 'Writable', false);
    plane_image = mat_obj.stack(:, :, plane_idx); % Load only selected plane
    
    % Extract ROI signals and calculate STD for the selected plane
    data = roi_signals(plane_idx).data; % ROI signals for the plane
    rois = hex_rois{plane_idx, 1}; % ROI masks for the plane
    std_values = std(data, 0, 1); % STD of each ROI's signal

    % Normalize STD values to a [0, 1] range for colormap
    normalized_std = (std_values - min(std_values)) / (max(std_values) - min(std_values));
    cmap = jet(256); % Use a colormap (e.g., jet)

    % Display the brain slice
    figure;
    imshow(mat2gray(plane_image)); % Show the brain image for this plane
    hold on;

    % Overlay each ROI with color based on its STD
    for roi_idx = 1:length(rois)
        roi_mask = rois{1, roi_idx}; % Adjust for structured ROIs
        boundary = bwboundaries(roi_mask);
        color_idx = round(normalized_std(roi_idx) * 255) + 1; % Map to colormap index
        color = cmap(color_idx, :); % Get color from colormap

        for k = 1:length(boundary)
            plot(boundary{k}(:, 2), boundary{k}(:, 1), 'Color', color, 'LineWidth', 1.5);
        end
    end

    hold off;
    title(sprintf('Color-Coded ROIs for Plane %d (Activity: STD)', plane_idx));
    colormap(cmap); % Add the colormap
    cbar = colorbar;
    ylabel(cbar, 'Normalized ROI Activity (STD)', 'FontSize', 12, 'FontWeight', 'bold');
end