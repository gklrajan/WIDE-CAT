%% Stimulus vs. Non-Stimulus Correlation Analysis Across Whole Brain
clear; clc;

%%
% Load Data
input_file = 'D:\Gokul\2024-Widefield\data\rl_deconvolved\01_preprocessed_fish5_good-definiteLearner_rl_deconvolved\results\preprocessed_fish5_good-definiteLearner__rl_deconvolved_analysis.mat';
%input_file = 'D:\Gokul\2024-Widefield\data\rl_deconvolved\02_preprocessed_lnm_ctrl_fish4_rl_deconvolved\results\preprocessed_lnm_ctrl_fish4__rl_deconvolved_analysis.mat';
load(input_file, 'dff_signals');
load(input_file, 'hex_rois');
load(input_file, 'stim_periods_per_slice');

% Ensure data is consistent
[num_slices, num_volumes, num_rois] = size(dff_signals);
dff_signals = dff_signals(:,:,:);

%%
% Flatten into [voxels x time] and build mapping
all_voxels = reshape(dff_signals, [num_slices * num_rois, num_volumes]);
voxel_index_map = zeros(num_slices * num_rois, 2); % [slice, roi]
for z = 1:num_slices
    for r = 1:num_rois
        idx = (z - 1) * num_rois + r;
        voxel_index_map(idx, :) = [z, r];
    end
end

%%
% Filter voxels based on std threshold (top 80%)

voxel_std = std(all_voxels, 0, 2);
threshold = prctile(voxel_std, 70);  % Keep voxels above 20th percentile
valid_voxel_mask = voxel_std > threshold;
filtered_voxels = all_voxels(valid_voxel_mask, :);
filtered_map = voxel_index_map(valid_voxel_mask, :);

fprintf('Retained %d of %d voxels (%.2f%%) for correlation analysis.\n', ...
    sum(valid_voxel_mask), length(valid_voxel_mask), 100*mean(valid_voxel_mask));

%%
% Define stimulus vs non-stim periods

stim_onsets = unique(stim_periods_per_slice(:, 2));
stim_period = false(1, num_volumes);
nonstim_period = false(1, num_volumes);

for i = 1:length(stim_onsets)
    stim_range = stim_onsets(i):min(stim_onsets(i)+5, num_volumes);  % 6 volume stim period
    stim_period(stim_range) = true;
    pre_stim_range = max(stim_onsets(i)-6, 1):stim_onsets(i)-1;      % 6 volume pre-stim
    nonstim_period(pre_stim_range) = true;
end

%%
% Compute Correlation Matrices
fprintf('Computing correlation matrices...\n');

corr_stim = corrcoef(filtered_voxels(:, stim_period)');
corr_nonstim = corrcoef(filtered_voxels(:, nonstim_period)');
corr_diff = corr_stim - corr_nonstim;

fprintf('Correlation matrices computed.\n');

%%
% Save Results
output_folder = fileparts(fileparts(input_file));
save(fullfile(output_folder, 'correlation_results.mat'), 'corr_stim', 'corr_nonstim', 'corr_diff', 'filtered_map');

fprintf('Correlation matrices and voxel mappings saved to %s\n', output_folder);

%%
% Optional: Visualize Summary Stats
figure;
imagesc(corr_diff);
caxis([-1 1]);
axis image;
colorbar;
title('Difference in Correlation (Stim - Non-Stim)');
saveas(gcf, fullfile(output_folder, 'corr_diff_matrix.png'));

fprintf('Done.\n');

%% 
mask=ones(512,1024);
% Plot brain
plot_correlation_voxels(filtered_map, hex_rois, corr_diff, 0.8, '>0.8', mask);
plot_correlation_voxels(filtered_map, hex_rois, corr_diff, 0.8, '<-0.8', mask);

%% 
% Get high and low correlation voxel pairs
[high_i, high_j] = find(triu(corr_diff > 0.8, 1));
[low_i,  low_j]  = find(triu(corr_diff < -0.8, 1));
% Map to unique voxel indices (z, roi)
high_corr_voxels = unique([filtered_map(high_i, :); filtered_map(high_j, :)], 'rows');
low_corr_voxels  = unique([filtered_map(low_i,  :); filtered_map(low_j,  :)], 'rows');

% Plot activity
plot_dff_time_traces(dff_signals, high_corr_voxels, 10, 'high', stim_periods_per_slice);
plot_dff_time_traces(dff_signals, low_corr_voxels, 10, 'low', stim_periods_per_slice);
