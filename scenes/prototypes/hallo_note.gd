extends Node

## How many seconds of data to show on screen.
@export var window_seconds := 5.0

# Hudgins features, in the order features_ready sends them.
const FEATURE_NAMES := ["MAV", "WL", "ZC", "SSC"]

var _dataset: TauPlot.Dataset
# One dataset per feature, same order as FEATURE_NAMES.
var _feature_datasets: Array[TauPlot.Dataset] = []
var _sample_rate := 250.0
var _sample_count := 0
var _feature_count := 0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Uses the Emg autoload's band (only one connection to the band is possible).
	# Autoloads are ready before any scene, so the stream is already started.
	var channel_count: int = Emg.band.get_emg_channel_count()
	if channel_count == 0:
		push_error("EmgBand is not streaming, nothing to plot")
		return
	_sample_rate = Emg.band.get_sampling_rate()

	# Ring buffers: keep the last window_seconds of data, older values drop off.
	_dataset = _make_dataset(channel_count, int(window_seconds * _sample_rate))
	var features_per_second: float = 1000.0 / Emg.features.step_ms
	for _feature in FEATURE_NAMES:
		_feature_datasets.append(_make_dataset(channel_count, int(window_seconds * features_per_second)))

	# Raw EMG on the left (twice as wide), then one plot per feature, same row = same channel.
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	var raw_plot := _make_plot("Raw EMG", _dataset, channel_count)
	raw_plot.size_flags_stretch_ratio = 2.0
	row.add_child(raw_plot)
	for i in FEATURE_NAMES.size():
		row.add_child(_make_plot(FEATURE_NAMES[i], _feature_datasets[i], channel_count))

	Emg.band.emg_received.connect(_on_emg_received)
	Emg.features.features_ready.connect(_on_features_ready)


func _make_dataset(channel_count: int, capacity: int) -> TauPlot.Dataset:
	var dataset := TauPlot.Dataset.new(
		TauPlot.Dataset.Mode.SHARED_X,
		TauPlot.Dataset.XElementType.NUMERIC,
		capacity
	)
	for i in channel_count:
		dataset.add_series("Ch %d" % (i + 1))
	return dataset


# Builds a plot with one pane (row) per channel, all sharing the time axis.
func _make_plot(title: String, dataset: TauPlot.Dataset, channel_count: int) -> TauPlot:
	var x_axis := TauAxisConfig.new()
	x_axis.title = "Time (s)"
	x_axis.include_zero_in_domain = false
	# Look ahead a bit so the axis is not recomputed every frame.
	x_axis.domain_padding_mode = TauAxisConfig.DomainPaddingMode.DATA_UNITS
	x_axis.domain_padding_min = 0.0
	x_axis.domain_padding_max = 0.75

	var panes: Array[TauPaneConfig] = []
	var bindings: Array[TauXYSeriesBinding] = []
	for i in channel_count:
		var y_axis := TauAxisConfig.new()
		y_axis.title = "Ch %d" % (i + 1)

		var pane := TauPaneConfig.new()
		pane.y_left_axis = y_axis
		pane.overlays = [TauLineConfig.new()]
		panes.append(pane)

		var binding := TauXYSeriesBinding.new()
		binding.series_id = dataset.get_series_id_by_index(i)
		binding.pane_index = i
		binding.overlay_type = TauXYSeriesBinding.PaneOverlayType.LINE
		binding.y_axis_id = TauPlot.AxisId.LEFT
		binding.show_in_legend = false
		bindings.append(binding)

	var config := TauXYConfig.new()
	config.x_axis = x_axis
	config.panes = panes

	var plot := TauPlot.new()
	plot.title = title
	plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plot.plot_xy(dataset, config, bindings)
	return plot


# Called every time new EMG data arrives from the band (about once per frame).
# emg has one PackedFloat64Array per channel with all the new samples.
func _on_emg_received(emg: Array) -> void:

	var channel_count := emg.size()
	var new_samples: int = emg[0].size()

	# Batch so the plot redraws once per frame instead of once per sample.
	_dataset.begin_batch()
	for s in new_samples:
		var values := PackedFloat64Array()
		values.resize(channel_count)
		for ch in channel_count:
			values[ch] = emg[ch][s]
		_dataset.append_shared_sample(_sample_count / _sample_rate, values)
		_sample_count += 1
	_dataset.end_batch()


# Called every step_ms (50 ms by default) with the Hudgins features of the last
# window_ms of EMG. Each array has one value per channel.
# feature_vector is everything flattened, for feeding a classifier later.
func _on_features_ready(mav: PackedFloat64Array, wl: PackedFloat64Array,
		zc: PackedFloat64Array, ssc: PackedFloat64Array,
		feature_vector: PackedFloat64Array) -> void:
	# Time of the newest sample in this window, so the features line up with the raw EMG.
	# Window and step are whole numbers of samples, rounded like HudginsFeatures does.
	var window_samples: int = roundi(Emg.features.window_ms * _sample_rate / 1000.0)
	var step_samples: int = roundi(Emg.features.step_ms * _sample_rate / 1000.0)
	var t := (window_samples + _feature_count * step_samples) / _sample_rate
	_feature_count += 1
	var features := [mav, wl, zc, ssc]
	for i in features.size():
		_feature_datasets[i].append_shared_sample(t, features[i])
