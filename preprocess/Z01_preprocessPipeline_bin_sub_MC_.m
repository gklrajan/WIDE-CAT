%% Widefield Calcium Imaging: Preprocessing + Motion Correction Pipeline

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

% This script recursively processes subfolders under INPUT_ROOT, where each dataset
% is stored as a folder of TIFF frames (one subfolder per dataset). It performs:
%   1) 2x2 spatial binning [+ dark-image subtraction]
%   2) Rigid motion correction (slice-wise) with per-frame clipping & normalization
%   3) Saves preprocessed stacks, motion-corrected stacks, TIFF export, and QC metrics

%%
clear; clc;

%% — USER PARAMETERS —
INPUT_ROOT = 'D:\Gokul\2026b_data\d' %'F:\WilDeCaT\Data\004_huc-sound_'; % root folder with subfolders of TIFFs
RESULT_ROOT = fullfile(INPUT_ROOT, 'results'); % where processed results go
DARK_IMAGE = 'D:/Gokul/2024-Widefield/data/preprocessed/AVG_dark_img_binned2_allCovered_.tif';
slices_per_vol = 20; % number of z-slices per volume
clip_percentile = 98; % percentile for per-frame clipping
max_shift = 4; % max allowed shift (pixels)
exclude_z = 1; % slice index to exclude from correlation QC

%% — SETUP —
addpath(genpath('D:/Gokul/matlab/widefield/utility'));
if ~exist(RESULT_ROOT, 'dir'), mkdir(RESULT_ROOT); end
% load dark image once
dark_img = im2single(imread(DARK_IMAGE));

% list subfolders under INPUT_ROOT, excluding '.', '..', and 'results'
D = dir(INPUT_ROOT);
isub = [D.isdir] & ~ismember({D.name}, {'.', '..', 'results'});
subfolders = {D(isub).name};

%% — PROCESS EACH DATASET —
for i = 1:numel(subfolders)
    subn = subfolders{i};
    inDir = fullfile(INPUT_ROOT, subn);
    outDir = fullfile(RESULT_ROOT, subn);
    % skip if already processed
    if exist(outDir, 'dir')
        fprintf('Skipping dataset (already exists): %s\n', subn);
        continue;
    end

    mkdir(outDir);
    fprintf('Processing dataset: %s\n', subn);

    try
        % STEP 1: Load raw TIFF frames
        Yraw = load_tiff_folder(inDir);
        Yraw = im2single(Yraw);
        [H, W, T] = size(Yraw);

        % STEP 2: Preprocessing
        Hb = floor(H / 2); Wb = floor(W / 2);
        Ypre = zeros(Hb, Wb, T, 'single');

        for t = 1:T
            I = imresize(Yraw(:, :, t), 0.5, 'bilinear');
            %   I = I - dark_img;
            %   I(I<0) = 0;
            Ypre(:, :, t) = I;
        end

        clear Yraw;

        % STEP 3: Motion Correction
        Yf = Ypre; clear Ypre;
        nvol = T / slices_per_vol;
        Mpr = zeros(size(Yf), 'single');
        shifts = zeros(nvol, slices_per_vol, 2);
        preCorr = nan(nvol, slices_per_vol);
        postCorr = nan(nvol, slices_per_vol);

        opts = NoRMCorreSetParms('d1', size(Yf, 1), 'd2', size(Yf, 2), 'bin_width', 150, ...
            'max_shift', max_shift, 'iter', 1, 'correct_bidir', false);

        for z = 1:slices_per_vol
            slice_idx = z:slices_per_vol:T;
            slab = Yf(:, :, slice_idx);
            nref = max(10, round(0.2 * size(slab, 3)));
            ref = median(slab(:, :, 1:nref), 3);
            slab_clipped = slab;
            clip_val = prctile(slab_clipped(:), clip_percentile);
            slab_clipped(slab_clipped > clip_val) = clip_val;
            Yf_clipped = slab_clipped / clip_val;

            [~, cc] = normcorre_batch(Yf_clipped, opts, ref);
            Mz = apply_shifts(slab, cc, opts);
            Mpr(:, :, slice_idx) = Mz;
            shifts(:, z, :) = cat(1, cc(:).shifts);

            if z ~= exclude_z
                preCorr(:, z) = motion_metrics(slab, 5);
                postCorr(:, z) = motion_metrics(Mz, 5);
            end

        end

        % summarize per-volume metrics
        medPre = median(preCorr, 2, 'omitnan');
        medPost = median(postCorr, 2, 'omitnan');
        medX = median(shifts(:, :, 1), 2, 'omitnan');
        medY = median(shifts(:, :, 2), 2, 'omitnan');

        % save results
        save(fullfile(outDir, [subn '_motion_corrected.mat']), 'Mpr', '-v7.3');
        %       save_tiff_stack(fullfile(outDir,[subn '_motion_corrected.tif']), Mpr);
        save(fullfile(outDir, [subn '_motion_metrics.mat']), 'preCorr', 'postCorr', 'medPre', 'medPost', 'medX', 'medY');

        % QC plots
        plot_shifts(medX, medY, fullfile(outDir, 'median_shift_plot.png'));
        plot_motion_metrics(medPre, medPost, fullfile(outDir, 'median_corr_plot.png'));

        fprintf('Completed dataset: %s\n', subn);
    catch ME
        warning('Error processing %s: %s', subn, ME.message);
        continue;
    end

    % clear large variables
    clear Yf Mpr shifts preCorr postCorr medPre medPost medX medY;
