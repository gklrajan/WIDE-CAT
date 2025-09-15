
function stim_slices = compute_stim_timing(n_volumes, stim_start, stim_duration, stim_repeat_vol, slices_per_volume, slice_acquisition_time)
    % Ensure valid number of volumes is provided
    if nargin < 1
        error('Number of volumes (n_volumes) is required.');
    end

    % Correct stimulus repeat interval
    stim_repeat_vol = 17; % Fix based on acquisition script

    % Generate stimulus start times at the first slice of each volume
    stim_start_volumes = stim_start:stim_repeat_vol:n_volumes;

    % Initialize output
    stim_slices = [];

    % Compute exact stimulus onset time per slice
    for start_volume = stim_start_volumes
        for slice_idx = 1:slices_per_volume
            % Compute actual acquisition time of each slice
            slice_time = ((start_volume - 1) * slices_per_volume + (slice_idx - 1)) * slice_acquisition_time;

            % Define stimulus onset time based on the **first slice of the volume**
            stim_start_time = (start_volume - 1) * slices_per_volume * slice_acquisition_time;
            stim_end_time = (start_volume + stim_duration - 1) * slices_per_volume * slice_acquisition_time;

            % Adjust for per-slice onset: If a slice is **after the first slice of the volume**, 
            % it has already been exposed to the stimulus
            if slice_time >= stim_start_time
                stim_status = 1; % Stimulus is ON for this slice
            else
                stim_status = 0; % Stimulus is OFF
            end

            % Store slice-wise stimulus period
            stim_slices = [stim_slices; slice_idx, start_volume, slice_time, stim_status];
        end
    end
end