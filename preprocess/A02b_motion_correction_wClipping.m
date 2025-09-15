%% Rigid Motion Correction for 1P Widefield Imaging with Robust Reference and Frame-wise Clipping+Normalization

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

% Add useful functions to MATLAB path
if ismac
    addpath(genpath('/Users/gokulrajan/Documents/MATLAB/ZebranalysisSystem/zebraFunctions')); 
else
    addpath(genpath('D:\Gokul\matlab\widefield\utility'));
end

% Paths
inputRoot = 'D:\Gokul\2024-Widefield\data\preprocessed';
outputRoot = 'D:\Gokul\2024-Widefield\data\motion_corrected_rigid_clip';
if ~exist(outputRoot, 'dir'); mkdir(outputRoot); end

% Parameters
slices_per_vol = 40;
clip_for_alignment = true;
clip_percentile = 98;
exclude_slice_index_from_correlation = 1;

% Discover data folders
inputFolders = dir(fullfile(inputRoot, 'thisone_*'));

for i = 1:length(inputFolders)
    folderName = inputFolders(i).name;
    inputPath = fullfile(inputRoot, folderName, [folderName '.tif']);
    outputSubFolder = fullfile(outputRoot, folderName);
    if ~exist(outputSubFolder, 'dir'); mkdir(outputSubFolder); end

    % Output paths
    outputMatPath = fullfile(outputSubFolder, [folderName '_motion_corrected.mat']);
    outputTiffPath = fullfile(outputSubFolder, [folderName '_motion_corrected.tif']);
    figPath = fullfile(outputSubFolder, [folderName '_motion_plot.png']);
    motionMetricsPath = fullfile(outputSubFolder, [folderName '_motion_metrics.mat']);

    fprintf('Processing: %s\n', inputPath);

    % Load TIFF
    Yf = load_tiff_stack(inputPath);
    Yf = single(Yf);
    [d1, d2, T] = size(Yf);
    num_volumes = T / slices_per_vol;
    if mod(T, slices_per_vol) ~= 0
        error('Frame count not divisible by %d.', slices_per_vol);
    end

    max_shift = min(3, round(0.01 * min(d1, d2)));
    Mpr = zeros(size(Yf), 'single');
    shifts_all = zeros(num_volumes, slices_per_vol, 2);
    pre_corr = nan(num_volumes, slices_per_vol);
    post_corr = nan(num_volumes, slices_per_vol);

    for z = 1:slices_per_vol
        fprintf('Slice %d/%d\n', z, slices_per_vol);
        slice_frames = z:slices_per_vol:T;
        Yf_slice = Yf(:,:,slice_frames);

        % Reference from first 20% of frames
        n_ref = max(10, round(0.2 * size(Yf_slice, 3)));
        ref_slice = median(Yf_slice(:,:,1:n_ref), 3);

        % Prepare input for alignment
        if clip_for_alignment
            Yf_clipped = zeros(size(Yf_slice));
            for f = 1:size(Yf_slice, 3)
                frame = Yf_slice(:,:,f);
                high = prctile(frame(:), clip_percentile);
                frame(frame > high) = high;
                Yf_clipped(:,:,f) = frame / high;  % Normalize to [0, 1]
            end
        else
            Yf_clipped = Yf_slice;
        end

        options_r = NoRMCorreSetParms(...
            'd1', d1, 'd2', d2, 'bin_width', 150, 'max_shift', max_shift, 'iter', 1, 'correct_bidir', false);

        [~, shifts] = normcorre_batch(Yf_clipped, options_r, ref_slice);
        Mpr_slice = apply_shifts(Yf_slice, shifts, options_r);

        Mpr(:,:,slice_frames) = Mpr_slice;
        shifts_all(:,z,:) = cat(1, shifts(:).shifts);

        if z ~= exclude_slice_index_from_correlation
            pre_corr(:,z) = motion_metrics(Yf_slice, 5);
            post_corr(:,z) = motion_metrics(Mpr_slice, 5);
        end
    end

    % Compute median correlation per volume
    median_pre_corr = median(pre_corr, 2, 'omitnan');
    median_post_corr = median(post_corr, 2, 'omitnan');

    % Compute median shift per volume
    median_shift_x = median(shifts_all(:,:,1), 2, 'omitnan');
    median_shift_y = median(shifts_all(:,:,2), 2, 'omitnan');

    % Save outputs
    save(motionMetricsPath, 'pre_corr', 'post_corr', 'median_pre_corr', 'median_post_corr', 'median_shift_x', 'median_shift_y');
    save(outputMatPath, 'Mpr', '-v7.3');
    save_tiff_stack(outputTiffPath, Mpr);
    plot_shifts(median_shift_x, median_shift_y, fullfile(outputSubFolder, 'median_shift_plot.png'));
    plot_motion_metrics(median_pre_corr, median_post_corr, fullfile(outputSubFolder, [folderName '_correlation_metrics.png']));
end
fprintf('Motion correction complete.\n');


function save_tiff_stack(filename, imgStack)
    if exist(filename, 'file'); delete(filename); end
    t = Tiff(filename, 'w8');
    tagstruct = struct('ImageLength', size(imgStack, 1), 'ImageWidth', size(imgStack, 2), ...
        'Photometric', Tiff.Photometric.MinIsBlack, 'BitsPerSample', 16, ...
        'SamplesPerPixel', 1, 'PlanarConfiguration', Tiff.PlanarConfiguration.Chunky, ...
        'Software', 'MATLAB', 'Compression', Tiff.Compression.None);
    for k = 1:size(imgStack, 3)
        t.setTag(tagstruct);
        t.write(uint16(imgStack(:,:,k) * 65535));
        if k < size(imgStack, 3); t.writeDirectory(); end
    end
    t.close();
end
