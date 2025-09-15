function apply_filters_and_deconvolve(matfile_path, psf_path, num_iterations, pad_size,slices_per_vol)
    % Applies multiple filtering methods, then performs RL deconvolution on each.
    % 
    % Args:
    %   matfile_path - Path to the input .mat file containing the imaging stack
    %   psf_path - Path to the point spread function (PSF) file
    %   num_iterations - Number of RL iterations
    %   pad_size - Padding size in pixels

    % Extract folder and create output directory
    [input_folder, file_name, ~] = fileparts(matfile_path);
    output_folder = fullfile(input_folder, 'trad_filters_deconv_tests');

    if ~exist(output_folder, 'dir')
        mkdir(output_folder);
    end

    % Load .mat file (memory efficient)
    fprintf('Loading imaging stack...\n');
    mat_obj = matfile(matfile_path, 'Writable', false);
    stack_info = whos(mat_obj, 'stack');

    if isempty(stack_info)
        error('Variable "stack" not found in the provided .mat file.');
    end

    [rows, cols, total_slices] = size(mat_obj, 'stack');

    % Load and normalize PSF
    fprintf('Loading PSF...\n');
    psf = load_tiff_stack(psf_path);
    psf = psf / sum(psf(:)); % Normalize PSF
    psf = padarray(psf, [pad_size, pad_size, 0], 'symmetric', 'both'); % Pad PSF

    % Extract raw stack into memory
    fprintf('Extracting raw stack into memory...\n');
    raw_stack = zeros(rows, cols, total_slices, 'single');
    for i = 1:total_slices
        raw_stack(:,:,i) = mat_obj.stack(:,:,i);
    end

    % Apply filters
    fprintf('Applying filters...\n');
    gaussian_stack = apply_gaussian_filter(mat_obj, rows, cols, total_slices);
    median_stack = apply_median_filter(mat_obj, rows, cols, total_slices);
    bandpass_stack = apply_bandpass_filter(mat_obj, rows, cols, total_slices);
    bilateral_stack = apply_bilateral_filter(mat_obj, rows, cols, total_slices);
    %wavelet_stack = apply_wavelet_denoising(mat_obj, rows, cols, total_slices);

    % Perform RL Deconvolution
    fprintf('Performing RL deconvolution...\n');
    deconv_raw = perform_rl_deconvolution(raw_stack, psf, num_iterations, pad_size, slices_per_vol);
    deconv_gaussian = perform_rl_deconvolution(gaussian_stack, psf, num_iterations, pad_size, slices_per_vol);
    deconv_median = perform_rl_deconvolution(median_stack, psf, num_iterations, pad_size, slices_per_vol);
    deconv_bandpass = perform_rl_deconvolution(bandpass_stack, psf, num_iterations, pad_size, slices_per_vol);
    deconv_bilateral = perform_rl_deconvolution(bilateral_stack, psf, num_iterations, pad_size, slices_per_vol);
    %deconv_wavelet = perform_rl_deconvolution(wavelet_stack, psf, num_iterations, pad_size, slices_per_vol);

    % Save results
    fprintf('Saving results to %s\n', output_folder);
    save(fullfile(output_folder, [file_name, '_raw_deconv.mat']), 'deconv_raw', '-v7.3');
    save(fullfile(output_folder, [file_name, '_gaussian_deconv.mat']), 'deconv_gaussian', '-v7.3');
    save(fullfile(output_folder, [file_name, '_median_deconv.mat']), 'deconv_median', '-v7.3');
    save(fullfile(output_folder, [file_name, '_bandpass_deconv.mat']), 'deconv_bandpass', '-v7.3');
    save(fullfile(output_folder, [file_name, '_bilateral_deconv.mat']), 'deconv_bilateral', '-v7.3');
    %save(fullfile(output_folder, [file_name, '_wavelet_deconv.mat']), 'deconv_wavelet', '-v7.3');

    fprintf('Filtering and deconvolution completed.\n');
end
