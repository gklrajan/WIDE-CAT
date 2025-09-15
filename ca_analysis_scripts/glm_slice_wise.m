%% Slice-wise Regression Analysis with Stimulus Regressor (Dynamic)
clear; clc;

% Define input file path
%input_file = 'D:\Gokul\2024-Widefield\data\rl_deconvolved\02_preprocessed_lnm_ctrl_fish4_rl_deconvolved\results\preprocessed_lnm_ctrl_fish4__rl_deconvolved_analysis.mat';
%load('D:\Gokul\2024-Widefield\data\rl_deconvolved\02_preprocessed_lnm_ctrl_fish4_rl_deconvolved\results\stim_slices.mat');  % `dff_signals(slices, volumes, ROIs)`

input_file = 'D:\Gokul\2024-Widefield\data\rl_deconvolved\01_preprocessed_fish5_good-definiteLearner_rl_deconvolved\results\preprocessed_fish5_good-definiteLearner__rl_deconvolved_analysis.mat';
load('D:\Gokul\2024-Widefield\data\rl_deconvolved\01_preprocessed_fish5_good-definiteLearner_rl_deconvolved\results\stim_slices.mat');  % `dff_signals(slices, volumes, ROIs)`
% Extract parent folder (one level up from "results" folder)

%input_file = 'D:\Gokul\2024-Widefield\data\rl_deconvolved\03_preprocessed_dc5_test_rl_deconvolved\results\preprocessed_dc5_test_rl_deconvolved_analysis.mat';
%load('D:\Gokul\2024-Widefield\data\rl_deconvolved\03_preprocessed_dc5_test_rl_deconvolved\results\stim_slices.mat');  % `dff_signals(slices, volumes, ROIs)`
% Extract parent folder (one level up from "results" folder)
parent_folder = fileparts(fileparts(input_file));

% Load stimulus timing data
fprintf('Loading stimulus and dF/F data...\n');
load(input_file);  % Contains stim_periods_per_slice
load(fullfile(parent_folder, 'results', 'stim_slices.mat'));  % Contains dff_signals

dff_signals = dff_signals(:,:,:);
stim_periods_per_slice = stim_periods_per_slice(:,:);

% Parameters for GCaMP6s convolution
tau = 1.0; % Decay time constant for GCaMP6s
time_period = 1.9; % Time (s) for 1 full volume acquisition
fs = round(1 / time_period, 2);

% Extract stimulus timing
time_vector = stim_periods_per_slice(:, 3);  % Acquisition time per slice
stim_onset_vols = unique(stim_periods_per_slice(:, 2));

% Create full stimulus vector of length num_volumes
[num_slices, num_volumes, num_rois] = size(dff_signals);
stim_vector_full = zeros(num_volumes, 1);
for v = 1:length(stim_onset_vols)
    idx = stim_onset_vols(v);
    stim_vector_full(idx:min(idx+5, num_volumes)) = 1;
end

%% Generate Calcium-Modeled Stimulus Regressors
fprintf('Generating calcium-modeled stimulus regressor...\n');
t_kernel = 0:1/fs:3*tau; % Kernel duration
calcium_kernel = exp(-t_kernel / tau); % Exponential decay function

% Convolve stimulus with calcium response function
stim_regressor_full = conv(stim_vector_full, calcium_kernel, 'full');
stim_regressor_full = stim_regressor_full(1:num_volumes); % Trim to match

% Normalize regressor
stim_regressor_full = stim_regressor_full / max(stim_regressor_full);

%% Perform Slice-wise Regression
fprintf('Performing slice-wise regression...\n');

glm_results = struct();
significant_rois = cell(num_slices, 1); % Store ROIs with significant regression

for slice_idx = 1:num_slices
    Y = squeeze(dff_signals(slice_idx, :, :)); % Extract dF/F signals for this slice (Volumes x ROIs)
    X = [ones(num_volumes, 1), stim_regressor_full]; % Design matrix (Intercept + Stimulus Regressor)

    beta_values = nan(num_rois, 2); % Store betas (intercept, stim)
    p_values = nan(num_rois, 2); % Store p-values

    for roi = 1:num_rois
        [b, ~, ~, ~, stats] = regress(Y(:, roi), X);
        beta_values(roi, :) = b;
        p_values(roi, :) = stats(3);
    end

    % Store results
    glm_results(slice_idx).beta = beta_values;
    glm_results(slice_idx).p_values = p_values;

    % Identify significant ROIs (p < 0.05)
    sig_idx = find(p_values(:,2) < 0.05);
    significant_rois{slice_idx} = struct('rois', sig_idx, 'betas', beta_values(sig_idx, 2));
end

%% Save GLM Results
save(fullfile(parent_folder, 'glm_results.mat'), 'glm_results', 'stim_regressor_full', 'time_vector');
fprintf('GLM analysis completed. Results saved in %s\n', parent_folder);

%% Depth-Coded Max Projection of Significant ROIs
fprintf('Generating depth-coded max projection of significant ROIs...\n');

% Get image dimensions from first slice's ROIs
[rows, cols] = size(hex_rois{1}{1}); 
num_rois = length(hex_rois{1});

% Initialize max intensity and depth maps
max_intensity_per_roi = zeros(1, num_rois);
max_depth_per_roi = zeros(1, num_rois);

% Iterate through slices to find max activation
for z = 1:num_slices
    roi_ids = significant_rois{z}.rois;
    beta_values = significant_rois{z}.betas;

    for i = 1:length(roi_ids)
        roi_id = roi_ids(i);
        beta_val = beta_values(i);

        % Update max intensity and depth maps
        if abs(beta_val) > abs(max_intensity_per_roi(roi_id))
            max_intensity_per_roi(roi_id) = beta_val;
            max_depth_per_roi(roi_id) = z;
        end
    end
end

% Initialize the depth-coded projection
depth_coded_projection = zeros(rows, cols, 3);

% Colormap for depth coding
cmap = jet(num_slices);

% Populate the projection using ROI masks
for r = 1:num_rois
    roi_mask = hex_rois{1}{r}; 
    roi_intensity = max_intensity_per_roi(r);
    roi_depth = max_depth_per_roi(r);

    if roi_depth > 0
        color = cmap(roi_depth, :);
        for c = 1:3
            depth_coded_projection(:,:,c) = max(depth_coded_projection(:,:,c), color(c) * roi_mask * abs(roi_intensity));
        end
    end
end

% Normalize for visualization
depth_coded_projection = mat2gray(depth_coded_projection);

% Plot the max projection
figure;
imshow(depth_coded_projection);
title('Depth-coded Max Intensity Projection of Stimulus-Responsive ROIs');
colormap(cmap);
cbar = colorbar('Ticks', linspace(0, 1, num_slices), 'TickLabels', 1:num_slices);
ylabel(cbar, 'Depth (z-plane)', 'FontSize', 12, 'FontWeight', 'bold');

% Save figure in the parent folder
saveas(gcf, fullfile(parent_folder, 'depth_coded_max_projection.png'));

fprintf('Max projection saved to: %s\n', parent_folder);