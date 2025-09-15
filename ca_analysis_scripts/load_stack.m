function stack = load_stack(file_path)
    % Load a multi-frame TIFF stack robustly
    tiff_info = imfinfo(file_path);
    num_images = numel(tiff_info);
    
    % Preallocate based on the first frame dimensions
    stack = zeros(tiff_info(1).Height, tiff_info(1).Width, num_images, 'double');

    % Open the TIFF file
    t = Tiff(file_path, 'r');
    
    for i = 1:num_images
        t.setDirectory(i); % Move to the correct frame
        stack(:, :, i) = double(t.read());
    end
    
    % Close the TIFF file
    t.close();
    
    fprintf('Loaded %d slices from %s\n', num_images, file_path);
end