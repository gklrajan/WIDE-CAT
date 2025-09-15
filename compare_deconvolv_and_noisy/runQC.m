%%%%%%%%%%%%%%%%%%%%%%%%%%%%
roi_masks = roi_masks; % Set this if you want consistent ROIs across all deconv methods
%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Define raw stack (noisy data)
rawStack = 'G:\GR\WF-data\deconv_tests_larvae\noisy\reduce_preprocessed_dc5_test.mat';

% Define different deconvolution methods with updated paths
deconvStacks = {
    'G:\GR\WF-data\deconv_tests_larvae\bandpass\reduce_preprocessed_dc5_test_bandpass_deconv.mat';
    'G:\GR\WF-data\deconv_tests_larvae\bilateral\reduce_preprocessed_dc5_test_bilateral_deconv.mat';
    'G:\GR\WF-data\deconv_tests_larvae\gaussian\reduce_preprocessed_dc5_test_gaussian_deconv.mat';
    'G:\GR\WF-data\deconv_tests_larvae\median\reduce_preprocessed_dc5_test_median_deconv.mat';
    'G:\GR\WF-data\deconv_tests_larvae\raw_deconv\reduce_preprocessed_dc5_test_raw_deconv.mat'
};

% Analysis parameters
volume_range = 1:50;
slices_per_vol = 40;

% Loop through each deconvolution method
for i = 1:length(deconvStacks)
    deconvStack = deconvStacks{i};
    
    fprintf('Processing: %s\n', deconvStack);
    
    % Run quantitative analysis
    analyze_deconvolution_dff(rawStack, deconvStack, volume_range, slices_per_vol, roi_masks);
    
    % Save example stacks
    get_tiff_examples(rawStack, deconvStack, 20, slices_per_vol);
    
    fprintf('Finished processing: %s\n', deconvStack);
end

fprintf('All deconvolution methods processed.\n');