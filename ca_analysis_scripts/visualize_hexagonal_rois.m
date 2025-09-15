function visualize_hexagonal_rois(matfile_path, hex_rois, batch_size)
    % Efficiently visualize hexagonal ROIs in small batches to avoid memory overflow

    mat_obj = matfile(matfile_path, 'Writable', false); % Open MAT file
    dims = size(mat_obj, 'stack'); % Get full size
    rows = dims(1);
    cols = dims(2);
    num_slices = dims(3); % Get total slices
    
    if nargin < 3
        batch_size = 40; % Default batch size to avoid memory overload
    end
    
    % Iterate through slices in batches
    for batch_start = 1:batch_size:num_slices
        batch_end = min(batch_start + batch_size - 1, num_slices);
        num_batch_slices = batch_end - batch_start + 1;
        
        % Allocate memory for batch
        rep_image_stack = zeros(rows, cols, 1, num_batch_slices, 'double');

        for i = 1:num_batch_slices
            z = batch_start + i - 1;
            slice = mat_obj.stack(:, :, z); % Load slice from matfile

            if isempty(hex_rois{z})
                rep_image_stack(:, :, 1, i) = mat2gray(slice); % Just show the slice
                continue; % Skip if no ROIs for this slice
            end

            % Create an overlay image for this slice
            overlay = slice; % Original slice
            roi_mask = false(rows, cols); % Aggregate ROI mask

            for roi = hex_rois{z}
                roi_mask = roi_mask | roi{1}; % Combine all ROI masks for this slice
            end

            % Highlight ROIs in the overlay
            overlay(roi_mask) = max(overlay(:)) * 1.5; % Brighten ROI areas
            rep_image_stack(:, :, 1, i) = mat2gray(overlay); % Normalize to [0, 1]
        end

        % Display the batch
        figure;
        montage(rep_image_stack, 'Size', [ceil(sqrt(num_batch_slices)), ceil(sqrt(num_batch_slices))]); 
        colormap('hot');
        colorbar;
        title(sprintf('Hexagonal ROI Visualization (Slices %d - %d)', batch_start, batch_end));

        uiwait(); % Wait for user to close figure before processing the next batch
    end
end