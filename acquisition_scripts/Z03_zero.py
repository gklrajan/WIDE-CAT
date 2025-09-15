import nidaqmx
import time
import threading
import pygame

# Configuration- change based on your experiment. commented out well enough to be self-explanatory
device_name = "Dev1"
piezo_control_channel = f"{device_name}/ao0"  # Analog output to drive the piezo
piezo_feedback_channel = f"{device_name}/ai0"  # Analog input for piezo feedback
feedback_monitor_channel = f"{device_name}/ao1"  # Analog output to duplicate feedback signal
camera_trigger_channel = f"{device_name}/PFI0"  # Digital output to trigger the camera

step_voltage = 0.11 #0.055 #0.11 #0.0111 #0.11  # Voltage increment for 5 μm movement
flyback_voltage = 4.44 #4.44 #4.4  # Voltage to reset piezo to starting position
num_steps = 40  # Number of steps in one volume


with nidaqmx.Task() as piezo_control_task, nidaqmx.Task() as piezo_feedback_task, \
        nidaqmx.Task() as feedback_monitor_task, nidaqmx.Task() as camera_task:
    # Configure piezo control output channel
    piezo_control_task.ao_channels.add_ao_voltage_chan(piezo_control_channel)

    # Reset piezo to starting position
    piezo_control_task.write(0.0, auto_start=True)