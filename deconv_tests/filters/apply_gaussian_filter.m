%% Function: Apply Gaussian filter
function filtered_stack = apply_gaussian_filter(mat_obj, rows, cols, total_slices)
    sigma = 1; 
    filtered_stack = zeros(rows, cols, total_slices, 'single');
    parfor i = 1:total_slices
        slice = mat_obj.stack(:,:,i);
        filtered_stack(:,:,i) = imgaussfilt(slice, sigma);
    end
end
