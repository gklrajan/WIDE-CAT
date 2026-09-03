%% Richardson-Lucy Deconvolution for 3D Widefield Imaging
% Recursive bulk processing of all *_motion_corrected.mat files

% WIDE-CAT: A low-cost, open-source toolbox for widefield calcium imaging
% and voxel-based analysis, with optional structural enhancement via
% deconvolution or computational sectioning.
% Copyright (C) 2025 Gokul Rajan
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program. If not, see <https://www.gnu.org/licenses/>.

clear;
clc;

%% Add functions to MATLAB path

if ismac
    addpath(genpath( ...
        '/Users/gokulrajan/Documents/MATLAB/ZebranalysisSystem/zebraFunctions'));
elseif ispc
    addpath(genpath('D:\Gokul\matlab\widefield\utility'));
end


%% ============================================================
%  CONFIGURATION
%  ============================================================

pad_size = 20;              % XY symmetric padding
num_iterations = 25;        % Richardson-Lucy iterations
slices_per_vol = 20;        % Z slices per acquired volume

% Number of volumes simultaneously held in memory.
% Increase if you have lots of RAM.
volumes_per_batch = 8;

% Skip files that have already been processed
overwrite_existing = false;


%% Paths

% Search EVERYTHING below this folder
inputRoot = 'D:\Gokul\2026b_data\d\results';

% All RL results go here
outputRoot = 'D:\Gokul\2026b_data\d\rl_deconvolved';

psf_path = ...
    'D:\Gokul\2024-Widefield\data\preprocessed\psf_prepared_for_RL.tif';


%% Create output directory

if ~exist(outputRoot, 'dir')
    mkdir(outputRoot);
end


%% ============================================================
%  LOAD PSF
%  ============================================================

fprintf('\nLoading PSF:\n%s\n', psf_path);

psf = load_tiff_stack(psf_path);
psf = single(psf);

psf_sum = sum(psf(:));

if psf_sum <= 0
    error('PSF has zero or negative total intensity.');
end

psf = psf ./ psf_sum;

fprintf('PSF dimensions: %d x %d x %d\n', ...
    size(psf,1), size(psf,2), size(psf,3));

fprintf('PSF sum: %.10f\n', sum(psf(:)));
fprintf('PSF max: %.6e\n\n', max(psf(:)));


%% ============================================================
%  FIND ALL MOTION-CORRECTED MAT FILES RECURSIVELY
%  ============================================================

fprintf('Searching recursively under:\n%s\n\n', inputRoot);

inputFiles = dir(fullfile( ...
    inputRoot, '**', '*_motion_corrected.mat'));

if isempty(inputFiles)
    error('No *_motion_corrected.mat files found below:\n%s', inputRoot);
end


%% Prevent accidental processing of anything under outputRoot

keepFile = true(size(inputFiles));

for k = 1:numel(inputFiles)

    currentPath = fullfile( ...
        inputFiles(k).folder, inputFiles(k).name);

    if startsWith(currentPath, outputRoot, 'IgnoreCase', true)
        keepFile(k) = false;
    end
end

inputFiles = inputFiles(keepFile);


fprintf('Found %d motion-corrected MAT files.\n\n', ...
    numel(inputFiles));


%% ============================================================
%  START PARALLEL POOL
%  ============================================================

if isempty(gcp('nocreate'))
    parpool;
end


%% ============================================================
%  PROCESS EVERY FILE
%  ============================================================

nFiles = numel(inputFiles);

successfulFiles = 0;
failedFiles = 0;
skippedFiles = 0;

