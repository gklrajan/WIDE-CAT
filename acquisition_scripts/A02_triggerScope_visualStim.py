import time
import threading
import numpy as np
import pygame
import nidaqmx

from nidaqmx.constants import (
    AcquisitionType,
    Edge,
    Level,
    TimeUnits,
    RegenerationMode,
)

from nidaqmx.stream_writers import AnalogSingleChannelWriter
from nidaqmx.stream_readers import AnalogSingleChannelReader


# ============================================================
# EXPERIMENT CONFIGURATION
# ============================================================

device_name = "Dev1"


# ------------------------------------------------------------
# PIEZO
# ------------------------------------------------------------

piezo_control_channel = f"{device_name}/ao0"
piezo_feedback_channel = f"{device_name}/ai0"


# ------------------------------------------------------------
# CAMERA
# ------------------------------------------------------------
#
# Camera remains physically connected to PFI0.
#
# NI counter 0 generates the trigger pulses in hardware.
# ------------------------------------------------------------

camera_counter_channel = f"{device_name}/ctr0"
camera_trigger_terminal = f"/{device_name}/PFI0"


# ------------------------------------------------------------
# PIEZO POSITIONS
# ------------------------------------------------------------

step_voltage = 0.22
flyback_voltage = 4.4
num_steps = 20


# ------------------------------------------------------------
# TIMING
# ------------------------------------------------------------
#
# EACH SLICE:
#
# piezo moves
#       |
#       |---- 25 ms stabilization ----|
#                                      |
#                                      camera HIGH
#                                      |---- 30 ms ----|
#                                                        next Z
#
# 25 ms + 30 ms = 55 ms/slice
#
# 20 slices = 1100 ms
#
# Flyback = 25 ms
# Reset   = 25 ms
#
# TOTAL = 1150 ms/volume
#       = ~0.870 Hz
# ------------------------------------------------------------

stabilization_delay = 0.025

camera_trigger_duration = 0.030

flyback_hold = 0.025
reset_hold = 0.025


# ------------------------------------------------------------
# VISUAL STIMULUS
# ------------------------------------------------------------

# PLEASE add your customstim_a.png and customstim_b.png files in the same directory as this script.

image_stimulus_volumes = 5

stimulus_interval = 25


# VisualStim stimulus

image_file = "customstim_a.png"


# Mean-luminance gray background
#
# RGB = 128, 128, 128

background_file = "customstim_b.png"


# Secondary monitor/projector

stimulus_display_index = 1


# ------------------------------------------------------------
# HARDWARE SAMPLE CLOCK
# ------------------------------------------------------------

sample_rate = 1000.0


# ------------------------------------------------------------
# EXPERIMENT LENGTH
# ------------------------------------------------------------
#
# None = run continuously until ESC / Ctrl+C / close
#
# For a short test:
#
# max_volumes = 60
# ------------------------------------------------------------

max_volumes = 305


# ------------------------------------------------------------
# FEEDBACK PRINTING
# ------------------------------------------------------------
#
# False:
# one feedback summary per volume
#
# True:
# additionally show feedback around each exposure
# ------------------------------------------------------------

verbose_feedback = False


# ============================================================
# SHARED THREAD STATE
# ============================================================

stop_event = threading.Event()

state_lock = threading.Lock()

desired_stimulus_on = False

display_change_requested = threading.Event()


# ============================================================
# CALCULATE TIMING
# ============================================================

slice_period = (
    stabilization_delay
    + camera_trigger_duration
)


samples_per_slice = int(
    round(
        slice_period
        * sample_rate
    )
)


samples_flyback = int(
    round(
        flyback_hold
        * sample_rate
    )
)


samples_reset = int(
    round(
        reset_hold
        * sample_rate
    )
)


# ------------------------------------------------------------
# Verify timing can be represented exactly
# ------------------------------------------------------------

if not np.isclose(
    samples_per_slice / sample_rate,
    slice_period,
):
    raise ValueError(
        "Slice timing is not exactly representable "
        "at the selected sample rate."
    )


if not np.isclose(
    samples_flyback / sample_rate,
    flyback_hold,
):
    raise ValueError(
        "Flyback timing is not exactly representable "
        "at the selected sample rate."
    )


if not np.isclose(
    samples_reset / sample_rate,
    reset_hold,
):
    raise ValueError(
        "Reset timing is not exactly representable "
        "at the selected sample rate."
    )


# ============================================================
# BUILD ONE COMPLETE PIEZO VOLUME
# ============================================================
#
# AO waveform:
#
# Z1   = 55 ms
# Z2   = 55 ms
# ...
# Z20  = 55 ms
#
# flyback 4.4 V = 25 ms
# reset 0 V      = 25 ms
#
# ============================================================

