# WIDE-CAT: A low-cost, open-source toolbox for widefield calcium imaging
# and voxel-based analysis, with optional structural enhancement via
# deconvolution or computational sectioning.
# Copyright (C) 2025 Gokul Rajan
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

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
stabilization_delay = 0.040  # Delay after piezo movement (40 ms)
camera_trigger_duration = 0.030  # Camera trigger pulse duration (30 ms)

volumes_per_sound = 6  # Play sound after every 6 volumes/ 10 vols for sound3
# per 6 vol aka per 10.44 s inter-stim
# per 10 vol aka per 17.44 s inter-stim

# acquire for 159 vols / 6360 images

# 6 vol_per_sec setting - 25 stims
# 10 vol setting - 15 stims (might be usable for sound3 to achieve 6s presentation + 10s isi)

sound_file = "sound1_41592_2018_144_MOESM7_ESM.wav"  # Path to your sound file
#sound_file = "sound2_DC_agonistic_4_males_HTIhydrof.wav"
#sound_file = "sound3_DC_coutship_1male4fem_HTI.wav"

# Initialize Pygame mixer for sound playback
pygame.mixer.init()

def play_sound():
    """Play sound in a non-blocking way."""
    pygame.mixer.music.load(sound_file)
    pygame.mixer.music.play()

with nidaqmx.Task() as piezo_control_task, nidaqmx.Task() as piezo_feedback_task, \
        nidaqmx.Task() as feedback_monitor_task, nidaqmx.Task() as camera_task:
    # Configure piezo control output channel
    piezo_control_task.ao_channels.add_ao_voltage_chan(piezo_control_channel)

    # Configure piezo feedback input channel
    piezo_feedback_task.ai_channels.add_ai_voltage_chan(piezo_feedback_channel)

    # Configure feedback monitor output channel (for oscilloscope)
    feedback_monitor_task.ao_channels.add_ao_voltage_chan(feedback_monitor_channel)

    # Configure camera trigger digital output channel
    camera_task.do_channels.add_do_chan(camera_trigger_channel)

    print("Starting piezo control, feedback monitoring, camera triggering, and sound playback...")

    volume_count = 0

    while True:

        # Imaging Steps
        for step in range(num_steps):
            # Calculate target voltage for this step
            target_voltage = step_voltage * step

            # Drive piezo to the target voltage
            piezo_control_task.write(target_voltage, auto_start=True)

            # Wait for stabilization
            time.sleep(stabilization_delay)

            # Read feedback signal
            current_voltage = piezo_feedback_task.read()

            # Output feedback signal to AO1 for monitoring
            feedback_monitor_task.write(current_voltage, auto_start=True)

            # Trigger the camera
            camera_task.write(True, auto_start=True)  # HIGH signal
            time.sleep(camera_trigger_duration)  # Pulse duration
            camera_task.write(False, auto_start=True)  # LOW signal

            print(f"Triggered camera at step {step + 1}, feedback voltage: {current_voltage:.6f} V")

        # Flyback to initial position
        piezo_control_task.write(flyback_voltage, auto_start=True)
        print(f"Flyback to initial position with voltage: {flyback_voltage} V")
        time.sleep(stabilization_delay/2)

        # Reset piezo to starting position after flyback
        piezo_control_task.write(0.0, auto_start=True)
        time.sleep(stabilization_delay*8)  # Stabilize at 0 V

        # Increment volume count
        volume_count += 1

        # Play sound at intervals
        if volume_count % volumes_per_sound == 0:
            print(f"Playing sound after {volume_count} volumes...")
            sound_thread = threading.Thread(target=play_sound)
            sound_thread.start()  # Non-blocking sound playback

        print(f"Completed volume {volume_count}")
