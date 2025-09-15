%% Function: Apply Bilateral filter
function filtered_stack = apply_bilateral_filter(mat_obj, rows, cols, total_slices)
    spatial_sigma = 2; 
    intensity_sigma = 0.1;
    filtered_stack = zeros(rows, cols, total_slices, 'single');
    parfor i = 1:total_slices
        slice = mat_obj.stack(:,:,i);
        filtered_stack(:,:,i) = imbilatfilt(slice, intensity_sigma, spatial_sigma);
    end
end