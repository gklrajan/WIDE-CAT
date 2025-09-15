function [roi_masks] = analyze_deconvolution_dff(noisy_mat_path, deconv_mat_path, volume_range, slices_per_vol, roi_masks)
    % Compare deconvolved vs. raw stack using dF/F, Laplacian variance, and dynamic range
    % Fully loaded matrices, no matfile nonsense

    % Load .mat files
    fprintf('Loading .mat files...\n');
    noisy_data = load(noisy_mat_path);
    deconv_data = load(deconv_mat_path);

    % Extract the 3D matrix from the structure (assumes only 1 variable per file)
    noisy_stack = struct2cell(noisy_data);
    noisy_stack = noisy_stack{1};

    deconv_stack = struct2cell(deconv_data);
    deconv_stack = deconv_stack{1};

    % Get dimensions
    [~, ~, total_slices] = size(noisy_stack);
    num_volumes = total_slices / slices_per_vol;

    % Validate volume range
    if any(volume_range < 1) || any(volume_range > num_volumes)
        error('Invalid volume range. Must be between 1 and %d.', num_volumes);
    end

    % ROI Selection (if not provided)
    if nargin < 5 || isempty(roi_masks)
        fprintf('Please define ROIs on slice z=20.\n');
        sample_slice = noisy_stack(:, :, 20);
        roi_masks = define_rois(sample_slice);
    else
        fprintf('Using provided ROI masks.\n');
    end

    0;

    % Compute dF/F, Dynamic Range, and Per-ROI Statistics
    [df_f_values, dynamic_range_values, per_roi_stats, per_roi_dynamic_range] = compute_dff(noisy_stack, deconv_stack, volume_range, slices_per_vol, roi_masks);

    % Compute Laplacian Variance
    laplacian_values = compute_laplacian_variance(noisy_stack, deconv_stack, 1:slices_per_vol);

    % Save results
    output_folder = fullfile(fileparts(deconv_mat_path), 'qc_final');  % Save in QC subfolder
    if ~exist(output_folder, 'dir')
        mkdir(output_folder);
    end
    save_metrics_and_plots(df_f_values, laplacian_values, dynamic_range_values, per_roi_stats, per_roi_dynamic_range, volume_range, output_folder);

    fprintf('Analysis complete! Results saved in %s\n', output_folder);
end

%% Function: Compute dF/F, Dynamic Range, and Per-ROI Statistics
function [df_f_values, dynamic_range_values, per_roi_stats, per_roi_dynamic_range] = compute_dff(noisy_stack, deconv_stack, volume_range, slices_per_vol, roi_masks)
    num_volumes = length(volume_range);
    num_rois = length(roi_masks);
    df_f_values = nan(num_volumes, num_rois, 2);
    dynamic_range_values = nan(num_volumes, 2);
    per_roi_stats = nan(num_volumes, num_rois, 2);
    per_roi_dynamic_range = nan(num_volumes, num_rois, 2);

    for t = 1:num_volumes
        temp_dff = nan(num_rois, 2);
        temp_dynamic_range = nan(num_rois, 2);

        slice_idx = 20 + (t - 1) * slices_per_vol;
        if slice_idx > size(noisy_stack, 3)
            continue;
        end

        noisy_slice = noisy_stack(:, :, slice_idx);
        deconv_slice = deconv_stack(:, :, slice_idx);

        for r = 1:num_rois
            roi_mask = roi_masks{r};

            % Compute signal within ROI
            F_t_noisy = nanmean(noisy_slice(roi_mask), 'all');
            F_t_deconv = nanmean(deconv_slice(roi_mask), 'all');

            % Compute rolling baseline
            start_idx = max(1, t - 50);
            baseline_noisy = nanmean(noisy_stack(:, :, start_idx:t), 'all');
            baseline_deconv = nanmean(deconv_stack(:, :, start_idx:t), 'all');

            % Compute dF/F
            temp_dff(r, 1) = (F_t_noisy - baseline_noisy) / baseline_noisy;
            temp_dff(r, 2) = (F_t_deconv - baseline_deconv) / baseline_deconv;

            % Compute dynamic range
            temp_dynamic_range(r, 1) = max(noisy_slice(roi_mask), [], 'all') - min(noisy_slice(roi_mask), [], 'all');
            temp_dynamic_range(r, 2) = max(deconv_slice(roi_mask), [], 'all') - min(deconv_slice(roi_mask), [], 'all');
        end

        df_f_values(t, :, :) = temp_dff;
        per_roi_stats(t, :, :) = temp_dff;
        per_roi_dynamic_range(t, :, :) = temp_dynamic_range;

        % Compute mean dynamic range across ROIs
        dynamic_range_values(t, 1) = mean(temp_dynamic_range(:, 1), 'omitnan');
        dynamic_range_values(t, 2) = mean(temp_dynamic_range(:, 2), 'omitnan');
    end
end

