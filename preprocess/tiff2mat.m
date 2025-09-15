
    % Load TIFF and save it as a .mat file for efficient access
    tiff_path='D:\Gokul\2024-Widefield\data\preprocessed\preprocessed_lnm_ctrl_fish4_\preprocessed_lnm_ctrl_fish4_.tif';
    mat_path='D:\Gokul\2024-Widefield\data\preprocessed\preprocessed_lnm_ctrl_fish4_\preprocessed_lnm_ctrl_fish4_.mat';

    info = imfinfo(tiff_path);
    num_slices = numel(info);
    img_size = [info(1).Height, info(1).Width, num_slices];

    % Use matfile() to avoid loading everything into memory
    mat_obj = matfile(mat_path, 'Writable', true);
    mat_obj.stack = zeros(img_size, 'single');  % Pre-allocate in MAT file

    fprintf('Converting TIFF to MAT: %s\n', tiff_path);
    for i = 1:num_slices
        mat_obj.stack(:,:,i) = im2single(imread(tiff_path, i));
        if mod(i, 100) == 0
            fprintf('Saved %d/%d slices...\n', i, num_slices);
        end
    end

    fprintf('Conversion complete. Saved to: %s\n', mat_path);