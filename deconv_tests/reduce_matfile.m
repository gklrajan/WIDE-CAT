function reduce_matfile(matfile_path, slices_per_vol,reduce_to_vol)
    % Extracts the first N volumes from a large .mat stack and saves it as a new .mat file.
    % 
    % Args:
    %   matfile_path - Path to the original .mat file
    %   slices_per_vol - Number of Z slices per volume
    %   reduce_to_vol - First N volumes to keep

    % Extract folder, filename, and set new filename
    [input_folder, file_name, ext] = fileparts(matfile_path);
    output_file = fullfile(input_folder, ['reduce_', file_name, ext]);

    % Load .mat file memory-efficiently
    fprintf('Loading .mat file with memory-efficient access...\n');
    mat_obj = matfile(matfile_path, 'Writable', false);
    
    % Get stack dimensions
    [rows, cols, total_slices] = size(mat_obj, 'stack');
    num_volumes = total_slices / slices_per_vol;

    if num_volumes < reduce_to_vol
        error('The input file has only %d volumes. Cannot extract volumes.', num_volumes);
    end

    % Define slice range for the first N volumes
    slice_range = 1:(reduce_to_vol * slices_per_vol);

    % Create new .mat file to store the reduced stack
    fprintf('Saving reduced .mat file to: %s\n', output_file);
    mat_out = matfile(output_file, 'Writable', true);
    mat_out.stack = zeros(rows, cols, length(slice_range), 'single'); % Preallocate

    % Copy data from original file
    mat_out.stack = mat_obj.stack(:, :, slice_range);

    fprintf('Extraction complete! Reduced file saved as: %s\n', output_file);
end