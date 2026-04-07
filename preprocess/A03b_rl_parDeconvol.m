%% Richardson-Lucy Deconvolution for 3D Widefield Imaging (Batch Processing)

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

%%
clear; clc;

% Add useful functions to MATLAB path
if ismac
    addpath(genpath('/Users/gokulrajan/Documents/MATLAB/ZebranalysisSystem/zebraFunctions')); 
elseif ispc
    addpath(genpath('D:\Gokul\matlab\widefield\utility'));
end

%   CONFIGURABLE PARAMETERS  
use_mat = true; % Set to `true` to use .mat files as input, `false` for .tif
pad_size = 20; % Padding size in pixels (applies to all sides)
num_iterations = 25; % RL iterations
slices_per_vol = 40; % Fixed volume size

%   Paths  
inputRoot = 'F:\processed data\maintenance\test';
outputRoot = 'F:\processed data\maintenance\test\rl_deconvolved';

psf_path = 'D:\Gokul\2024-Widefield\data\preprocessed\psf_prepared_for_RL.tif';

%   Ensure output directory exists  
if ~exist(outputRoot, 'dir')
    mkdir(outputRoot);
end

%   Load PSF  
fprintf('Loading PSF...\n');
psf = load_tiff_stack(psf_path);
psf = psf / sum(psf(:));
fprintf('PSF sum=%.10f  max=%.6e\n', sum(psf(:)), max(psf(:)));

%   Get All Motion-Corrected Folders  
inputFolders = dir(fullfile(inputRoot, '*_motion_corrected'));
if isempty(inputFolders)
    error('No motion-corrected folders found in %s', inputRoot);
end

for i = 1:length(inputFolders)
    folderName = inputFolders(i).name;
    inputFolder = fullfile(inputRoot, folderName);

    %   Locate motion-corrected files  
    if use_mat
        inputFile = dir(fullfile(inputFolder, '*_motion_corrected.mat'));
    else
        inputFile = dir(fullfile(inputFolder, '*_motion_corrected.tif'));
    end
    
    if isempty(inputFile)
        fprintf('Skipping %s (no input file found)\n', folderName);
        continue;
    end
    input_path = fullfile(inputFolder, inputFile.name);

    %   Define output subfolder  
    outputSubFolder = fullfile(outputRoot, strrep(folderName, '_motion_corrected', '_rl_deconvolved'));
    if ~exist(outputSubFolder, 'dir')
        mkdir(outputSubFolder);
    end

    %   Define output files  
    output_mat_path = fullfile(outputSubFolder, strrep(inputFile.name, '_motion_corrected', '_rl_deconvolved.mat'));
    output_tiff_path = fullfile(outputSubFolder, strrep(inputFile.name, '_motion_corrected', '_rl_deconvolved.tif'));

    fprintf('Processing file: %s\n', input_path);

    %   Load Data  
    if use_mat
        % Load MAT file using memory-efficient matfile()
        m = matfile(input_path, 'Writable', false);
        [rows, cols, total_slices] = size(m, 'Mpr');
    else
        % Load TIFF stack
        stack = load_tiff_stack(input_path);
        stack = single(stack); % Convert to single precision
        [rows, cols, total_slices] = size(stack);
    end

    num_volumes = total_slices / slices_per_vol;
    assert(mod(total_slices, slices_per_vol) == 0, 'Stack size mismatch: Not divisible by 40 slices per volume');

    %   Initialize Output MAT File  
    m_out = matfile(output_mat_path, 'Writable', true);
    m_out.Mpr = zeros(rows, cols, total_slices, 'single');

    fprintf('Starting RL Deconvolution for %s...\n', folderName);

    %   Apply RL Deconvolution Volume-by-Volume (Parallelized)  
    deconv_results = cell(1, num_volumes); % Temporary storage (cannot write to MAT in parfor)
    
    parfor vol = 1:num_volumes
        fprintf('Processing volume %d/%d...\n', vol, num_volumes);
    
        %   Load batch from input  
        vol_start = (vol - 1) * slices_per_vol + 1;
        vol_end = vol * slices_per_vol;
        
        if use_mat
            vol_data = m.Mpr(:,:, vol_start:vol_end);
        else
            %vol_data = stack(:,:, vol_start:vol_end); % Need to fix this for
            %tif processing. but why ue tif anyway?
        end
    
        %   Pad data  
        vol_data_padded = padarray(vol_data, [pad_size, pad_size, 0], 'symmetric', 'both');
    
        %   Apply RL Deconvolution  
        vol_deconvolved_padded = deconvlucy(vol_data_padded, psf, num_iterations);
    
        %   Crop back to original size  
        vol_deconvolved = vol_deconvolved_padded(pad_size+1:end-pad_size, pad_size+1:end-pad_size, :);
    
        %   Store in temporary cell (cannot write to .mat in parallel)  
        deconv_results{vol} = vol_deconvolved;
    end
    
        %   Sequentially Write to Output MAT File  
        for vol = 1:num_volumes
            vol_start = (vol - 1) * slices_per_vol + 1;
            vol_end = vol * slices_per_vol;
            m_out.Mpr(:,:, vol_start:vol_end) = deconv_results{vol};
        end
    
        fprintf('RL Deconvolution complete! Results saved to: %s\n', output_mat_path);

        %   Save as TIFF  
%        save_tiff_stack(output_tiff_path, m_out.stack);
%        fprintf('Saved RL Deconvolved TIFF: %s\n', output_tiff_path);
    end
    
    fprintf('RL Deconvolution Finished for all datasets.\n');

%%   Helper Functions  

%   Load TIFF Stack  
function stack = load_tiff_stack(filepath)
    info = imfinfo(filepath);
    num_images = numel(info);
    stack = zeros(info(1).Height, info(1).Width, num_images, 'single');
    for i = 1:num_images
        stack(:,:,i) = single(imread(filepath, i));  % no rescaling
    end
end

%   Save TIFF Stack  
function save_tiff_stack(filename, matStack)
    % Convert the matfile stack into a readable format for writing
    m = matfile(matStack);
    numSlices = size(m, 'stack', 3);

    % Open TIFF file in 'w8' mode (BigTIFF support)
    t = Tiff(filename, 'w8');

    % Set TIFF Metadata
    tagstruct.ImageLength = size(m.Mpr, 1);
    tagstruct.ImageWidth = size(m.Mpr, 2);
    tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
    tagstruct.BitsPerSample = 16;
    tagstruct.SamplesPerPixel = 1;
    tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
    tagstruct.Software = 'MATLAB';
    tagstruct.Compression = Tiff.Compression.None;

    %   Write Frames to TIFF Stack  
    for k = 1:numSlices
        t.setTag(tagstruct);
        t.write(uint16(m.Mpr(:,:,k) * 65535)); % Scale to 16-bit
        if k < numSlices
            t.writeDirectory(); % Create a new directory for the next frame
        end
    end

    % Close File
    t.close();
end
