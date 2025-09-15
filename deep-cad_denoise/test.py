from deepcad.test_collection import testing_class
import os

# User-defined paths
datasets_path = "D:/Gokul/2024-Widefield/data/single_zplane_stack/"  # Folder containing the single stack
denoise_model = "D:/Gokul/2024-Widefield/data/motion_corrected_rigid/train_adult/separated_zplanes/this_202503060109/E_20_Iter_7680.pth"

# First setup some parameters for testing
test_datasize = 100000  # Use all frames if the number exceeds the total number of frames in the dataset
GPU = '0'  # The index of GPU to use for computation
patch_xy = 150  # The width and height of 3D patches
patch_t = 1  # Single time slice for testing (since it's a single Z-plane)
overlap_factor = 0.6  # Required for seamless stitching
num_workers = 0  # Set to 0 on Windows to avoid multiprocessing issues

# Define Deep-CaD-RT testing parameters
test_dict = {
    'patch_x': patch_xy,
    'patch_y': patch_xy,
    'patch_t': patch_t,
    'overlap_factor': overlap_factor,
    'scale_factor': 1,  # Intensity scaling factor
    'test_datasize': test_datasize,
    'datasets_path': datasets_path,  # Folder where the single Z-plane stack is stored
    'pth_dir': os.path.dirname(denoise_model),  # Ensure correct model directory
    'denoise_model': denoise_model,
    'output_dir': "./results",  # Save outputs in the results directory
    'fmap': 16,  # Number of feature maps
    'GPU': GPU,
    'num_workers': num_workers,
    'visualize_images_per_epoch': False  # Disable visualization
}

# Run inference on the single stack
tc = testing_class(test_dict)
tc.run()