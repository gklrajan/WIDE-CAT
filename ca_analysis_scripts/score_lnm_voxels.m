clear; clc;

%% Parameters
vols_to_eval=[210,350];
vols_to_plot=[210,350];

%% Load Data
input_file = 'D:\Gokul\2024-Widefield\data\rl_deconvolved\01_preprocessed_fish5_good-definiteLearner_rl_deconvolved\results\preprocessed_fish5_good-definiteLearner__rl_deconvolved_analysis.mat';
%input_file = 'D:\Gokul\2024-Widefield\data\rl_deconvolved\02_preprocessed_lnm_ctrl_fish4_rl_deconvolved\results\preprocessed_lnm_ctrl_fish4__rl_deconvolved_analysis.mat';
load(input_file, 'dff_signals');
load(input_file, 'hex_rois');
load(input_file, 'stim_periods_per_slice');

% Ensure data is consistent
[num_slices, num_volumes, num_rois] = size(dff_signals);
dff_signals = dff_signals(:,:,:);

%% Run analysis
voxel_scores=plot_stim_specific_voxels(dff_signals, stim_periods_per_slice, vols_to_eval, 5, vols_to_plot);
plot_top_voxels_depth_map(voxel_scores, hex_rois, 5);
