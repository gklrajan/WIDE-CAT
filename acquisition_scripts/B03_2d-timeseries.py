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

# Configuration
device_name = "Dev1"
camera_trigger_channel = f"{device_name}/PFI0"  # Digital output to trigger the camera
stimulus_interval_frames = 90  # Trigger stimulus every 90 frames (30 seconds)
stimulus_duration_frames = 30  # Stimulus duration (10 seconds or 30 frames)
frame_interval = 1 / 3  # 3 frames per second
camera_trigger_duration = 0.030  # Camera trigger pulse duration (30 ms)
sound_file = "sound3_DC_coutship_1male4fem_HTI.wav"  # Sound file
image_file = "checker100.png"  # Stim img
audio_enabled = False  # True to use audio stimulus
video_enabled = False  # True to use visual stimulus

# Initialize Pygame for sound and visual presentation
pygame.init()
pygame.mixer.init()

def play_sound():
    """Play sound in a non-blocking way."""
    pygame.mixer.music.load(sound_file)
    pygame.mixer.music.play()

def display_image():
    """Display visual stimulus on the secondary screen."""
    display_info = pygame.display.Info()
    screen_width, screen_height = display_info.current_w, display_info.current_h
    stimulus_screen = pygame.display.set_mode((screen_width, screen_height), pygame.NOFRAME)
    pygame.display.set_caption("Visual Stimulus")

    # Load and scale the stimulus image
    stimulus_image = pygame.image.load(image_file)
    stimulus_image = pygame.transform.scale(stimulus_image, (screen_width, screen_height))

    # Display the image for the duration
    start_time = time.time()
    while time.time() - start_time < stimulus_duration_frames * frame_interval:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                return
        stimulus_screen.blit(stimulus_image, (0, 0))
        pygame.display.update()

    # Clear the screen
    stimulus_screen.fill((0, 0, 0))
    pygame.display.update()
    pygame.display.quit()

with nidaqmx.Task() as camera_task:
    # Configure camera trigger digital output channel
    camera_task.do_channels.add_do_chan(camera_trigger_channel)

    print("Starting camera triggering and stimulus presentation...")

    frame_count = 0

    while True:
        # Trigger the camera
        camera_task.write(True, auto_start=True)  # HIGH signal
        time.sleep(camera_trigger_duration)  # Exposure time
        camera_task.write(False, auto_start=True)  # LOW signal

        frame_count += 1
        print(f"Triggered camera at frame {frame_count}")

        # Check for stimulus presentation
        if frame_count % stimulus_interval_frames == 0:
            print("Stimulus presentation starting...")
            if audio_enabled:
                sound_thread = threading.Thread(target=play_sound)
                sound_thread.start()
            elif video_enabled:
                stimulus_thread = threading.Thread(target=display_image)
                stimulus_thread.start()

        # Wait for the next frame
        time.sleep(frame_interval - camera_trigger_duration)