%% Function: Compute Laplacian Variance
function laplacian_values = compute_laplacian_variance(noisy_stack, deconv_stack, z_range)
    laplacian_values = nan(length(z_range), 2);

    for z = 1:length(z_range)
        if z_range(z) > size(noisy_stack, 3)
            continue;
        end
        noisy_slice = noisy_stack(:, :, z_range(z));
        deconv_slice = deconv_stack(:, :, z_range(z));

        % Compute Laplacian variance
        laplacian_values(z, 1) = var(imfilter(noisy_slice, fspecial('laplacian')), 0, 'all');
        laplacian_values(z, 2) = var(imfilter(deconv_slice, fspecial('laplacian')), 0, 'all');
    end
end

%% Function: Save Metrics & Plots
function save_metrics_and_plots(df_f_values, laplacian_values, dynamic_range_values, per_roi_stats, per_roi_dynamic_range, volume_range, output_folder)
    num_rois = size(per_roi_stats, 2);

    % Compute mean & SEM of dF/F
    mean_dff_noisy = mean(df_f_values(:,:,1), 2, 'omitnan');
    sem_dff_noisy = std(df_f_values(:,:,1), 0, 2, 'omitnan') / sqrt(size(df_f_values, 2));
    mean_dff_deconv = mean(df_f_values(:,:,2), 2, 'omitnan');
    sem_dff_deconv = std(df_f_values(:,:,2), 0, 2, 'omitnan') / sqrt(size(df_f_values, 2));

    % Mean dF/F Plot
    figure;
    hold on;
    fill([volume_range, fliplr(volume_range)], [mean_dff_noisy - sem_dff_noisy; flipud(mean_dff_noisy + sem_dff_noisy)], 'r', 'FaceAlpha', 0.3, 'EdgeColor', 'none');
    plot(volume_range, mean_dff_noisy, 'r', 'LineWidth', 2);
    fill([volume_range, fliplr(volume_range)], [mean_dff_deconv - sem_dff_deconv; flipud(mean_dff_deconv + sem_dff_deconv)], 'b', 'FaceAlpha', 0.3, 'EdgeColor', 'none');
    plot(volume_range, mean_dff_deconv, 'b', 'LineWidth', 2);
    xlabel('Volume');
    ylabel('dF/F');
    title('Mean dF/F Over Time with SEM');
    legend({'Noisy (±SEM)', 'Mean dF/F (Noisy)', 'Deconvolved (±SEM)', 'Mean dF/F (Deconvolved)'});
    hold off;
    saveas(gcf, fullfile(output_folder, 'mean_df_f.png'));

    % Dynamic Range Plot
    figure;
    plot(volume_range, dynamic_range_values(:, 1), 'r', 'LineWidth', 2);
    hold on;
    plot(volume_range, dynamic_range_values(:, 2), 'b', 'LineWidth', 2);
    xlabel('Volume');
    ylabel('Dynamic Range (dF/F)');
    title('Mean Dynamic Range of dF/F');
    legend({'Noisy', 'Deconvolved'});
    hold off;
    saveas(gcf, fullfile(output_folder, 'dynamic_range.png'));

    % Laplacian Variance Plot
    figure;
    plot(laplacian_values(:, 1), 'r', 'LineWidth', 2);
    hold on;
    plot(laplacian_values(:, 2), 'b', 'LineWidth', 2);
    xlabel('Z-slice');
    ylabel('Laplacian Variance');
    title('Laplacian Variance Comparison');
    legend({'Noisy', 'Deconvolved'});
    hold off;
    saveas(gcf, fullfile(output_folder, 'laplacian_variance.png'));

    % Per-ROI Mean Intensity Subplots (2x5)
    figure;
    for r = 1:num_rois
        subplot(2, 5, r);
        plot(volume_range, squeeze(per_roi_stats(:, r, 1)), 'r', 'LineWidth', 2);
        hold on;
        plot(volume_range, squeeze(per_roi_stats(:, r, 2)), 'b', 'LineWidth', 2);
        title(sprintf('ROI %d', r));
        hold off;
    end
    saveas(gcf, fullfile(output_folder, 'per_roi_dff.png'));

    % Per-ROI Dynamic Range Subplots (2x5)
    figure;
    for r = 1:num_rois
        subplot(2, 5, r);
        plot(volume_range, squeeze(per_roi_dynamic_range(:, r, 1)), 'r', 'LineWidth', 2);
        hold on;
        plot(volume_range, squeeze(per_roi_dynamic_range(:, r, 2)), 'b', 'LineWidth', 2);
        title(sprintf('ROI %d', r));
        hold off;
    end
    saveas(gcf, fullfile(output_folder, 'per_roi_dynamic_range.png'));
end

%% Function: ROI Selection
function roi_masks = define_rois(sample_slice)
    figure;
    imshow(mat2gray(sample_slice));
    title('Draw ROIs for dF/F analysis. Press Enter when done.');

    roi_masks = {};
    while true
        h = drawfreehand('Color', 'g');
        roi_masks{end+1} = createMask(h);
        answer = input('Press Enter to add another ROI, or type "done" to finish: ', 's');
        if strcmpi(answer, 'done')
            break;
        end
    end
    close;
end