%% Function: Load TIFF Stack
function stack = load_tiff_stack(filepath)
    info = imfinfo(filepath);
    num_images = numel(info);
    stack = zeros(info(1).Height, info(1).Width, num_images, 'single');
    for i = 1:num_images
        stack(:,:,i) = im2single(imread(filepath, i));
    end
end