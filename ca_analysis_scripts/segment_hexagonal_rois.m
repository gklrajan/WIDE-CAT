function hex_rois = segment_hexagonal_rois(matfile_path, mask, radius)
    % Generate hexagonal ROIs, loading slices on demand
    mat_obj = matfile(matfile_path, 'Writable', false);
    
    [rows, cols, slices] = size(mask);
    hex_rois = cell(slices, 1);

    for z = 1:slices
        if ~any(mask(:, :, z), 'all')
            continue;
        end
        slice = mat_obj.Mpr(:, :, z); % Load slice only when needed
        hex_rois{z} = create_hex_rois(slice, mask(:, :, z), radius);
    end
end

function rois = create_hex_rois(image, mask, radius)
    % Create hexagonal ROIs for a single z-plane
    [rows, cols] = size(mask);
    [X, Y] = meshgrid(1:cols, 1:rows);
    rois = {};

    step_x = 1.5 * radius;
    step_y = sqrt(3) * radius;

    for y = 1:step_y:rows
        for x = 1:step_x:cols
            hex_mask = sqrt((X - x).^2 + (Y - y).^2) <= radius;
            if any(mask & hex_mask, 'all')
                rois{end + 1} = hex_mask;
            end
        end
    end
end