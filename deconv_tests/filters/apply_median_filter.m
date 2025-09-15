%% Function: Apply Median filter
function filtered_stack = apply_median_filter(mat_obj, rows, cols, total_slices)
    filtered_stack = zeros(rows, cols, total_slices, 'single');
    parfor i = 1:total_slices
        slice = mat_obj.stack(:,:,i);
        filtered_stack(:,:,i) = medfilt2(slice, [3 3]);
    end
end