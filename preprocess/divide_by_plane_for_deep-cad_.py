import os
import numpy as np
import tifffile as tiff

# this was for deep-cad preprocess. irrelevant now.

# User-defined paths
input_root = "D:\\Gokul\\2024-Widefield\\data\motion_corrected_rigid\\train_larva\\"
output_root = "D:\\Gokul\\2024-Widefield\\data\motion_corrected_rigid\\train_larva\\separated_zplanes\\"
num_z = 40  # Number of Z-planes per volume

# Ensure output root directory exists
os.makedirs(output_root, exist_ok=True)

# Get all TIFF files in the input directory
tiff_files = [f for f in os.listdir(input_root) if f.endswith(".tif")]

# Process each TIFF stack in the input directory
for tiff_file in tiff_files:
    input_tiff = os.path.join(input_root, tiff_file)
    stack = tiff.imread(input_tiff).astype(np.float32)

    # Get dimensions
    num_frames = stack.shape[0]  # Total frames (timepoints * Z-planes)

    # Ensure the number of frames is divisible by num_z
    if num_frames % num_z != 0:
        print(f"Warning: {tiff_file} has {num_frames} frames, which is not a multiple of {num_z}. Skipping.")
        continue

    num_timepoints = num_frames // num_z  # Compute number of timepoints

    # Create subfolder for separated planes
    stack_name = os.path.splitext(tiff_file)[0]
    output_folder = os.path.join(output_root, f"separated_{stack_name}")
    os.makedirs(output_folder, exist_ok=True)

    # Reshape into time-series per Z-plane
    for z in range(num_z):
        z_time_series = stack[z::num_z]  # Select frames corresponding to Z-plane z

        # Save as separate TIFF stack
        output_path = os.path.join(output_folder, f"Z{z + 1}_{stack_name}.tif")
        tiff.imwrite(output_path, z_time_series.astype(np.uint16))
        print(f"Saved {output_path} with {z_time_series.shape[0]} timepoints.")

print("All stacks processed successfully!")