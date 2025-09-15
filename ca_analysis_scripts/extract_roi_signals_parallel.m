function roi_signals = extract_roi_signals_parallel(mat_path, hex_rois, slices_per_volume)
    % Extract ROI signals efficiently using batched parallel processing.
    % Loads slices only when needed, avoids race conditions.

    m = matfile(mat_path, 'Writable', false); % Load MAT file in read-only mode
    num_volumes = size(m, 'Mpr', 3) / slices_per_volume; % Total number of volumes

    roi_signals = struct; % Initialize output structure

    % **Parallel Pool Setup (Avoid Redundant Initialization)**
    pool = gcp('nocreate'); % Check if a parallel pool exists
    if isempty(pool)
        parpool('local', max(1, feature('numcores') - 2)); % Use available cores minus 2
    end

    % **Process Each Slice Independently**
    for z = 1:length(hex_rois) 
        num_rois = numel(hex_rois{z}); % Get number of ROIs in this slice
        plane_signals = zeros(num_volumes, num_rois, 'single'); % Storage for signals

        fprintf('Processing plane %d with %d ROIs...\n', z, num_rois);

        % **Pre-load ROI Masks to Reduce Overhead**
        roi_masks = hex_rois{z};

        % **Parallel Processing of ROIs**
        parfor r = 1:num_rois
            roi_mask = roi_masks{r}; % Extract ROI mask
            roi_signal = zeros(num_volumes, 1, 'single'); % Allocate ROI signal

            for v = 1:num_volumes
                slice_idx = (v - 1) * slices_per_volume + z; % Compute slice index
                slice = m.Mpr(:,:,slice_idx); % Load only required slice
                roi_signal(v) = mean(slice(roi_mask)); % Compute mean intensity in ROI
            end
            
            plane_signals(:, r) = roi_signal; % Store computed signal safely
        end

        % **Store Results in Structure**
        roi_signals(z).data = plane_signals;
        roi_signals(z).num_rois = num_rois;
        roi_signals(z).num_volumes = num_volumes;
    end

    fprintf('ROI Signal Extraction Complete!\n');
end