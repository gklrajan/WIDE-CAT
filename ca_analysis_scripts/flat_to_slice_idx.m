function [slice_idx, roi_in_slice] = flat_to_slice_idx(flat_idx, hex_rois)
roi_counts = cellfun(@numel, hex_rois);
cum_counts = cumsum(roi_counts);
slice_idx = find(cum_counts >= flat_idx, 1, 'first');
if slice_idx == 1
    roi_in_slice = flat_idx;
else
    roi_in_slice = flat_idx - cum_counts(slice_idx-1);
end
end