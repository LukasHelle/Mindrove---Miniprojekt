extends HBoxContainer

## Live plots of the Hudgins features from the Emg autoload, one plot per
## feature side by side, one pane (row) per channel.

## How many seconds of data to show on screen.
@export var window_seconds := 5.0

# Hudgins features, in the order features_ready sends them.
const FEATURE_NAMES := ["MAV", "WL", "ZC", "SSC"]

# One dataset per feature, same order as FEATURE_NAMES.
var _datasets: Array[TauPlot.Dataset] = []
var _feature_count := 0


func _ready() -> void:
	var channel_count: int = Emg.band.get_emg_channel_count()
	if channel_count == 0:
		push_error("EmgBand is not streaming, nothing to plot")
		return
	var features_per_second: float = 1000.0 / Emg.features.step_ms
	for feature in FEATURE_NAMES:
		var dataset := _make_dataset(channel_count, int(window_seconds * features_per_second))
		_datasets.append(dataset)
		add_child(_make_plot(feature, dataset, channel_count))
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


func _on_features_ready(mav: PackedFloat64Array, wl: PackedFloat64Array,
		zc: PackedFloat64Array, ssc: PackedFloat64Array,
		_feature_vector: PackedFloat64Array) -> void:
	var t := _feature_count * Emg.features.step_ms / 1000.0
	_feature_count += 1
	var features := [mav, wl, zc, ssc]
	for i in features.size():
		_datasets[i].append_shared_sample(t, features[i])
