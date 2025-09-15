function stim_slices = convert_tone_periods_to_stim_slices(tone_periods)
    % Convert `tone_periods` into `stim_slices` format for analysis.
    % Args:
    %   tone_periods - [num_slices, num_frequencies+3] matrix
    % Returns:
    %   stim_slices - [slice_idx, volume_idx, slice_time, stim_status]

    % Extract necessary columns
    slice_idx = tone_periods(:, 1);
    volume_idx = tone_periods(:, 2);
    slice_time = tone_periods(:, 3);
    
    % Compute `stim_status`: 1 if any tone is active, otherwise 0
    stim_status = any(tone_periods(:, 4:end), 2);

    % Construct stim_slices matrix
    stim_slices = [slice_idx, volume_idx, slice_time, stim_status];
    
    fprintf('Stimulus matrix generated from tone periods.\n');
end