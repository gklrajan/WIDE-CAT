addpath(genpath('D:\Gokul\matlab\widefield\deconv_tests\filters')); % TS workstation
%addpath(genpath('G:\GR\Lab-SW\widefield\utility')); % OpenLab workstation

matfile_path='D:\Gokul\2024-Widefield\data\test_various_deconvols\larval_1-50\reduce_preprocessed_dc5_test.mat';
psf_path='D:\Gokul\2024-Widefield\data\preprocessed\00_inverted_normalized_psf_16bit_binned2.tif';
num_iterations=3;
pad_size=150;
slices_per_vol=40;
reduce_to_vol=50;

%reduce_matfile(matfile_path, slices_per_vol,reduce_to_vol);

apply_filters_and_deconvolve(matfile_path, psf_path, num_iterations, pad_size,slices_per_vol);
