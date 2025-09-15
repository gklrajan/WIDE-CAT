function save_tiff_stack(filepath, stack)
    % Ensure stack is in `uint16` format (convert if needed)
    if ~isa(stack, 'uint16')
        stack = stack - min(stack(:)); % Shift to make min 0
        stack = stack / max(stack(:)); % Scale to [0, 1]
        stack = uint16(stack * 65535); % Convert to 16-bit
    end

    % Open a TIFF file for writing
    t = Tiff(filepath, 'w8'); % Use BigTIFF ('w8') to avoid file size limitations
    
    % Set TIFF tags (essential for multi-page TIFFs)
    tagstruct.ImageLength = size(stack, 1);
    tagstruct.ImageWidth = size(stack, 2);
    tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
    tagstruct.BitsPerSample = 16;
    tagstruct.SamplesPerPixel = 1;
    tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
    tagstruct.Software = 'MATLAB';
    tagstruct.Compression = Tiff.Compression.None;

    % Write each slice separately
    for i = 1:size(stack, 3)
        t.setTag(tagstruct);
        t.write(stack(:,:,i));
        if i < size(stack, 3)
            t.writeDirectory(); % Create a new directory for multi-page TIFF
        end
    end

    % Close file
    t.close();
    fprintf('Saved TIFF stack to: %s\n', filepath);
end