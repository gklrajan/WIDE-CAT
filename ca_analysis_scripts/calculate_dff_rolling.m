function dff_signals = calculate_dff_rolling(corrected_roi_signals, window_size)
    % Compute ΔF/F using a rolling baseline (moving median).
    % Args:
    %   corrected_roi_signals - 3D matrix [num_slices, num_volumes, num_rois]
    %   window_size - Number of frames for rolling baseline calculation (default 30)
    % Returns:
    %   dff_signals - 3D matrix [num_slices, num_volumes, num_rois] with ΔF/F values

    if nargin < 2
        window_size = 30; % Default window size (~60s for 0.5 Hz)
    end

    % Extract dimensions
    [num_slices, num_volumes, num_rois] = size(corrected_roi_signals);

    % Initialize dF/F matrix
    dff_signals = zeros(num_slices, num_volumes, num_rois, 'single');

    fprintf('Computing ΔF/F using rolling baseline (window: %d frames)...\n', window_size);
    
    % Process each slice independently
    for s = 1:num_slices
        fprintf('Processing Slice %d/%d...\n', s, num_slices);
        
        % Extract signals for this slice
        signals = squeeze(corrected_roi_signals(s, :, :)); % Shape: [num_volumes, num_rois]
        signals = max(signals, 1e-3); % Prevent negative fluorescence values

        % Initialize rolling baseline (use single precision for memory efficiency)
        rolling_baseline = zeros(num_volumes, num_rois, 'single');

        % Compute rolling baseline using a moving median
        for t = 1:num_volumes
            start_idx = max(1, t - window_size);
            rolling_baseline(t, :) = nanmedian(signals(start_idx:t, :), 1);
        end

        % Ensure rolling baseline is not too small to avoid large dF/F values
        rolling_baseline(rolling_baseline < 1e-6) = 1e-6;

        % Compute dF/F
        dff_signals(s, :, :) = (signals - rolling_baseline) ./ rolling_baseline;

        % Debugging check
        disp(['Slice ', num2str(s), ' Min/Max Baseline: ', num2str(min(rolling_baseline(:))), ' / ', num2str(max(rolling_baseline(:)))]);
    end

    fprintf('ΔF/F computation complete.\n');
end