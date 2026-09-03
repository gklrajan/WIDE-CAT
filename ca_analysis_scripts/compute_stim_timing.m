function stim_slices = compute_stim_timing( ...
    n_volumes, stim_start, stim_repeat_vol, stim_duration, ...
    slices_per_volume, slice_acquisition_time)

    % Columns:
    % 1 = slice number within volume
    % 2 = volume number
    % 3 = acquisition time (seconds)
    % 4 = stimulus status (0 = OFF, 1 = ON)

    total_slices = n_volumes * slices_per_volume;
    stim_slices = zeros(total_slices, 4);

    for volume_idx = 1:n_volumes

        % Number of volumes relative to first stimulus
        relative_vol = volume_idx - stim_start;

        % Determine whether stimulus is ON
        if relative_vol >= 0
            stim_status = ...
                mod(relative_vol, stim_repeat_vol) < stim_duration;
        else
            stim_status = false;
        end

        % Assign stimulus status to every slice in this volume
        for slice_idx = 1:slices_per_volume

            global_slice = ...
                (volume_idx - 1) * slices_per_volume + slice_idx;

            slice_time = ...
                (global_slice - 1) * slice_acquisition_time;

            stim_slices(global_slice,:) = [ ...
                slice_idx, ...
                volume_idx, ...
                slice_time, ...
                double(stim_status)];
        end
    end
end