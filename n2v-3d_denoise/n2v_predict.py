import os
import numpy as np
import tensorflow as tf
import tifffile as tiff

# Disable oneDNN optimizations for numerical stability
os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"

# Correct Model Path (Ensure it points to the unzipped folder containing `saved_model.pb`)
model_path = r"D:\Gokul\2024-Widefield\data\n2v_model\n2v-7722266211490665587.bioimage.io\tf_saved_model_bundle"

# Input & Output Paths
input_stack_path = r"D:\Gokul\2024-Widefield\data\motion_corrected_rigid\motion_corrected_preprocessed_fish5_good-definiteLearner_.tif"
output_stack_folder = r"D:\Gokul\2024-Widefield\data\n2v_denoised"

# Ensure output folder exists
os.makedirs(output_stack_folder, exist_ok=True)

# Define Output File Path
output_stack_path = os.path.join(output_stack_folder, "n2v-denoised_motion_corrected_preprocessed_fish5_good-definiteLearner_.tif")

# Load N2V Model
print("Loading N2V model...")
model = tf.saved_model.load(model_path)
predict_fn = model.signatures["serving_default"]

# Load Input Image Stack
print(f"Loading input stack from: {input_stack_path}")
stack = tiff.imread(input_stack_path).astype(np.float32)

# Ensure Stack is 4D: [batch, z, y, x, channel]
if stack.ndim == 3:
    stack = np.expand_dims(stack, axis=-1)  # Add channel dimension if missing
stack = np.expand_dims(stack, axis=0)  # Add batch dimension

# Ensure batch_size matches model requirement
batch_size = 4  # Adjust if needed (must match model requirements!)
z_slices = stack.shape[1]
num_batches = z_slices // batch_size  # Only process full batches

# Process Stack in Batches to Prevent OOM & Mismatched Shapes
denoised_stack = np.zeros_like(stack[:, :num_batches * batch_size, :, :, :])  # Trim to full batch

print(f"Running N2V prediction in batches of {batch_size} slices...")
for i in range(0, num_batches * batch_size, batch_size):
    batch = stack[:, i:i + batch_size, :, :, :]
    
    print(f"Processing slices {i+1} to {i+batch_size}/{z_slices}")
    denoised_batch = predict_fn(tf.convert_to_tensor(batch))["output_0"].numpy()
    
    denoised_stack[:, i:i + batch_size, :, :, :] = denoised_batch

# Save Output Stack
print(f"Saving denoised stack to: {output_stack_path}")
tiff.imwrite(output_stack_path, np.squeeze(denoised_stack).astype(np.float32))

print(" N2V Denoising Complete!")