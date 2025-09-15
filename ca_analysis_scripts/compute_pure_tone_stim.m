function stim_slices = compute_pure_tone_stim(n_volumes, slices_per_volume, slice_acquisition_time)
    % Computes volume-wise stimulus matrix for shuffled pure tone stimuli
    % Args:
    %   n_volumes: Total number of volumes
    %   slices_per_volume: Number of slices per volume
    %   slice_acquisition_time: Acquisition time per slice (in seconds)
    % Returns:
    %   stim_slices: Matrix where each row is [slice_idx, volume_idx, slice_time, stim_status]
    
    % Tone Sequence & Presentation Logic
    shuffled_tones = [200, 300, 600, 700, 650, 1000, 850, 150, 950, 750, ...
                      150, 550, 900, 150, 800, 1000, 450, 650, 300, 450, ...
                      550, 800, 600, 250, 850, 450, 600, 550, 700, 950, ...
                      800, 200, 300, 650, 300, 750, 550, 600, 900, 250, ...
                      750, 250, 600, 900, 700, 800, 150, 750, 650, 800, ...
                      200, 850, 450, 1000, 850, 150, 900, 900, 200, 700, ...
                      250, 1000, 700, 650, 950, 450, 750, 850, 950, 250, ...
                      950, 200, 550, 300, 1000]; % Fixed sequence

    isi_volumes = 6; % Stimulus interval every 6 volumes
    tone_duration = 1.9; % Each tone plays for 1.9s (1 volume)
    
    % Initialize Pure Tone Stimulus Matrix
    pure_tone_matrix = zeros(n_volumes, max(shuffled_tones)); % Rows = volumes, Cols = tone freq

    % Assign 1 for the specific frequency at the corresponding volume
    tone_index = 1; % Track which tone to use
    for v = 1:isi_volumes:n_volumes
        if tone_index <= length(shuffled_tones)
            freq = shuffled_tones(tone_index);
            pure_tone_matrix(v, freq) = 1; % Assign 1 at correct frequency
            tone_index = tone_index + 1;
        end
    end

    % Convert Pure Tone Matrix to Stimulus Slices
    stim_slices = [];
    for v = 1:n_volumes
        for slice_idx = 1:slices_per_volume
            slice_time = ((v - 1) * slices_per_volume + (slice_idx - 1)) * slice_acquisition_time;
            stim_status = pure_tone_matrix(v, :); % Get corresponding tone activity
            stim_slices = [stim_slices; slice_idx, v, slice_time, stim_status];
        end
    end

    fprintf('Pure tone stimulus computation completed.\n');
end