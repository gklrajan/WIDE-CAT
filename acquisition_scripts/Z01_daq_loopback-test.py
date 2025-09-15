import PyDAQmx as nidaq
import numpy as np

# DAQ parameters
device_name = "Dev1"
ao_channel = f"{device_name}/ao0"
ai_channel = f"{device_name}/ai4"
test_voltage = 2.0  # Voltage to test with

# Set up AO task
ao_task = nidaq.Task()
ao_task.CreateAOVoltageChan(ao_channel, "", -10.0, 10.0, nidaq.DAQmx_Val_Volts, None)

# Write the test voltage to AO
ao_task.StartTask()
ao_task.WriteAnalogScalarF64(True, 10.0, test_voltage, None)
print(f"Voltage {test_voltage} V written to {ao_channel}.")

# Set up AI task
ai_task = nidaq.Task()
ai_task.CreateAIVoltageChan(ai_channel, "", nidaq.DAQmx_Val_Cfg_Default, -10.0, 10.0, nidaq.DAQmx_Val_Volts, None)

# Read the voltage back from AI
read_voltage = np.zeros(1, dtype=np.float64)
ai_task.StartTask()
ai_task.ReadAnalogF64(1, 10.0, nidaq.DAQmx_Val_GroupByChannel, read_voltage, 1, None, None)
print(f"Voltage read from {ai_channel}: {read_voltage[0]:.2f} V")

# Clean up tasks
ao_task.StopTask()
ao_task.ClearTask()
ai_task.StopTask()
ai_task.ClearTask()