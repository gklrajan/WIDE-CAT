function brain_mask = select_and_visualize_mask(matfile_path, volume_size)
    % Select a single mask for the first slice, apply it to the entire volume,
    % and visualize the overlay on the first volume to verify.

    mat_obj = matfile(matfile_path, 'Writable', false);
    [rows, cols, ~] = size(mat_obj, 'stack'); % Get XY dimensions

    brain_mask = false(rows, cols, volume_size); % Initialize mask for one volume

    % Step 1: Compute a mean projection over the first volume for mask selection
    volume_mean = zeros(rows, cols, 'single');
    for i = 1:volume_size
        volume_mean = volume_mean + single(mat_obj.stack(:, :, i));
    end
    volume_mean = volume_mean / volume_size; % Compute mean projection

    imshow(volume_mean, []); % Display the mean projection
    title('Draw a broad mask (based on mean projection)');
    
    h = drawfreehand('Color', 'r'); % Draw a freehand mask
    single_mask = createMask(h); % Create the binary mask
    close;

    % Step 2: Apply the same mask to all slices in the volume
    for i = 1:volume_size
        brain_mask(:, :, i) = single_mask;
    end

    % Step 3: Visualize the mask overlay on the volume in a 4x10 grid
    montage_data = zeros(rows, cols, 1, volume_size);

    for i = 1:volume_size
        slice = mat_obj.stack(:, :, i); % Load slice from matfile
        montage_data(:, :, 1, i) = overlay_mask(slice, brain_mask(:, :, i), [1 0 0]);
    end

    figure;
    montage(montage_data, 'Size', [4 10]); % Arrange in 4x10 grid
    title('Mask Overlay on Volume (4x10 Layout)');
end

function output = overlay_mask(input_image, mask, color)
    % Overlay mask on the image with the specified color
    rgb_image = repmat(mat2gray(input_image), [1 1 3]); % Convert to RGB
    for c = 1:3
        channel = rgb_image(:, :, c);
        channel(mask) = color(c);
        rgb_image(:, :, c) = channel;
    end
    output = rgb2gray(rgb_image); % Convert overlay back to grayscale for montage
end