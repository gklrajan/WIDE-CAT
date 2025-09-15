function get_tiff_examples(noisy_mat_path, deconv_mat_path, volume_idx, slices_per_vol)
    % Saves representative stacks of noisy & deconvolved images.
    %
    % Inputs:
    %   - noisy_mat_path: Path to noisy .mat file
    %   - deconv_mat_path: Path to deconvolved .mat file
    %   - volume_idx: Volume index to extract
    %   - slices_per_vol: Number of slices per volume

    % Get parent directory and create 'qc' folder
    parent_folder = fileparts(deconv_mat_path);
    qc_folder = fullfile(parent_folder, 'qc_final');
    if ~exist(qc_folder, 'dir')
        mkdir(qc_folder);
    end

    % Load .mat files (assuming single 3D matrix per file)
    fprintf('Loading data...\n');
    noisy_data = load(noisy_mat_path);
    deconv_data = load(deconv_mat_path);

    % Extract variable name dynamically
    field_noisy = fieldnames(noisy_data);
    field_deconv = fieldnames(deconv_data);

    % Get 3D stacks
    noisy_stack = noisy_data.(field_noisy{1});
    deconv_stack = deconv_data.(field_deconv{1});

    % Save full volume (all z-slices)
    save_volume_as_tif(noisy_stack, volume_idx, slices_per_vol, fullfile(qc_folder, 'noisy_volume.tif'));
    save_volume_as_tif(deconv_stack, volume_idx, slices_per_vol, fullfile(qc_folder, 'deconvolved_volume.tif'));

    % Save 50-frame time series at z=20
    save_time_series_as_tif(noisy_stack, deconv_stack, volume_idx, slices_per_vol, qc_folder);

    fprintf('TIFF stacks saved in %s/\n', qc_folder);
end

%% Function: Save 1 volume (all z-slices) as a TIFF stack
function save_volume_as_tif(stack, volume_idx, slices_per_vol, output_filename)
    fprintf('Saving %s...\n', output_filename);
    
    for z = 1:slices_per_vol
        slice_idx = (volume_idx - 1) * slices_per_vol + z;
        
        % Ensure we don't exceed matrix bounds
        if slice_idx > size(stack, 3)
            break;
        end
        
        frame = stack(:, :, slice_idx);

        % Convert to grayscale and save as TIFF
        if z == 1
            imwrite(mat2gray(frame), output_filename, 'Compression', 'none');
        else
            imwrite(mat2gray(frame), output_filename, 'WriteMode', 'append', 'Compression', 'none');
        end
    end
end

%% Function: Save 50-frame time series at z=20 as a TIFF stack
function save_time_series_as_tif(noisy_stack, deconv_stack, volume_idx, slices_per_vol, qc_folder)
    fprintf('Saving time series TIFF stacks...\n');

    % Define file names
    noisy_filename = fullfile(qc_folder, 'noisy_time_series.tif');
    deconv_filename = fullfile(qc_folder, 'deconvolved_time_series.tif');

    % Extract time series from z=20 over 50 frames
    start_frame = max(1, (volume_idx - 1) * slices_per_vol - 49);
    end_frame = (volume_idx - 1) * slices_per_vol;

    for t = start_frame:end_frame
        % Ensure we don't exceed matrix bounds
        if t > size(noisy_stack, 3)
            break;
        end

        noisy_frame = noisy_stack(:, :, t);
        deconv_frame = deconv_stack(:, :, t);

        % Save noisy stack
        if t == start_frame
            imwrite(mat2gray(noisy_frame), noisy_filename, 'Compression', 'none');
            imwrite(mat2gray(deconv_frame), deconv_filename, 'Compression', 'none');
        else
            imwrite(mat2gray(noisy_frame), noisy_filename, 'WriteMode', 'append', 'Compression', 'none');
            imwrite(mat2gray(deconv_frame), deconv_filename, 'WriteMode', 'append', 'Compression', 'none');
        end
    end
end