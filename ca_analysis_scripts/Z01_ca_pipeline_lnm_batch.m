%% Batch dF/F Analysis for WIDE-CAT

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
% Streams from Mpr, skips processed datasets, includes correct background subtraction,
% and saves everything under results/<dataset>/dfF/

%%
clear; clc;

%% — USER PARAMETERS — 
INPUT_ROOT             = 'F:\WilDeCaT\Data\003_adults_lnm_ctrl_3day-nonUS-training_'
RESULT_ROOT            = fullfile(INPUT_ROOT, 'results');
frames_per_volume      = 40;
stim_start_volume      = 17;    
stim_repeat_volume     = stim_start_volume;
stim_duration_volumes  = 6;     
slice_acquisition_time = 0.050; 
baseline_window        = 50;    
hex_radius             = 7;

%% — PATH SETUP —
if ispc
    addpath(genpath('D:\Gokul\matlab\widefield\utility'));
elseif ismac
    addpath(genpath('/Users/gokulrajan/Documents/MATLAB/ZebranalysisSystem/zebraFunctions'));
end

%% — FIND DATASET FOLDERS —
D       = dir(RESULT_ROOT);
isub    = [D.isdir] & ~ismember({D.name}, {'.','..'});
subdirs = {D(isub).name};

for i = 1:numel(subdirs)
    subn     = subdirs{i};
    outDir   = fullfile(RESULT_ROOT, subn);
    dfF_dir  = fullfile(outDir, 'dfF');

    if exist(dfF_dir, 'dir')
        fprintf('Skipping %s (dfF exists)\n', subn);
        continue;
    end
    mkdir(dfF_dir);
    fprintf('\n=== Processing %s ===\n', subn);

    % Locate .mat
    matpat = fullfile(outDir, [subn '*_motion_corrected.mat']);
    F = dir(matpat);
    if isempty(F)
        warning('No motion_corrected.mat -> skipping %s\n', subn);
        continue;
    end
    motion_mat = fullfile(outDir, F(1).name);
    m = matfile(motion_mat, 'Writable', false);
    
    [H, W, Z] = size(m, 'Mpr');
    if mod(Z, frames_per_volume) ~= 0
        warning('Z = %d not divisible by %d -> skipping %s', Z, frames_per_volume, subn);
        continue;
    end
    n_volumes = Z / frames_per_volume;

    %% Step 1: Compute and save mean volume
    fprintf('  Computing mean-volume...\n');
    mean_vol = mean(m.Mpr(:,:,1:frames_per_volume), 3);
    save(fullfile(dfF_dir, 'mean_volume.mat'), 'mean_vol');
    imwrite(mat2gray(mean_vol), fullfile(dfF_dir, 'mean_volume.png'));

    %% Step 2: Background mask (interactive)
    fprintf('  Select background ROI...\n');
    figure; imshow(mean_vol, []); title('Draw background ROI');
    h_bg = drawfreehand('Color','c');
    bg_mask = createMask(h_bg); close;
    save(fullfile(dfF_dir, 'bg_mask.mat'), 'bg_mask');

    %% Step 3: Brain mask (interactive)
    fprintf('  Draw brain mask on mean volume...\n');
    figure; imshow(mean_vol, []); title('Draw brain mask');
    h_brain = drawfreehand('Color','r');
    mask2d = createMask(h_brain); close;
    brain_mask = repmat(mask2d, [1 1 frames_per_volume]);
    save(fullfile(dfF_dir, 'brain_mask.mat'), 'brain_mask');

    %% Step 4: Stimulus periods
    fprintf('  Computing stimulus timing...\n');
    stim_periods_per_slice = compute_stim_timing( ...
        n_volumes, stim_start_volume, stim_repeat_volume, ...
        stim_duration_volumes, frames_per_volume, slice_acquisition_time);
    save(fullfile(dfF_dir, 'stim_slices.mat'), 'stim_periods_per_slice');

    %% Step 5: ROI segmentation
    fprintf('  Segmenting ROIs...\n');
    hex_rois = segment_hexagonal_rois(motion_mat, brain_mask, hex_radius);
    save(fullfile(dfF_dir, 'hex_rois.mat'), 'hex_rois', '-v7.3');

    %% Step 6: ROI signal extraction
    fprintf('  Extracting ROI signals...\n');
    roi_signals = extract_roi_signals_parallel(motion_mat, hex_rois, frames_per_volume);

    %% Step 7: Background subtraction
    fprintf('  Background subtraction...\n');
    bg_signal = extract_bg_signal(motion_mat, bg_mask, frames_per_volume);
    roi_signals_corrected = subtract_background_from_signals(roi_signals, bg_signal);
    save(fullfile(dfF_dir, 'roi_signals_corrected.mat'), 'roi_signals_corrected', 'bg_signal');

    %% Step 8: ΔF/F
    fprintf('  Calculating ΔF/F...\n');
    dff = calculate_dff_rolling(roi_signals_corrected, baseline_window);
    save(fullfile(dfF_dir, 'dff_signals.mat'), 'dff');

    %% Step 9: Visualization (optional)
    try
        create_dff_max_projection(dff, hex_rois, 1:frames_per_volume*2);
        plot_dff_raster_with_stim(dff, stim_periods_per_slice, ...
            1:frames_per_volume, 1:size(dff,2));
    catch
        warning('Visualization failed for %s', subn);
    end

    %% Step 10: Metadata
    file_info = struct();
    file_info.dataset = subn;
    file_info.processed_on = datestr(now);
    file_info.frames_per_volume = frames_per_volume;
    file_info.slice_acquisition_time = slice_acquisition_time;
    save(fullfile(dfF_dir, 'file_info.mat'), 'file_info');

    fprintf('  Done -> %s\n', dfF_dir);
end

fprintf('\n=== ALL DATASETS COMPLETE ===\n');