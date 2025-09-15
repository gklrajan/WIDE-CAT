%% Calcium Imaging Analysis Pipeline for WIDE-CAT (Widefield Calcium Analysis Toolbox).
% Gokul Rajan, Orger Lab, Champalimaud Foundation. 2025.

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
% Ensure preprocessing (binning, dark image subtraction, motion correction, deconvolution) is done beforehand.
% Then run this section by section.

%%
% Add necessary functions to MATLAB path
if ismac
    addpath(genpath('/Users/gokulrajan/Documents/MATLAB/ZebranalysisSystem/zebraFunctions')); 
elseif ispc
    addpath(genpath('D:\Gokul\matlab\widefield\utility')); % TS workstation
    %addpath(genpath('G:\GR\Lab-SW\widefield\utility')); % OpenLab workstation
end

%% Parameters
mat_path = 'D:\Gokul\2024-Widefield\data\rl_deconvolved\02_preprocessed_lnm_ctrl_fish4_rl_deconvolved\preprocessed_lnm_ctrl_fish4__rl_deconvolved.mat';
frames_per_volume = 40;
stim_start_volume = 17;  % 17 for vis and 6 for pure tone
stim_repeat_volume = stim_start_volume; % Corrected stimulus interval
stim_duration_volumes = 6; % 6 for vis and 1 for pure tone
plane_idx = 20; % Representative plane for verification
slice_acquisition_time = 0.050;  % Only stabilization delay (50ms per slice)
batch_size = 40; % Number of ROIs processed per batch (adjust if needed)

%% Step 1: Load metadata from MAT file
fprintf('Loading stack metadata...\n');
m = matfile(mat_path, 'Writable', false); % Open MAT file for efficient reading
total_slices = size(m, 'stack', 3);  % Get total Z slices
n_volumes = total_slices / frames_per_volume;  % Compute number of volumes
fprintf('Auto-detected %d volumes in the dataset.\n', n_volumes);

% Compute Per-Slice Stimulus Timing
fprintf('Computing per-slice stimulus timing...\n');
stim_periods_per_slice = compute_stim_timing(n_volumes, stim_start_volume, stim_repeat_volume, stim_duration_volumes, frames_per_volume, slice_acquisition_time);
%tone_periods=compute_pure_tone_stim(n_volumes,frames_per_volume,slice_acquisition_time);
%% Step 2: Select a large background ROI
fprintf('Selecting background ROI...\n');
bg_mask = select_background_mask(m.stack(:,:,1)); % Select background ROI

%% Step 3: Extract background signal over time
fprintf('Extracting background signal from selected ROI...\n');
bg_signal = extract_bg_signal(mat_path, bg_mask, frames_per_volume);

%% Step 4: Select Brain Mask
fprintf('Selecting brain mask...\n');
brain_mask = select_and_visualize_mask(mat_path, frames_per_volume);

%% Step 5: Hexagonal ROI Segmentation
fprintf('Segmenting into hexagonal ROIs...\n');
hex_rois = segment_hexagonal_rois(mat_path, brain_mask, 7); % After binning: 7-pixel radius - 9.1um rad/ 18um dia x-y and 5um z
%visualize_hexagonal_rois(mat_path, hex_rois,batch_size); % Verify segmentation
%uiwait();

%% Step 6: Extract ROI signals using batch processing
fprintf('Extracting ROI signals...\n');
roi_signals = extract_roi_signals_parallel(mat_path, hex_rois, frames_per_volume);

%% Step 7: Apply background correction to ROI signals
fprintf('Applying background subtraction to ROI signals...\n');
corrected_roi_signals = subtract_background_from_signals(roi_signals, bg_signal);

%% Step 8: Compute ΔF/F using rolling baseline (30-frame default)
fprintf('Calculating ΔF/F...\n');
dff_signals = calculate_dff_rolling(corrected_roi_signals, 50);

%% Step 9: Visualize df/F
fprintf('Visualizing df/F...\n');
create_dff_max_projection(dff_signals, hex_rois,1:180);

%Compute Stimulus Matrix

if exist('tone_periods', 'var') 
    stim_periods_per_slice = convert_tone_periods_to_stim_slices(tone_periods);
    fprintf('Using pure tone stimulus matrix.\n');
end

plot_dff_raster_with_stim(dff_signals, stim_periods_per_slice, 1:40, 1:180);

%% Save Results in `results/` Folder
[input_folder, filename, ~] = fileparts(mat_path);
results_folder = fullfile(input_folder, 'results');

if ~exist(results_folder, 'dir')
    mkdir(results_folder);
end

% Save stimulus slice timing for later regression analysis
save(fullfile(results_folder, 'stim_slices.mat'), 'stim_periods_per_slice');
fprintf('Stimulus timing saved.\n');

output_file = fullfile(results_folder, [filename, '_analysis.mat']);

file_info = struct();
file_info.input_file = filename;
file_info.processed_on = datestr(now);
file_info.frames_per_volume = frames_per_volume;
file_info.slice_acquisition_time = slice_acquisition_time;

save(output_file, 'dff_signals', 'hex_rois', 'stim_periods_per_slice', 'file_info', '-v7.3');
fprintf('Results saved to: %s\n', output_file);
fprintf('Pipeline completed.\n');