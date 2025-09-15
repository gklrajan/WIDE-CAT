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
from pygame.locals import QUIT

# Configuration- change based on your experiment. commented out well enough to be self-explanatory
device_name = "Dev1"
piezo_control_channel = f"{device_name}/ao0"  # Analog output to drive the piezo
piezo_feedback_channel = f"{device_name}/ai0"  # Analog input for piezo feedback
feedback_monitor_channel = f"{device_name}/ao1"  # Analog output to duplicate feedback signal
camera_trigger_channel = f"{device_name}/PFI0"  # Digital output to trigger the camera

step_voltage = 0.22  # Voltage increment for 10 μm movement
flyback_voltage = 4.4  # Voltage to reset piezo to starting position
num_steps = 20  # Number of steps in one volume
stabilization_delay = 0.048  # Delay after piezo movement. 250915: 50ms to 48ms
camera_trigger_duration = 0.030  # Camera trigger pulse duration

image_stimulus_volumes = 6  # Number of volumes the stimulus is displayed
stimulus_interval = 17  # Inter-stimulus interval in volumes

# notes
# per 6 vol
# 250402 - 353 vols - 14120 - 11min - 20 stims

# acquire 175*2 vols or 14000 images
# 6 and 17 setting - 20 stim presentations

#250915 - changed to 1Hz vol acquisitions with 20-slice vols
# 6 and 17 vol setting -> presentation and isi dur reduced to half

sound_file = "sound3_DC_coutship_1male4fem_HTI.wav"  # Path to your sound file
image_file = "checker_B.png"  # Path to your visual stimulus image

# Initialize Pygame for sound and visual presentation
pygame.init()
pygame.mixer.init()

def display_stimulus():
    """Display stimulus on the secondary screen."""
    pygame.init()
    pygame.mixer.init()

    # Get available displays
    display_info = pygame.display.Info()
    screen_width, screen_height = display_info.current_w, display_info.current_h
    display_list = pygame.display.get_num_displays()
    print(f"Available displays: {display_list}")

    # Create a window on the secondary screen (projector)
    stimulus_screen = pygame.display.set_mode((screen_width, screen_height), pygame.NOFRAME,display=1)#display=1; cant detect secondary
    pygame.display.set_caption("Stimulus Presentation")
    screen = pygame.Surface((screen_width, screen_height))

    # Load and scale the stimulus image
    stimulus_image = pygame.image.load(image_file)
    stimulus_image = pygame.transform.scale(stimulus_image, (screen_width, screen_height))

    # Load image and get its size
    stimulus_image = pygame.image.load(image_file)
    image_width, image_height = stimulus_image.get_size()

    # Do NOT stretch, only center the correctly scaled image
    stimulus_screen.fill((0, 0, 0))  # Black background
    stimulus_screen.blit(stimulus_image, ((screen_width - image_width) // 2, (screen_height - image_height) // 2))
    pygame.display.update()


    # Keep the stimulus displayed until the stimulus duration ends
    running = True
    start_time = time.time()
    while running:
        for event in pygame.event.get():
            if event.type == QUIT:
                running = False
        if time.time() - start_time >= (image_stimulus_volumes * stabilization_delay * num_steps):
            running = False

    # Clear the screen
    stimulus_screen.fill((0, 0, 0))
    pygame.display.update()
    pygame.display.quit()

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

    print("Starting piezo control, feedback monitoring, camera triggering, and sound/visual stimulus playback...")

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

            print(f"Triggered camera at step {step + 1}, feedback voltage: {current_voltage:.3f} V")

        # Flyback to initial position
        piezo_control_task.write(flyback_voltage, auto_start=True)
        print(f"Flyback to initial position with voltage: {flyback_voltage} V")
        time.sleep(stabilization_delay / 2)

        # Reset piezo to starting position after flyback
        piezo_control_task.write(0.0, auto_start=True)
        time.sleep(stabilization_delay / 2)  # Stabilize at 0 V

        # Increment volume count
        volume_count += 1

        # Present visual stimulus at intervals
        if (volume_count % stimulus_interval) == 0:
            print(f"Presenting stimulus for {image_stimulus_volumes} volumes...")
            stimulus_thread = threading.Thread(target=display_stimulus)
            stimulus_thread.start()

        print(f"Completed volume {volume_count}")
