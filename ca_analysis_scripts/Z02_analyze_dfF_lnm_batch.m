%% Batch Stim-Driven dF/F Analysis with ROI Resection from Mean Volume
% Gokul Rajan, Orger Lab, Champalimaud Foundation. 2025

% WIDE-CAT: A low-cost, open-source toolbox for widefield calcium imaging 
% and voxel-based analysis, with optional structural enhancement via 
% deconvolution or computational sectioning.
% Copyright (C) 2025 Gokul Rajan
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program. If not, see <https://www.gnu.org/licenses/>.

%%
clear; clc;

%% Parameters
INPUT_ROOT = 'F:\WilDeCaT\Data\003_adults_lnm_ctrl_3day-nonUS-training_';
frames_per_volume = 40;
vol_duration_sec = 1.9;
stim_duration = 6;
stim_interval = 17;
pre_vols = 2;
post_vols = 2;
min_corr = 0.3; % correlation threshold
roi_radius = 7;  % hex ROI radius
gauss_sigma = 5; % Gaussian blob size in pixels

% Collect ROI scores from all animals
all_scores = struct();

%% Locate dataset folders

result_root = fullfile(INPUT_ROOT, 'results');
result_dirs = dir(fullfile(result_root));
result_dirs = result_dirs([result_dirs.isdir] & ~startsWith({result_dirs.name}, '.'));
result_dirs = result_dirs(~strcmp({result_dirs.name}, 'results'));  % ignore "results" as a dataset
result_dirs = result_dirs( [result_dirs.isdir] & ~ismember( {result_dirs.name}, {'.','..'} ) );

for i = 1:numel(result_dirs)
    dataset = result_dirs(i).name;
    data_root = fullfile(result_dirs(i).folder, dataset);
    dfF_path  = fullfile(data_root, 'dff_analyzed');
    if ~exist(dfF_path, 'dir'), mkdir(dfF_path); end

    fprintf('\n=== Processing %s ===\n', dataset);

    % Load required files
    load(fullfile(data_root, 'dfF', 'dff_signals.mat'), 'dff');
    load(fullfile(data_root, 'dfF', 'stim_slices.mat'), 'stim_periods_per_slice');
    load(fullfile(data_root, 'dfF', 'brain_mask.mat'), 'brain_mask');
    load(fullfile(data_root, 'dfF', 'mean_volume.mat'), 'mean_vol');
    load(fullfile(data_root, 'dfF', 'hex_rois.mat'), 'hex_rois')

    if ndims(dff) == 3
        dff = permute(dff, [2, 1, 3]);        
        dff = reshape(dff, size(dff,1), []);  
        fprintf('  Reshaped dff to [%d × %d]\n', size(dff,1), size(dff,2));
    end

    assert(size(dff,2) == sum(cellfun(@numel, hex_rois)), 'Mismatch between dff ROIs and hex_rois count');

    [nVols, nROIs] = size(dff);

    % Build sustained and onset regressors with GCaMP6s convolution
    stim_onsets = unique(stim_periods_per_slice(:,2));
    sustained_vec = zeros(nVols,1);
    onset_vec = zeros(nVols,1);

    for onset = stim_onsets(:)'
        idxs = onset : min(onset + stim_duration - 1, nVols);
        sustained_vec(idxs) = 1;
        onset_vec(onset) = 1;
    end

    % Create GCaMP6s kernel (decay tau ~1.3s)
    tau = 1.3; 
    t = (0:30)*vol_duration_sec; 
    kernel = exp(-t/tau);
    kernel = kernel / sum(kernel);

    % Convolve regressors
    sustained_regressor_full = conv(sustained_vec,kernel,'same');
    onset_regressor_full = conv(onset_vec,kernel,'same');

    expected_len = pre_vols + stim_duration + post_vols;

    %% Create subsets: early and full
    cutoff_vol = round(nVols*0.25);
    sustained_regressor_early = sustained_regressor_full(1:cutoff_vol);
    onset_regressor_early = onset_regressor_full(1:cutoff_vol);
    dff_early = dff(1:cutoff_vol,:);

    %% Run for full dataset
    [corr_sust_f, corr_onset_f, b_sust_f, b_onset_f, R2_f] = analyze_block(dff, sustained_regressor_full, onset_regressor_full);

    %% Run for early dataset
    [corr_sust_e, corr_onset_e, b_sust_e, b_onset_e, R2_e] = analyze_block(dff_early, sustained_regressor_early, onset_regressor_early);

    %% Threshold ROIs separately
    top_sust_f = find(corr_sust_f >= min_corr);
    top_onset_f = find(corr_onset_f >= min_corr);
    top_sust_e = find(corr_sust_e >= min_corr);
    top_onset_e = find(corr_onset_e >= min_corr);

    %% Store all results
    all_scores(i).fish = dataset;
    
    all_scores(i).full.corr_sustained = corr_sust_f;
    all_scores(i).full.corr_onset = corr_onset_f;
    all_scores(i).full.b_sustained = b_sust_f;
    all_scores(i).full.b_onset = b_onset_f;
    all_scores(i).full.R2 = R2_f;
    all_scores(i).full.top_sust = top_sust_f;
    all_scores(i).full.top_onset = top_onset_f;
    
    all_scores(i).early.corr_sustained = corr_sust_e;
    all_scores(i).early.corr_onset = corr_onset_e;
    all_scores(i).early.b_sustained = b_sust_e;
    all_scores(i).early.b_onset = b_onset_e;
    all_scores(i).early.R2 = R2_e;
    all_scores(i).early.top_sust = top_sust_e;
    all_scores(i).early.top_onset = top_onset_e;

    %% Plot full dataset
    plot_summary('Full', dataset, pre_vols, post_vols, stim_duration, mean_vol, brain_mask, hex_rois, corr_sust_f, corr_onset_f, dff, sustained_regressor_full, onset_regressor_full, top_sust_f, top_onset_f, stim_onsets, expected_len, gauss_sigma, dfF_path);

    %% Plot early dataset
    plot_summary('Early', dataset, pre_vols, post_vols, stim_duration, mean_vol, brain_mask, hex_rois, corr_sust_e, corr_onset_e, dff_early, sustained_regressor_early, onset_regressor_early, top_sust_e, top_onset_e, stim_onsets, expected_len, gauss_sigma, dfF_path);

    fprintf('Saved all plots for %s\n', dataset);

    clearvars -except INPUT_ROOT frames_per_volume vol_duration_sec ...
        stim_duration stim_interval pre_vols post_vols min_corr ...
        roi_radius gauss_sigma result_dirs i all_scores
end

% Save pooled scores
save(fullfile(INPUT_ROOT, 'results', 'all_scores.mat'), 'all_scores', '-v7.3'); 
fprintf('\n=== ALL DATASETS COMPLETE ===\n');