piezo_chunks = []


for step in range(num_steps):

    target_voltage = (
        step_voltage * step
    )

    piezo_chunks.append(

        np.full(
            samples_per_slice,
            target_voltage,
            dtype=np.float64,
        )

    )


# ------------------------------------------------------------
# FLYBACK
# ------------------------------------------------------------

piezo_chunks.append(

    np.full(
        samples_flyback,
        flyback_voltage,
        dtype=np.float64,
    )

)


# ------------------------------------------------------------
# RESET TO ZERO
# ------------------------------------------------------------

piezo_chunks.append(

    np.zeros(
        samples_reset,
        dtype=np.float64,
    )

)


piezo_waveform = np.concatenate(
    piezo_chunks
)


samples_per_volume = len(
    piezo_waveform
)


volume_duration = (
    samples_per_volume
    / sample_rate
)


volume_rate = (
    1.0
    / volume_duration
)


# ============================================================
# TIMING CHECK
# ============================================================

expected_duration = (

    num_steps
    * (
        stabilization_delay
        + camera_trigger_duration
    )

    + flyback_hold
    + reset_hold

)


if not np.isclose(
    volume_duration,
    expected_duration,
):

    raise RuntimeError(
        "Calculated volume duration does not match "
        "requested timing."
    )


print()

print(
    "======================================================"
)

print(
    "TIMING"
)

print(
    "======================================================"
)


print(
    f"Slices per volume       : "
    f"{num_steps}"
)


print(
    f"Piezo stabilization     : "
    f"{stabilization_delay * 1000:.1f} ms"
)


print(
    f"Camera HIGH/exposure    : "
    f"{camera_trigger_duration * 1000:.1f} ms"
)


print(
    f"Slice period            : "
    f"{slice_period * 1000:.1f} ms"
)


print(
    f"20-slice scan           : "
    f"{num_steps * slice_period:.3f} s"
)


print(
    f"Flyback                 : "
    f"{flyback_hold * 1000:.1f} ms"
)


print(
    f"Reset                   : "
    f"{reset_hold * 1000:.1f} ms"
)


print(
    f"TOTAL volume duration   : "
    f"{volume_duration:.3f} s"
)


print(
    f"Nominal volume rate     : "
    f"{volume_rate:.3f} Hz"
)


print(
    "======================================================"
)

print()


# ============================================================
# REQUEST VISUAL STATE CHANGE
# ============================================================
#
# IMPORTANT:
#
# The imaging thread DOES NOT wait for Pygame.
#
# It simply requests:
#
# stimulus ON
#
# or
#
# stimulus OFF
#
# NI hardware continues controlling acquisition.
# ============================================================

def request_stimulus_state(turn_on):

    global desired_stimulus_on

    with state_lock:

        desired_stimulus_on = bool(
            turn_on
        )

    display_change_requested.set()


# ============================================================
# HARDWARE-TIMED IMAGING THREAD
# ============================================================

