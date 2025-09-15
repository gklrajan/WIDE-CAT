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
import numpy as np
import random

# Configuration
device_name = "Dev1"
piezo_control_channel = f"{device_name}/ao0"
camera_trigger_channel = f"{device_name}/PFI0"

step_voltage = 0.11  # Voltage increment for 5 μm movement
flyback_voltage = 4.4  # Voltage to reset piezo to starting position
num_steps = 40  # Number of steps in one volume
stabilization_delay = 0.040  # Delay after piezo movement (40 ms)
camera_trigger_duration = 0.030  # Camera trigger pulse duration (30 ms)
# cam imgs 18000

# **Pure Tone Sound Configuration**
tone_frequencies = [150, 200, 250, 300, 450, 550, 600, 650, 700, 750, 800, 850, 900, 950, 1000]  # Hz
repeat_each_tone = 5  # Each tone repeats 5 times
isi_volumes = 6  # Stimulus interval every 6 volumes (~10s ISI)
tone_duration = 1.9  # Each tone runs for exactly 1 volume (1.9s)

# **Create a Constant Shuffled Array (Only Once)**
random.seed(42)  # Fixing seed for reproducibility. 42 because well 42
shuffled_tones = tone_frequencies * repeat_each_tone  # Expand to 75 elements
random.shuffle(shuffled_tones)  # Shuffle the order

# Display the shuffled array for reference
print("\nFixed Shuffled Tone Sequence (Used for All Experiments):")
print(shuffled_tones)

# Initialize Pygame mixer for sound playback
pygame.mixer.init(frequency=44100, size=-16, channels=2)

def generate_tone(frequency, duration=1.9, sample_rate=44100):
    """Generates a cosine-squared gated pure tone with 150 ms raise/fall time."""
    t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
    envelope = np.sin(np.pi * t / duration) ** 2  # Cosine-squared gating
    wave = 0.5 * envelope * np.sin(2 * np.pi * frequency * t)  # 50% amplitude modulation
    wave = (wave * 32767).astype(np.int16)  # Convert to 16-bit PCM
    stereo_wave = np.column_stack((wave, wave))  # Stereo format
    return pygame.sndarray.make_sound(stereo_wave)

def play_tone(frequency):
    """Plays a single tone for the configured duration in a non-blocking way."""
    tone = generate_tone(frequency, tone_duration)
    print(f"Playing tone: {frequency} Hz")
    tone.play()  # Start playing tone
    # Do NOT use time.sleep(tone_duration) here to avoid blocking execution

# Start the tone sequence in the main loop
with nidaqmx.Task() as piezo_control_task, nidaqmx.Task() as camera_task:
    # Configure DAQ channels
    piezo_control_task.ao_channels.add_ao_voltage_chan(piezo_control_channel)
    camera_task.do_channels.add_do_chan(camera_trigger_channel)

    print("\nStarting piezo control, camera triggering, and synchronized sound playback...\n")

    volume_count = 0
    tone_index = 0  # Index for shuffled tone list

    while tone_index < (len(shuffled_tones)+1):  # Run until all tones are played
        # Imaging Steps
        for step in range(num_steps):
            target_voltage = step_voltage * step
            piezo_control_task.write(target_voltage, auto_start=True)

            # Wait for stabilization
            time.sleep(stabilization_delay)

            # Trigger the camera
            camera_task.write(True, auto_start=True)  # HIGH signal
            time.sleep(camera_trigger_duration)  # Exposure time
            camera_task.write(False, auto_start=True)  # LOW signal

            print(f"Triggered camera at step {step + 1}")

        # Flyback to initial position
        piezo_control_task.write(flyback_voltage, auto_start=True)
        print(f"Flyback to initial position with voltage: {flyback_voltage} V")
        time.sleep(stabilization_delay / 2)

        # Reset piezo to starting position after flyback
        piezo_control_task.write(0.0, auto_start=True)
        time.sleep(stabilization_delay * 8)  # Stabilize at 0 V

        # Increment volume count
        volume_count += 1

        # **Play tone every 6th volume (NON-BLOCKING)**
        if (volume_count % isi_volumes) == 0:
            if tone_index < len(shuffled_tones):
                print(f"Triggering tone {tone_index+1}/75 at volume {volume_count}: {shuffled_tones[tone_index]} Hz")
                sound_thread = threading.Thread(target=play_tone, args=(shuffled_tones[tone_index],))
                sound_thread.start()  # Play tone in parallel
                tone_index += 1  # Move to next tone in sequence
            else:
                print("All tones completed.")

        print(f"Completed volume {volume_count}")
