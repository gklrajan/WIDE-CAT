function bg_mask = select_background_mask(image)
    % Function to manually select a large background ROI
    figure, imshow(image, []); title('Select a large background ROI');
    h = drawpolygon('LineWidth', 2, 'Color', 'r'); % Drawr ROI
    bg_mask = createMask(h);
    close;
end