end

fprintf('=== All new datasets processed! ===\n');

%% — HELPER FUNCTIONS —
function imgStack = load_tiff_folder(folderPath)
    F = dir(fullfile(folderPath, '*.tif'));
    base = folderPath;

    if isempty(F)
        D = dir(folderPath);

        for k = 1:numel(D)

            if D(k).isdir && ~startsWith(D(k).name, '.')
                C = dir(fullfile(folderPath, D(k).name, '*.tif'));

                if ~isempty(C)
                    F = C; base = fullfile(folderPath, D(k).name); break;
                end

            end

        end

    end

    if isempty(F)
        error('No TIFFs found in %s', folderPath);
    end

    [~, ord] = sort({F.name}); F = F(ord);
    info = imfinfo(fullfile(base, F(1).name));
    H = info.Height; W = info.Width; T = numel(F);
    imgStack = zeros(H, W, T, 'single');

    for t = 1:T
        imgStack(:, :, t) = im2single(imread(fullfile(base, F(t).name)));
    end

end

function save_tiff_stack(fname, stack)
    if exist(fname, 'file'), delete(fname); end
    t = Tiff(fname, 'w8');
    tag.ImageLength = size(stack, 1);
    tag.ImageWidth = size(stack, 2);
    tag.Photometric = Tiff.Photometric.MinIsBlack;
    tag.BitsPerSample = 16;
    tag.SamplesPerPixel = 1;
    tag.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
    tag.Software = 'MATLAB';
    tag.Compression = Tiff.Compression.None;

    for z = 1:size(stack, 3)
        t.setTag(tag);
        t.write(uint16(stack(:, :, z) * 65535));
        if z < size(stack, 3), t.writeDirectory(); end
    end

    t.close();
end

function plot_shifts(sx, sy, pth)
    figure; subplot(2, 1, 1); plot(sx, 'r'); title('Median X Shift per Volume'); ylabel('px');
    subplot(2, 1, 2); plot(sy, 'b'); title('Median Y Shift per Volume'); xlabel('Volume'); ylabel('px');
    saveas(gcf, pth); close(gcf);
end

function plot_motion_metrics(pre, post, pth)
    figure; plot(pre, 'r'); hold on; plot(post, 'g'); legend('Pre', 'Post');
    title('Median Correlation per Volume'); xlabel('Volume'); ylabel('Correlation');
    saveas(gcf, pth); close(gcf);
end
