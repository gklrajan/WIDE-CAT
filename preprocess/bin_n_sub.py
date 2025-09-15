import os
import numpy as np
import tifffile as tiff
from skimage.transform import downscale_local_mean

# User-defined input directories
inputDirs = [
    "D:/Gokul/2024-Widefield/data/01_adults_lnm_visual/fish5_good-definiteLearner_/",
    "D:/Gokul/2024-Widefield/data/04_adults_lnm_ctrl_3day-nonUS-training_/lnm_ctrl_fish4_/",
    "E:/widefield/00_2025-data/03_larval_pureTones/zf1_test/",
    "E:/widefield/00_2025-data/03_larval_pureTones/dc5_test/"
]
outputRoot = "D:/Gokul/2024-Widefield/data/preprocessed/"  # Root output directory
darkImagePath = "D:/Gokul/2024-Widefield/data/preprocessed/AVG_dark_img_binned2_allCovered_.tif"  # Path to dark image

# Load the average dark image
dark_image = tiff.imread(darkImagePath).astype(np.float32)

# Process each folder
for inputDir in inputDirs:
    folder_name = os.path.basename(os.path.normpath(inputDir))  # Extract last folder name
    output_folder = os.path.join(outputRoot, f"preprocessed_{folder_name}")  # Create subfolder
    os.makedirs(output_folder, exist_ok=True)  # Ensure output folder exists

    print(f"Processing folder: {inputDir}")

    # Get all TIFF files in the folder
    tiff_files = sorted([f for f in os.listdir(inputDir) if f.endswith(".tif")])

    processed_stack = []
    for file in tiff_files:
        file_path = os.path.join(inputDir, file)

        # Load TIFF image
        image = tiff.imread(file_path).astype(np.float32)

        # Bin (2×2) by averaging neighboring pixels
        binned_image = downscale_local_mean(image, (2, 2))

        # Subtract dark image
        corrected_image = binned_image - dark_image

        # Clip negative values to zero
        corrected_image[corrected_image < 0] = 0

        # Convert back to 16-bit for saving
        corrected_image = corrected_image.astype(np.uint16)

        processed_stack.append(corrected_image)

    # Save as a TIFF stack
    output_file = os.path.join(output_folder, f"preprocessed_{folder_name}.tif")
    tiff.imwrite(output_file, np.array(processed_stack), photometric="minisblack")

    print(f"Saved preprocessed stack: {output_file}")

print("All folders processed successfully!")