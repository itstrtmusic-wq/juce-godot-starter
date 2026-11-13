extends Control

var network: JuceDSPNetwork
var device: JuceAudioDeviceManager
var status: Label
var meter: ProgressBar
var outputs: OptionButton
var inputs: OptionButton
var source: OptionButton
var controls := {"frequency": 220.0, "cutoff": 1800.0, "drive": 1.0, "wet": 0.15, "level": -12.0}

func _ready() -> void:
    device = JuceAudioDeviceManager.new()
    var scroll := ScrollContainer.new()
    scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(scroll)
    var panel := VBoxContainer.new()
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.add_theme_constant_override("separation", 10)
    scroll.add_child(panel)
    var title := Label.new()
    title.text = "JUCE DSP network · assembled in GDScript"
    title.add_theme_font_size_override("font_size", 24)
    panel.add_child(title)
    var info := Label.new()
    info.text = "Source → Low-pass → Distortion → Reverb → Gain → Clip → Output"
    info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    panel.add_child(info)
    status = Label.new()
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status.text = "Choose a source, then start audio. API reference: docs/API_REFERENCE.md"
    panel.add_child(status)
    source = OptionButton.new()
    source.add_item("Oscillator source")
    source.add_item("Live audio input (use headphones)")
    panel.add_child(source)
    outputs = _device_menu(panel, "Default output", device.get_output_devices())
    inputs = _device_menu(panel, "Default input", device.get_input_devices())
    var start := Button.new()
    start.text = "Start DSP network"
    start.pressed.connect(_start)
    panel.add_child(start)
    var stop := Button.new()
    stop.text = "Stop audio"
    stop.pressed.connect(func():
        device.stop_audio()
        status.text = "Stopped. Topology can now be edited."
    )
    panel.add_child(stop)
    _slider(panel, "Oscillator frequency (Hz)", "frequency", 20, 2000)
    _slider(panel, "Low-pass cutoff (Hz)", "cutoff", 20, 20000)
    _slider(panel, "Distortion drive", "drive", 0, 10)
    _slider(panel, "Reverb wet level", "wet", 0, 1)
    _slider(panel, "Output gain (dB)", "level", -60, 0)
    meter = ProgressBar.new()
    meter.max_value = 1
    meter.show_percentage = false
    panel.add_child(meter)

func _device_menu(panel: VBoxContainer, caption: String, names: PackedStringArray) -> OptionButton:
    var menu := OptionButton.new()
    menu.add_item(caption)
    for name in names:
        menu.add_item(name)
    panel.add_child(menu)
    return menu

func _slider(panel: VBoxContainer, caption: String, key: String, low: float, high: float) -> void:
    var label := Label.new()
    label.text = caption
    panel.add_child(label)
    var slider := HSlider.new()
    slider.min_value = low
    slider.max_value = high
    slider.step = 0.01 if high <= 10 else 1.0
    slider.value = controls[key]
    slider.value_changed.connect(func(value: float):
        controls[key] = value
        _update_parameters()
    )
    panel.add_child(slider)

func _start() -> void:
    device.stop_audio()
    network = JuceDSPNetwork.new()
    network.add_node("osc", "oscillator")
    network.add_node("filter", "low_pass")
    network.add_node("drive", "tanh")
    network.add_node("reverb", "reverb")
    network.add_node("level", "gain")
    network.add_node("guard", "clip")
    network.set_parameter("osc", "gain", 0.1)
    network.set_parameter("guard", "threshold", 0.9)
    var origin := "osc" if source.selected == 0 else "input"
    network.connect_nodes(origin, "filter")
    network.connect_nodes("filter", "drive")
    network.connect_nodes("drive", "reverb")
    network.connect_nodes("reverb", "level")
    network.connect_nodes("level", "guard")
    network.connect_nodes("guard", "output")
    _update_parameters()
    device.set_network(network)
    var out_name := "" if outputs.selected == 0 else outputs.get_item_text(outputs.selected)
    var in_name := "" if inputs.selected == 0 else inputs.get_item_text(inputs.selected)
    if device.start_audio(out_name, 48000.0, 256, in_name, source.selected == 1):
        status.text = "Running: %s" % str(device.get_device_info())
    else:
        status.text = device.get_last_error()

func _update_parameters() -> void:
    if network == null:
        return
    network.set_parameter("osc", "frequency", controls.frequency)
    network.set_parameter("filter", "frequency", controls.cutoff)
    network.set_parameter("drive", "drive", controls.drive)
    network.set_parameter("reverb", "wet_level", controls.wet)
    network.set_parameter("level", "gain_db", controls.level)

func _process(_delta: float) -> void:
    if is_instance_valid(meter) and device != null:
        meter.value = device.get_peak()

func _exit_tree() -> void:
    if device != null:
        device.stop_audio()
