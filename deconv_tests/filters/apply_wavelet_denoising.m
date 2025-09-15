%% Function: Apply Wavelet-Based Denoising (Fixed)
function filtered_stack = apply_wavelet_denoising(mat_obj, rows, cols, total_slices)
    wavelet_type = 'db4';
    denoise_level = 3;
    filtered_stack = zeros(rows, cols, total_slices, 'single');

    parfor i = 1:total_slices
        slice = mat_obj.stack(:,:,i);

        % Wavelet decomposition
        [C, S] = wavedec2(slice, denoise_level, wavelet_type);

        % Compute universal threshold (SureShrink method)
        threshold = wthrmngr('dw2ddenoLVL', 'penalhi', C, S, denoise_level);

        % Apply thresholding correctly to **each wavelet detail coefficient band**
        for level = 1:denoise_level
            [H, V, D] = detcoef2('all', C, S, level); % Extract sub-bands
            H = wthresh(H, 's', threshold);
            V = wthresh(V, 's', threshold);
            D = wthresh(D, 's', threshold);
            C = appcoef2(C, S, wavelet_type, level); % Reconstruct details
        end

        % Reconstruct using thresholded coefficients
        filtered_stack(:,:,i) = waverec2(C, S, wavelet_type);
    end
end