%% Function: Apply Bandpass filter (Difference of Gaussians)
function filtered_stack = apply_bandpass_filter(mat_obj, rows, cols, total_slices)
    low_sigma = 5; 
    high_sigma = 1; 
    filtered_stack = zeros(rows, cols, total_slices, 'single');
    parfor i = 1:total_slices
        slice = mat_obj.stack(:,:,i);
        low_f = imgaussfilt(slice, low_sigma);
        high_f = imgaussfilt(slice, high_sigma);
        filtered_stack(:,:,i) = high_f - low_f;
    end
end