def imaging_loop():

    volume_count = 0

    stimulus_end_volume = None


    feedback_buffer = np.zeros(
        samples_per_volume,
        dtype=np.float64,
    )


    try:

        with nidaqmx.Task() as ao_task, \
             nidaqmx.Task() as ai_task, \
             nidaqmx.Task() as camera_task:


            # =================================================
            # PIEZO AO0
            # =================================================

            ao_task.ao_channels.add_ao_voltage_chan(
                piezo_control_channel
            )


            ao_task.timing.cfg_samp_clk_timing(

                rate=sample_rate,

                sample_mode=(
                    AcquisitionType.FINITE
                ),

                samps_per_chan=(
                    samples_per_volume
                ),

            )


            ao_task.out_stream.regen_mode = (
                RegenerationMode.ALLOW_REGENERATION
            )


            ao_writer = (
                AnalogSingleChannelWriter(
                    ao_task.out_stream,
                    auto_start=False,
                )
            )


            # Load complete volume waveform into NI buffer.

            ao_writer.write_many_sample(

                piezo_waveform,

                timeout=10.0,

            )


            # =================================================
            # PIEZO FEEDBACK AI0
            # ============================================================

            ai_task.ai_channels.add_ai_voltage_chan(
                piezo_feedback_channel
            )


            # Use AO hardware sample clock.

            ai_task.timing.cfg_samp_clk_timing(

                rate=sample_rate,

                source=(
                    f"/{device_name}/ao/SampleClock"
                ),

                active_edge=Edge.RISING,

                sample_mode=(
                    AcquisitionType.FINITE
                ),

                samps_per_chan=(
                    samples_per_volume
                ),

            )


            # AI waits for AO start.

            ai_task.triggers.start_trigger.\
                cfg_dig_edge_start_trig(

                    f"/{device_name}/ao/StartTrigger",

                    trigger_edge=Edge.RISING,

                )


            ai_reader = (
                AnalogSingleChannelReader(
                    ai_task.in_stream
                )
            )


            # =================================================
            # CAMERA HARDWARE COUNTER
            # ============================================================
            #
            # Each slice:
            #
            # t = 0 ms
            # Piezo changes
            #
            # t = 25 ms
            # Camera HIGH
            #
            # t = 55 ms
            # Camera LOW
            # Next piezo position
            #
            # ============================================================

            camera_channel = (

                camera_task.co_channels.
                add_co_pulse_chan_time(

                    camera_counter_channel,

                    units=TimeUnits.SECONDS,

                    idle_state=Level.LOW,

                    # Wait 25 ms after piezo step
                    initial_delay=(
                        stabilization_delay
                    ),

                    # 25-ms interval before subsequent pulses
                    low_time=(
                        stabilization_delay
                    ),

                    # Camera HIGH for 30 ms
                    high_time=(
                        camera_trigger_duration
                    ),

                )

            )


            # Send counter output to existing camera terminal.

            camera_channel.co_pulse_term = (
                camera_trigger_terminal
            )


            # Exactly 20 camera pulses.

            camera_task.timing.cfg_implicit_timing(

                sample_mode=(
                    AcquisitionType.FINITE
                ),

                samps_per_chan=(
                    num_steps
                ),

            )


            # Camera starts from same AO hardware trigger.

            camera_task.triggers.start_trigger.\
                cfg_dig_edge_start_trig(

                    f"/{device_name}/ao/StartTrigger",

                    trigger_edge=Edge.RISING,

                )


            print()

            print(
                "======================================================"
            )

            print(
                "HARDWARE-TIMED IMAGING STARTED"
            )

            print(
                "======================================================"
            )


            print(
                f"Piezo AO          : "
                f"{piezo_control_channel}"
            )


            print(
                f"Feedback AI       : "
                f"{piezo_feedback_channel}"
            )


            print(
                f"Camera counter    : "
                f"{camera_counter_channel}"
            )


            print(
                f"Camera terminal   : "
                f"{camera_trigger_terminal}"
            )


            print(
                f"Volume duration   : "
                f"{volume_duration:.3f} s"
            )


            print(
                f"Nominal rate      : "
                f"{volume_rate:.3f} Hz"
            )


            print(
                f"Stimulus interval : "
                f"{stimulus_interval} volumes"
            )


            print(
                f"Stimulus duration : "
                f"{image_stimulus_volumes} volumes"
            )


            print(
                "Baseline           : "
                "RGB(128,128,128) gray"
            )


            print(
                "======================================================"
            )

            print()


            # =================================================
            # VOLUME LOOP
            # =================================================

            while not stop_event.is_set():


                if (
                    max_volumes is not None
                    and
                    volume_count >= max_volumes
                ):

                    print(
                        f"Reached max_volumes = "
                        f"{max_volumes}"
                    )

                    break


                # =============================================
                # ARM AI + CAMERA
                # =============================================

                ai_task.start()

                camera_task.start()


                # =============================================
                # START PIEZO AO
                # =============================================
                #
                # From here on, timing is generated by
                # NI hardware.
                # =============================================

                ao_task.start()


                # =============================================
                # WAIT FOR VOLUME TO COMPLETE
                # =============================================

                while not ao_task.is_task_done():

                    if stop_event.is_set():
                        break

                    time.sleep(0.002)


                if stop_event.is_set():

                    try:
                        ao_task.stop()
                    except Exception:
                        pass

                    try:
                        camera_task.stop()
                    except Exception:
                        pass

                    try:
                        ai_task.stop()
                    except Exception:
                        pass

                    break


                # Camera finishes before AO because the last
                # 50 ms of AO are flyback/reset.

                camera_task.wait_until_done(
                    timeout=1.0
                )


                # =============================================
                # READ PIEZO FEEDBACK
                # =============================================

                ai_reader.read_many_sample(

                    feedback_buffer,

                    number_of_samples_per_channel=(
                        samples_per_volume
                    ),

                    timeout=1.0,

                )


                # =============================================
                # STOP + REARM TASKS
                # =============================================

                ao_task.stop()

                camera_task.stop()

                ai_task.stop()


                volume_count += 1


                # =============================================
                # FEEDBACK SUMMARY
                # =============================================

                feedback_mean = float(
                    np.mean(
                        feedback_buffer
                    )
                )


                feedback_min = float(
                    np.min(
                        feedback_buffer
                    )
                )


                feedback_max = float(
                    np.max(
                        feedback_buffer
                    )
                )


                print(

                    f"Volume "
                    f"{volume_count:04d} complete | "

                    f"feedback mean = "
                    f"{feedback_mean:.3f} V | "

                    f"range = "
                    f"{feedback_min:.3f} to "
                    f"{feedback_max:.3f} V"

                )


                # =============================================
                # OPTIONAL PER-SLICE FEEDBACK
                # =============================================

                if verbose_feedback:

                    for step in range(
                        num_steps
                    ):


                        slice_start = (
                            step
                            * samples_per_slice
                        )


                        exposure_start_index = (

                            slice_start

                            + int(
                                stabilization_delay
                                * sample_rate
                            )

                            - 1

                        )


                        exposure_end_index = (

                            slice_start

                            + samples_per_slice

                            - 1

                        )


                        feedback_at_start = (
                            feedback_buffer[
                                exposure_start_index
                            ]
                        )


                        feedback_at_end = (
                            feedback_buffer[
                                exposure_end_index
                            ]
                        )


                        print(

                            f"    Slice "
                            f"{step + 1:02d}: "

                            f"camera-start feedback = "
                            f"{feedback_at_start:.4f} V | "

                            f"camera-end feedback = "
                            f"{feedback_at_end:.4f} V"

                        )


                # =============================================
                # STIMULUS ON
                # =============================================
                #
                # After volume 25:
                #
                # gray -> VisualStim
                #
                # VisualStim then remains present during
                # volumes 26-30.
                # =============================================

                if (

                    stimulus_end_volume is None

                    and

                    volume_count
                    % stimulus_interval
                    == 0

                ):


                    stimulus_end_volume = (

                        volume_count
                        + image_stimulus_volumes

                    )


                    print(

                        f">>> REQUEST VisualStim ON "
                        f"after volume "
                        f"{volume_count}"

                    )


                    request_stimulus_state(
                        True
                    )


                # =============================================
                # STIMULUS OFF
                # =============================================
                #
                # Return to mean-luminance gray.
                # =============================================

                elif (

                    stimulus_end_volume
                    is not None

                    and

                    volume_count
                    >= stimulus_end_volume

                ):


                    print(

                        f">>> REQUEST VisualStim OFF "
                        f"after volume "
                        f"{volume_count}"

                    )


                    request_stimulus_state(
                        False
                    )


                    stimulus_end_volume = None


    except Exception as exc:


        print()

        print(
            "======================================================"
        )

        print(
            "NI-DAQ ERROR"
        )

        print(
            "======================================================"
        )

        print(
            repr(exc)
        )

        print(
            "======================================================"
        )

        print()


        print(

            "If the error specifically mentions "
            "ctr0, PFI0, or routing, the NI device "
            "may require a different counter/PFI route."

        )


        stop_event.set()


    finally:


        stop_event.set()

        display_change_requested.set()


        # ----------------------------------------------------
        # FORCE PIEZO BACK TO ZERO
        # ----------------------------------------------------

        try:

            with nidaqmx.Task() as reset_task:

                reset_task.ao_channels.add_ao_voltage_chan(
                    piezo_control_channel
                )

                reset_task.write(
                    0.0,
                    auto_start=True,
                )


        except Exception as reset_error:

            print(

                "Could not explicitly reset "
                "AO0 to zero:",

                reset_error,

            )


        print()

        print(
            "Imaging stopped."
        )


