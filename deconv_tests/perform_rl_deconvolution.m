%% Function: Perform 3D RL Deconvolution (Fixed)
function deconv_stack = perform_rl_deconvolution(stack, psf, num_iterations, pad_size, slices_per_vol)
    [rows, cols, total_slices] = size(stack);
    num_volumes = total_slices / slices_per_vol;

    assert(mod(total_slices, slices_per_vol) == 0, 'Stack size mismatch: Not divisible by %d slices per volume', slices_per_vol);

    deconv_results = cell(1, num_volumes); % Temporary storage for parallel processing

    parfor vol = 1:num_volumes
        fprintf('Processing volume %d/%d...\n', vol, num_volumes);

        % Extract volume from stack
        vol_start = (vol - 1) * slices_per_vol + 1;
        vol_end = vol * slices_per_vol;
        vol_data = stack(:,:,vol_start:vol_end);

        % Pad data
        vol_data_padded = padarray(vol_data, [pad_size, pad_size, 0], 'symmetric', 'both');

        % Apply 3D RL Deconvolution
        vol_deconvolved_padded = deconvlucy(vol_data_padded, psf, num_iterations);

        % Crop back to original size
        deconv_results{vol} = vol_deconvolved_padded(pad_size+1:end-pad_size, pad_size+1:end-pad_size, :);
    end

    % Reconstruct full deconvolved stack
    deconv_stack = zeros(rows, cols, total_slices, 'single');
    for vol = 1:num_volumes
        vol_start = (vol - 1) * slices_per_vol + 1;
        vol_end = vol * slices_per_vol;
        deconv_stack(:,:,vol_start:vol_end) = deconv_results{vol};
    end
end