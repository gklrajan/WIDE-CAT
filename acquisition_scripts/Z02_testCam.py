import nidaqmx
import time

# Configuration
device_name = "Dev1"
camera_trigger_channel = f"{device_name}/PFI0"  # Digital output to trigger the camera
camera_trigger_duration = 0.010  # Camera trigger pulse duration (10 ms)
num_triggers = 5  # Number of camera triggers
trigger_interval = 10.0  # Time between triggers in seconds

print("Starting camera trigger test...")

with nidaqmx.Task() as camera_task:
    # Configure camera trigger digital output channel
    camera_task.do_channels.add_do_chan(camera_trigger_channel)

    for i in range(num_triggers):
        # Trigger the camera
        camera_task.write(True, auto_start=True)  # HIGH signal
        time.sleep(camera_trigger_duration)  # Pulse duration
        camera_task.write(False, auto_start=True)  # LOW signal

        print(f"Triggered camera: {i + 1}/{num_triggers}")
        time.sleep(trigger_interval)  # Wait before next trigger

print("Camera trigger test completed.")
