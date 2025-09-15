% Rigid Motion Correction for 1P Widefield Imaging (Slice-wise Correction with Fixed Reference)
clear; clc;

% Add useful functions to MATLAB path
if ismac
    addpath(genpath('/Users/gokulrajan/Documents/MATLAB/ZebranalysisSystem/zebraFunctions')); 
elseif ispc
    addpath(genpath('D:\Gokul\matlab\widefield\utility'));
end

% Paths
inputRoot = 'D:/Gokul/2024-Widefield/data/preprocessed/';
outputRoot = 'D:/Gokul/2024-Widefield/data/motion_corrected_rigid/';

% Ensure output directory exists
if ~exist(outputRoot, 'dir')
    mkdir(outputRoot);
end

% Define parameters
slices_per_vol = 40; % 40 slices per volume
reference_frames = 100; % **First 100 frames per Z used as reference (DEFAULT)**

% Get all preprocessed folders
inputFolders = dir(fullfile(inputRoot, 'preprocessed_*'));

for i = 1:length(inputFolders)
    folderName = inputFolders(i).name;
    inputPath = fullfile(inputRoot, folderName, [folderName '.tif']);

    % Create output subfolder using the dataset name
    outputSubFolder = fullfile(outputRoot, folderName);
    if ~exist(outputSubFolder, 'dir')
        mkdir(outputSubFolder);
    end

    % Define output filenames
    outputMatPath = fullfile(outputSubFolder, [folderName '_motion_corrected.mat']);
    outputTiffPath = fullfile(outputSubFolder, [folderName '_motion_corrected.tif']);
    figPath = fullfile(outputSubFolder, [folderName '_motion_plot.png']);
    motionMetricsPath = fullfile(outputSubFolder, [folderName '_motion_metrics.mat']);

    fprintf('Processing: %s\n', inputPath);

    % Load TIFF stack
    Yf = load_tiff_stack(inputPath);
    Yf = single(Yf);  % Convert to single precision
    [d1, d2, T] = size(Yf);

    % Ensure T is a multiple of slices_per_vol
    num_volumes = T / slices_per_vol;
    if mod(T, slices_per_vol) ~= 0
        error('Number of frames is not a multiple of 40. Check TIFF stack structure.');
    end

    % Compute max shift dynamically
    max_shift = round(0.02 * min(d1, d2)); % ~6% of min(d1, d2)

    % Output storage
    Mpr = zeros(size(Yf), 'single');
    shifts_all = zeros(num_volumes, slices_per_vol, 2); % Store shifts
    pre_corr = zeros(num_volumes, slices_per_vol); % Pre-Correction Correlation
    post_corr = zeros(num_volumes, slices_per_vol); % Post-Correction Correlation

    % ---- Slice-wise Motion Correction ----
    for z = 1:slices_per_vol
        fprintf('Processing slice %d/%d\n', z, slices_per_vol);

        % Extract frames corresponding to slice position `z` across all volumes
        slice_frames = z:slices_per_vol:T; % Get indices of the same slice across volumes
        Yf_slice = Yf(:,:,slice_frames); % Extract the corresponding slice frames

        % Compute fixed reference from the first 100 frames per Z
        ref_indices = 1:min(reference_frames, size(Yf_slice, 3)); % Ensure no out-of-bounds indexing
        ref_slice = median(Yf_slice(:,:,ref_indices), 3); % Compute mean reference -> changed to median

        % Compute Pre-Correction Motion Metrics
        pre_corr(:, z) = motion_metrics(Yf_slice, 5);

        % Set NoRMCorre Parameters for Rigid Motion Correction
        options_r = NoRMCorreSetParms(...
            'd1', d1, 'd2', d2, 'bin_width', 150, ... 
            'max_shift', max_shift, ... % Dynamically computed based on min dim
            'iter', 1, ...
            'correct_bidir', false);

        % Register slice-wise
        [Mpr_slice, shifts] = normcorre_batch(Yf_slice, options_r, ref_slice);

        % Compute Post-Correction Motion Metrics
        post_corr(:, z) = motion_metrics(Mpr_slice, 5);

        % Store corrected frames back
        Mpr(:,:,slice_frames) = Mpr_slice;
        shifts_all(:,z,:) = cat(1, shifts(:).shifts);
    end

    % Save motion metrics
    save(motionMetricsPath, 'pre_corr', 'post_corr');

    % Save motion-corrected stack
    save(outputMatPath, 'Mpr', '-v7.3');
    fprintf('Saved motion-corrected MAT stack: %s\n', outputMatPath);

    % Save motion-corrected TIFF
    save_tiff_stack(outputTiffPath, Mpr);
    fprintf('Saved motion-corrected TIFF stack: %s\n', outputTiffPath);

    % Plot and save motion shift figures
    plot_shifts(shifts_all, figPath);

    % Save Pre & Post Correction Metrics Plot
    metrics_fig = fullfile(outputSubFolder, [folderName '_correlation_metrics.png']);
    plot_motion_metrics(pre_corr, post_corr, metrics_fig);
end

fprintf('Rigid Motion Correction Complete for All Folders!\n');

%% Functions

% Load TIFF Stack
function imgStack = load_tiff_stack(filename)
    info = imfinfo(filename);
    numFrames = numel(info);
    imgStack = zeros(info(1).Height, info(1).Width, numFrames, 'single');
    for k = 1:numFrames
        imgStack(:,:,k) = imread(filename, k);
    end
end

% Save TIFF Stack
function save_tiff_stack(filename, imgStack)
    if exist(filename, 'file')
        delete(filename);
    end

    t = Tiff(filename, 'w8'); % 'w8' ensures BigTIFF support

    tagstruct.ImageLength = size(imgStack, 1);
    tagstruct.ImageWidth = size(imgStack, 2);
    tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
    tagstruct.BitsPerSample = 16;
    tagstruct.SamplesPerPixel = 1;
    tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
    tagstruct.Software = 'MATLAB';
    tagstruct.Compression = Tiff.Compression.None;
    tagstruct.RowsPerStrip = min(size(imgStack, 1), 16);

    for k = 1:size(imgStack, 3)
        t.setTag(tagstruct);
        t.write(uint16(imgStack(:,:,k))); 
        if k < size(imgStack, 3)
            t.writeDirectory();
        end
    end
    t.close();
end

% Plot Motion Correction Shifts
function plot_shifts(shifts_all, savePath)
    num_volumes = size(shifts_all, 1);
    slices_per_vol = size(shifts_all, 2);
    T = num_volumes * slices_per_vol;

    shifts_x = reshape(shifts_all(:,:,1), [T, 1]);
    shifts_y = reshape(shifts_all(:,:,2), [T, 1]);

    figure;
    subplot(211); plot(shifts_x, 'r'); hold on;
    title('X-axis Motion Correction Shifts');
    ylabel('Pixels');
    
    subplot(212); plot(shifts_y, 'b'); hold on;
    title('Y-axis Motion Correction Shifts');
    xlabel('Frame');
    ylabel('Pixels');

    saveas(gcf, savePath);
    close(gcf);
end

% Plot Pre & Post Motion Correction Metrics
function plot_motion_metrics(pre_corr, post_corr, savePath)
    figure;
    plot(pre_corr(:), 'r'); hold on;
    plot(post_corr(:), 'g');
    legend('Pre-Correction', 'Post-Correction');
    title('Motion Correction Quality');
    xlabel('Frame');
    ylabel('Correlation with Mean Frame');
    saveas(gcf, savePath);
    close(gcf);
end