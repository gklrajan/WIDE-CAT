%% Preprocessing Script for Widefield Imaging
clear; clc;

% Input Directories (Modify as needed)
inputDirs = { 'E:\widefield\00_2025-data\03_larval_pureTones\dc1_test'
};

% Output Root Directory
outputRoot = 'D:/Gokul/2024-Widefield/data/preprocessed2/';

% Dark Image Path
darkImagePath = 'D:/Gokul/2024-Widefield/data/preprocessed/AVG_dark_img_binned2_allCovered_.tif';

%% Load Dark Image
fprintf('Loading dark image: %s\n', darkImagePath);
dark_image = im2single(imread(darkImagePath)); % Convert to single precision

%% Process Each Folder
for i = 1:length(inputDirs)
    inputDir = inputDirs{i};
    folderName = split(inputDir, filesep);
    folderName = folderName{end}; % Extract folder name
    outputFolder = fullfile(outputRoot, ['preprocessed_' folderName]);
    
    % Ensure output folder exists
    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end
    
    fprintf('Processing folder: %s\n', inputDir);

    % Get all TIFF files in the folder
    tiffFiles = dir(fullfile(inputDir, '*.tif'));
    
    % Initialize matrix for efficient processing
    numFrames = length(tiffFiles);
    exampleImage = im2single(imread(fullfile(inputDir, tiffFiles(1).name)));
    [rows, cols] = size(exampleImage);
    processed_stack = zeros(rows/2, cols/2, numFrames, 'single'); % Binned size

    for j = 1:numFrames
        filePath = fullfile(inputDir, tiffFiles(j).name);
        
        % Load TIFF Image
        image = im2single(imread(filePath));

        % Bin (2×2) using local averaging
        binned_image = imresize(image, 0.5, 'bilinear'); % Binning via bilinear interpolation

        % Subtract Dark Image
        corrected_image = binned_image - dark_image;

        % Clip negative values to zero
        corrected_image(corrected_image < 0) = 0;

        % Store in matrix
        processed_stack(:,:,j) = corrected_image;
    end

    % Save as TIFF stack
    outputTiffFile = fullfile(outputFolder, ['preprocessed_' folderName '.tif']);
    save_tiff_stack(outputTiffFile, processed_stack);
    fprintf('Saved preprocessed TIFF stack: %s\n', outputTiffFile);

    % Save as MAT file
    outputMatFile = fullfile(outputFolder, ['preprocessed_' folderName '.mat']);
    save_mat_stack(outputMatFile, processed_stack);
    fprintf('Saved preprocessed MAT stack: %s\n', outputMatFile);
end

fprintf('All folders processed successfully!\n');

%% Function to Save TIFF Stack
function save_tiff_stack(filename, imgStack)
    % Delete existing file if present
    if exist(filename, 'file')
        delete(filename);
    end

    % Open TIFF file in 'w8' mode (BigTIFF support)
    t = Tiff(filename, 'w8');

    % Set TIFF Metadata
    tagstruct.ImageLength = size(imgStack, 1);
    tagstruct.ImageWidth = size(imgStack, 2);
    tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
    tagstruct.BitsPerSample = 16;
    tagstruct.SamplesPerPixel = 1;
    tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
    tagstruct.Software = 'MATLAB';
    tagstruct.Compression = Tiff.Compression.None;

    % Write Frames to TIFF Stack
    for k = 1:size(imgStack, 3)
        t.setTag(tagstruct);
        t.write(uint16(imgStack(:,:,k) * 65535)); % Scale to 16-bit
        if k < size(imgStack, 3)
            t.writeDirectory(); % Create a new directory for the next frame
        end
    end

    % Close File
    t.close();
end

%% Function to Save as MAT File
function save_mat_stack(filename, imgStack)
    % Use matfile() for memory-efficient saving
    mat_obj = matfile(filename, 'Writable', true);
    mat_obj.stack = imgStack;  % Direct assignment for efficient saving
end