# ============================================================
# PYGAME INITIALIZATION
# ============================================================
#
# Pygame remains entirely in the MAIN THREAD.
#
# Display is created ONCE and stays open for the whole
# experiment.
# ============================================================

pygame.init()


display_count = (
    pygame.display.get_num_displays()
)


print(
    f"Available displays: "
    f"{display_count}"
)


if (
    display_count
    <= stimulus_display_index
):

    pygame.quit()

    raise RuntimeError(

        f"Display "
        f"{stimulus_display_index} requested, "

        f"but only "
        f"{display_count} display(s) detected."

    )


desktop_sizes = (
    pygame.display.get_desktop_sizes()
)


screen_width, screen_height = (

    desktop_sizes[
        stimulus_display_index
    ]

)


print(

    f"Stimulus display: "
    f"{screen_width} x "
    f"{screen_height}"

)


# ============================================================
# CREATE PROJECTOR WINDOW ONCE
# ============================================================

stimulus_screen = pygame.display.set_mode(

    (
        screen_width,
        screen_height,
    ),

    pygame.NOFRAME,

    display=(
        stimulus_display_index
    ),

)


pygame.display.set_caption(
    "Stimulus Presentation"
)


# ============================================================
# LOAD VisualStim
# ============================================================

stimulus_image = pygame.image.load(
    image_file
).convert()


