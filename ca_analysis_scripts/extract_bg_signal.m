function bg_signal = extract_bg_signal(mat_path, bg_mask, frames_per_volume)
    % Function to extract background signal **per slice & per time frame** using parfor

    m = matfile(mat_path); % Load stack dynamically
    num_slices = size(m, 'Mpr', 3);
    num_volumes = num_slices / frames_per_volume;
    
    % Initialize background signal storage [slices × time frames]
    bg_signal = zeros(frames_per_volume, num_volumes, 'single');

    fprintf('Extracting background signal slice-wise...\n');
    
    % Use parfor for volume-wise parallel extraction
    parfor v = 1:num_volumes
        temp_signal = zeros(frames_per_volume, 1, 'single'); % Temporary storage per worker

        for s = 1:frames_per_volume
            slice_idx = (v - 1) * frames_per_volume + s;
            current_slice = m.Mpr(:,:,slice_idx); % Load only this slice
            temp_signal(s) = mean(current_slice(bg_mask)); % Mean fluorescence in slice-wise background
        end

        % Store the result after loop completes to prevent parallel write issues
        bg_signal(:, v) = temp_signal;
    end

    fprintf('Background signal extracted successfully.\n');
end