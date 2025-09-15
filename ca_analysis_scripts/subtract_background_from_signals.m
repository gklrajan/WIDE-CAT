function corrected_signals = subtract_background_from_signals(roi_signals, bg_signal)
    % Extract dimensions
    num_slices = numel(roi_signals); % 40 slices
    num_volumes = roi_signals(1).num_volumes; % v time volumes
    num_rois = roi_signals(1).num_rois; % n ROIs

    % Initialize storage
    corrected_signals = zeros(num_slices, num_volumes, num_rois, 'single');

    % Iterate over slices
    for s = 1:num_slices
        if size(roi_signals(s).data, 1) ~= num_volumes || size(roi_signals(s).data, 2) ~= num_rois
            error('Mismatch in ROI signal dimensions at slice %d!', s);
        end
        
        % Subtract background per volume
        for v = 1:num_volumes
            corrected_signals(s, v, :) = roi_signals(s).data(v, :) - bg_signal(s, v);
        end
    end

    fprintf('Background subtraction completed.\n');
end