# ============================================================
# LOAD GRAY BACKGROUND
# ============================================================

background_image = pygame.image.load(
    background_file
).convert()


# ============================================================
# CHECK IMAGE DIMENSIONS
# ============================================================

image_width, image_height = (
    stimulus_image.get_size()
)


background_width, background_height = (
    background_image.get_size()
)


if (

    image_width
    != background_width

    or

    image_height
    != background_height

):

    raise RuntimeError(

        "customstim_a.png and customstim_b.png "
        "must have identical dimensions."

    )


print(

    f"Stimulus image: "
    f"{image_width} x "
    f"{image_height}"

)


# ============================================================
# CENTER IMAGE
# ============================================================

image_position = (

    (
        screen_width
        - image_width
    ) // 2,

    (
        screen_height
        - image_height
    ) // 2,

)


# ============================================================
# FUNCTION: DRAW GRAY BASELINE
# ============================================================
#
# Entire display is first filled RGB(128,128,128).
#
# customstim_b.png is then placed in exactly the same location
# occupied by customstim_a.png.
#
# This ensures that if the projector resolution is slightly
# larger than the stimulus image, the surrounding region
# ALSO stays gray.
# ============================================================

def draw_gray_background():

    stimulus_screen.fill(
        (128, 128, 128)
    )

    stimulus_screen.blit(
        background_image,
        image_position,
    )

    pygame.display.flip()


# ============================================================
# FUNCTION: DRAW VisualStim
# ============================================================
#
# The surrounding screen remains gray.
#
# ONLY the stimulus region changes from uniform gray
# to VisualStim.
# ============================================================

def draw_VisualStim():

    stimulus_screen.fill(
        (128, 128, 128)
    )

    stimulus_screen.blit(
        stimulus_image,
        image_position,
    )

    pygame.display.flip()


# ============================================================
# START WITH GRAY BASELINE
# ============================================================

draw_gray_background()


print(
    ">>> INITIAL DISPLAY: "
    "MEAN-LUMINANCE GRAY"
)


# ============================================================
# START NI IMAGING THREAD
# ============================================================

imaging_thread = threading.Thread(

    target=imaging_loop,

    name="NI-Imaging",

    daemon=True,

)


imaging_thread.start()


# ============================================================
# MAIN PYGAME LOOP
# ============================================================

clock = pygame.time.Clock()


rendered_stimulus_on = False


try:

    while not stop_event.is_set():


        # ----------------------------------------------------
        # PYGAME EVENTS
        # ----------------------------------------------------

        for event in pygame.event.get():


            if event.type == pygame.QUIT:

                stop_event.set()


            elif event.type == pygame.KEYDOWN:

                if (
                    event.key
                    == pygame.K_ESCAPE
                ):

                    print(
                        "ESC pressed. Stopping."
                    )

                    stop_event.set()


        # ----------------------------------------------------
        # VISUAL STATE CHANGE REQUEST
        # ----------------------------------------------------

        if (
            display_change_requested.is_set()
        ):


            with state_lock:

                requested_state = (
                    desired_stimulus_on
                )


            # Only redraw when necessary.

            if (
                requested_state
                != rendered_stimulus_on
            ):


                # =============================================
                # VisualStim ON
                # =============================================

                if requested_state:

                    draw_VisualStim()

                    rendered_stimulus_on = True


                    print(

                        ">>> VISUAL STIMULUS: "
                        "VisualStim"

                    )


                # =============================================
                # VisualStim OFF -> GRAY
                # =============================================

                else:

                    draw_gray_background()

                    rendered_stimulus_on = False


                    print(

                        ">>> VISUAL STIMULUS OFF: "
                        "GRAY BACKGROUND"

                    )


            display_change_requested.clear()


        # ----------------------------------------------------
        # MAIN THREAD SERVICE RATE
        # ----------------------------------------------------
        #
        # This does NOT control acquisition timing.
        # ----------------------------------------------------

        clock.tick(
            200
        )


except KeyboardInterrupt:


    print(
        "Ctrl+C received. Stopping."
    )

    stop_event.set()


finally:


    stop_event.set()


    imaging_thread.join(
        timeout=3.0
    )


    # ========================================================
    # LEAVE PROJECTOR ON GRAY
    # ========================================================

    try:

        draw_gray_background()

    except Exception:

        pass


    pygame.quit()


    print(
        "Experiment terminated."
    )