for fileIdx = 1:nFiles

    input_path = fullfile( ...
        inputFiles(fileIdx).folder, ...
        inputFiles(fileIdx).name);


    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('DATASET %d / %d\n', fileIdx, nFiles);
    fprintf('============================================================\n');
    fprintf('Input:\n%s\n\n', input_path);


    try

        %% --------------------------------------------------------
        % Determine relative directory
        % ---------------------------------------------------------

        inputFolder = inputFiles(fileIdx).folder;

        if strcmpi(inputFolder, inputRoot)

            relativeFolder = '';

        else

            prefix = [inputRoot filesep];

            if startsWith(inputFolder, prefix, 'IgnoreCase', true)
                relativeFolder = inputFolder(length(prefix)+1:end);
            else
                relativeFolder = '';
            end
        end


        % Rename motion-corrected directory names in output tree
        relativeOutputFolder = strrep( ...
            relativeFolder, ...
            '_motion_corrected', ...
            '_rl_deconvolved');


        outputSubFolder = fullfile( ...
            outputRoot, relativeOutputFolder);


        if ~exist(outputSubFolder, 'dir')
            mkdir(outputSubFolder);
        end


        %% --------------------------------------------------------
        % Output filename
        % ---------------------------------------------------------

        [~, inputBaseName, ~] = fileparts(inputFiles(fileIdx).name);

        outputBaseName = strrep( ...
            inputBaseName, ...
            '_motion_corrected', ...
            '_rl_deconvolved');


        output_mat_path = fullfile( ...
            outputSubFolder, ...
            [outputBaseName '.mat']);


        fprintf('Output:\n%s\n\n', output_mat_path);


        %% --------------------------------------------------------
        % Existing output
        % ---------------------------------------------------------

        if exist(output_mat_path, 'file')

            if overwrite_existing
                fprintf('Existing output found. Overwriting...\n');
                delete(output_mat_path);
            else
                fprintf('Already processed. Skipping.\n');
                skippedFiles = skippedFiles + 1;
                continue;
            end
        end


        %% --------------------------------------------------------
        % Open input MAT file
        % ---------------------------------------------------------

        m = matfile(input_path, 'Writable', false);


        vars = who(m);

        if ~ismember('Mpr', vars)
            error('MAT file does not contain variable "Mpr".');
        end


        [rows, cols, total_slices] = size(m, 'Mpr');


        fprintf('Dataset dimensions:\n');
        fprintf('    X/Y       : %d x %d\n', rows, cols);
        fprintf('    Z/T stack : %d frames\n', total_slices);


        %% --------------------------------------------------------
        % Validate volume structure
        % ---------------------------------------------------------

        if mod(total_slices, slices_per_vol) ~= 0

            error(['Stack contains %d slices, which is not divisible ' ...
                   'by slices_per_vol = %d.'], ...
                   total_slices, slices_per_vol);
        end


        num_volumes = total_slices / slices_per_vol;


        fprintf('    Slices/vol: %d\n', slices_per_vol);
        fprintf('    Volumes   : %d\n\n', num_volumes);


        %% --------------------------------------------------------
        % Create memory-mapped output
        %
        % Writing only the final element preallocates the MAT variable
        % without constructing the complete zeros array in RAM.
        % ---------------------------------------------------------

        m_out = matfile(output_mat_path, 'Writable', true);

        m_out.Mpr(rows, cols, total_slices) = single(0);


        %% --------------------------------------------------------
        % Process volumes in batches
        % ---------------------------------------------------------

        num_batches = ceil(num_volumes / volumes_per_batch);


        fprintf('Starting Richardson-Lucy deconvolution...\n');
        fprintf('Iterations       : %d\n', num_iterations);
        fprintf('Volumes per batch: %d\n', volumes_per_batch);
        fprintf('Number of batches: %d\n\n', num_batches);


        for batchIdx = 1:num_batches

            firstVol = ...
                (batchIdx - 1) * volumes_per_batch + 1;

            lastVol = min( ...
                batchIdx * volumes_per_batch, ...
                num_volumes);

            batchVols = firstVol:lastVol;

            nBatchVols = numel(batchVols);


            fprintf('Batch %d/%d: volumes %d-%d\n', ...
                batchIdx, ...
                num_batches, ...
                firstVol, ...
                lastVol);


            deconv_results = cell(1, nBatchVols);


            %% ----------------------------------------------------
            % Parallel deconvolution
            % -----------------------------------------------------

            parfor j = 1:nBatchVols

                vol = batchVols(j);

                vol_start = ...
                    (vol - 1) * slices_per_vol + 1;

                vol_end = ...
                    vol * slices_per_vol;


                % Read ONLY this volume from disk
                vol_data = single( ...
                    m.Mpr(:,:,vol_start:vol_end));


                % Symmetric XY padding.
                % No Z padding because Z extent corresponds to
                % actual acquired optical planes.
                vol_data_padded = padarray( ...
                    vol_data, ...
                    [pad_size pad_size 0], ...
                    'symmetric', ...
                    'both');


                % Richardson-Lucy deconvolution
                vol_deconvolved_padded = deconvlucy( ...
                    vol_data_padded, ...
                    psf, ...
                    num_iterations);


                % Crop XY padding
                vol_deconvolved = ...
                    vol_deconvolved_padded( ...
                    pad_size+1:end-pad_size, ...
                    pad_size+1:end-pad_size, ...
                    :);


                deconv_results{j} = ...
                    single(vol_deconvolved);

            end


            %% ----------------------------------------------------
            % Sequential disk write
            % -----------------------------------------------------

            for j = 1:nBatchVols

                vol = batchVols(j);

                vol_start = ...
                    (vol - 1) * slices_per_vol + 1;

                vol_end = ...
                    vol * slices_per_vol;


                m_out.Mpr(:,:,vol_start:vol_end) = ...
                    deconv_results{j};

            end


            % Explicitly release batch RAM
            clear deconv_results;


            fprintf('    Written to disk.\n');

        end


        fprintf('\nSUCCESS:\n%s\n', output_mat_path);

        successfulFiles = successfulFiles + 1;


    catch ME

        failedFiles = failedFiles + 1;

        fprintf(2, '\nFAILED:\n%s\n', input_path);
        fprintf(2, 'Reason: %s\n\n', ME.message);

        % Continue to next dataset rather than terminating the batch

    end

end


%% ============================================================
%  SUMMARY
%  ============================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf('RL DECONVOLUTION FINISHED\n');
fprintf('============================================================\n');

fprintf('Files found      : %d\n', nFiles);
fprintf('Successfully done: %d\n', successfulFiles);
fprintf('Skipped          : %d\n', skippedFiles);
fprintf('Failed           : %d\n', failedFiles);

fprintf('============================================================\n\n');


%% ============================================================
%  HELPER FUNCTIONS
%  ============================================================

function stack = load_tiff_stack(filepath)

    info = imfinfo(filepath);

    num_images = numel(info);

    stack = zeros( ...
        info(1).Height, ...
        info(1).Width, ...
        num_images, ...
        'single');

    for i = 1:num_images
        stack(:,:,i) = single(imread(filepath, i));
    end

end