import nidaqmx
import time
import threading
import pygame
import random
import os

# ==== CONFIGURATION ====
device_name = "Dev1"
piezo_control_channel = f"{device_name}/ao0"
piezo_feedback_channel = f"{device_name}/ai0"
feedback_monitor_channel = f"{device_name}/ao1"
camera_trigger_channel = f"{device_name}/PFI0"

step_voltage = 0.22 #0.11
flyback_voltage = 4.44
num_steps = 20
stabilization_delay = 0.040
camera_trigger_duration = 0.030

volumes_per_sound = 18  # Play sound after every 6 volumes -> 18
#213 vol / 8520
#425 vol/ 17000

# ==== SOUND FILE SETUP ====
sound_folder = "output_sounds"
sound_filenames = [
    "original.wav",
    "reversed.wav",
    "phase_scrambled.wav",
    "white_noise.wav",
    "bandpassed_noise_2to4kHz.wav",
    "original_shifted_+3kHz.wav",
    "original_shifted_-3kHz.wav"
]
sound_files = [os.path.join(sound_folder, fname) for fname in sound_filenames]

# Create consistent randomized presentation order
random.seed(42) # Answer to life, universe and everything
presentation_order = sound_files * 5  # 5 repeats of each
random.shuffle(presentation_order)

# Optionally save this order for reproducibility
with open("presentation_order.txt", "w") as f:
    for i, path in enumerate(presentation_order):
        f.write(f"{i + 1}: {os.path.basename(path)}\n")

# Init sound system
pygame.mixer.init()
sound_index = 0

def play_sound(path):
    pygame.mixer.music.load(path)
    pygame.mixer.music.play()

# ==== ACQUISITION LOOP ====
with nidaqmx.Task() as piezo_control_task, nidaqmx.Task() as piezo_feedback_task, \
     nidaqmx.Task() as feedback_monitor_task, nidaqmx.Task() as camera_task:

    piezo_control_task.ao_channels.add_ao_voltage_chan(piezo_control_channel)
    piezo_feedback_task.ai_channels.add_ai_voltage_chan(piezo_feedback_channel)
    feedback_monitor_task.ao_channels.add_ao_voltage_chan(feedback_monitor_channel)
    camera_task.do_channels.add_do_chan(camera_trigger_channel)

    print("Starting piezo control, feedback monitoring, camera triggering, and sound playback...")

    volume_count = 0

    while True:
        # Imaging steps per volume
        for step in range(num_steps):
            target_voltage = step_voltage * step
            piezo_control_task.write(target_voltage, auto_start=True)
            time.sleep(stabilization_delay/2)

            current_voltage = piezo_feedback_task.read()
            feedback_monitor_task.write(current_voltage, auto_start=True)

            camera_task.write(True, auto_start=True)
            time.sleep(camera_trigger_duration)
            camera_task.write(False, auto_start=True)

            print(f"Triggered camera at step {step + 1}, feedback voltage: {current_voltage:.6f} V")

        # Flyback
        piezo_control_task.write(flyback_voltage, auto_start=True)
        print(f"Flyback to initial position with voltage: {flyback_voltage} V")
        time.sleep(stabilization_delay / 2)
        piezo_control_task.write(0.0, auto_start=True)
        time.sleep(stabilization_delay / 2) # was * 8

        volume_count += 1

        # Sound playback
        if volume_count % volumes_per_sound == 0 and sound_index < len(presentation_order):
            current_sound = presentation_order[sound_index]
            print(f"Playing sound: {os.path.basename(current_sound)} ({sound_index + 1}/70)")
            threading.Thread(target=play_sound, args=(current_sound,)).start()
            sound_index += 1

        # Exit condition
        if sound_index >= len(presentation_order):
            print("All 35 sounds played. Stopping acquisition.")

        print(f"Completed volume {volume_count}")
