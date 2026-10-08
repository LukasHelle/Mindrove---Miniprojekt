from mindrove.board_shim import BoardShim, MindRoveInputParams, BoardIds
from mindrove.data_filter import DataFilter, FilterTypes
import matplotlib.pyplot as plt
import numpy as np

highpass_cutoff = 6.0
lowpass_cutoff = 4.0


BoardShim.enable_dev_board_logger()

params = MindRoveInputParams()
board_id = BoardIds.MINDROVE_WIFI_BOARD
board_shim = BoardShim(board_id, params)

board_shim.prepare_session()
board_shim.start_stream()

eeg_channels = BoardShim.get_eeg_channels(board_id)
accel_channels = BoardShim.get_accel_channels(board_id)
sampling_rate = BoardShim.get_sampling_rate(board_id)

display_seconds = 2
update_seconds = 0.1

display_points = int(display_seconds * sampling_rate)
update_points = int(update_seconds * sampling_rate)

# Create plot once
plt.ion()

fig, axes = plt.subplots(8, 1, figsize=(10, 12), sharex=True)

time_axis = np.arange(display_points) / sampling_rate

lines = []
data_buffer = np.zeros((8, display_points))


for i in range(8):
    line, = axes[i].plot(time_axis, np.zeros(display_points))
    lines.append(line)

    axes[i].set_ylabel(f"CH {i + 1}")

axes[-1].set_xlabel("Time [s]")
fig.suptitle("MindRove - Live EEG")

plt.show(block=False)


try:
    while plt.fignum_exists(fig.number):

        if board_shim.get_board_data_count() >= update_points:

            data = board_shim.get_board_data(update_points)

            eeg_data = data[eeg_channels]

            # Filter
            for i in range(len(eeg_channels)):
                # High-pass filter
                DataFilter.perform_highpass(
                    eeg_data[i],
                    sampling_rate,
                    highpass_cutoff,
                    4,
                    FilterTypes.BUTTERWORTH.value,
                    0
                )

                # Absolute value
                eeg_data[i] = np.abs(eeg_data[i])

                # Low-pass filter
                DataFilter.perform_lowpass(
                    eeg_data[i],
                    sampling_rate,
                    lowpass_cutoff,
                    4,
                    FilterTypes.BUTTERWORTH.value,
                    0
                )

           
            data_buffer = np.roll(
                data_buffer,
                -update_points,
                axis=1
            )

            
            data_buffer[:, -update_points:] = eeg_data

            # Opdater alle 8 kanaler
            for i in range(8):
                lines[i].set_ydata(data_buffer[i])

                axes[i].relim()
                axes[i].autoscale_view(
                    scalex=False,
                    scaley=True
                )

            fig.canvas.draw_idle()

        plt.pause(0.02)

finally:
    board_shim.stop_stream()
    board_shim.release_session()
