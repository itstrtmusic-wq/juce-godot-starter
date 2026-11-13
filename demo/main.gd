extends Control

var engine: Node
var status: Label
var meter: ProgressBar
var devices: OptionButton

func _ready() -> void:
    var panel := VBoxContainer.new()
    panel.position = Vector2(28, 24)
    panel.custom_minimum_size.x = 580
    panel.add_theme_constant_override("separation", 12)
    add_child(panel)
    var title := Label.new()
    title.text = "Godot + JUCE audio bridge"
    title.add_theme_font_size_override("font_size", 25)
    panel.add_child(title)
    status = Label.new()
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    panel.add_child(status)
    if not ClassDB.class_exists("JuceEngine"):
        status.text = "Build the native addon first. See README.md and build_windows.ps1."
        return
    engine = ClassDB.instantiate("JuceEngine")
    add_child(engine)
    engine.audio_error.connect(func(message: String): status.text = message)
    devices = OptionButton.new()
    devices.add_item("Default output device")
    for device in engine.get_output_devices():
        devices.add_item(device)
    panel.add_child(devices)
    var start := Button.new()
    start.text = "Start audio"
    start.pressed.connect(_start_audio)
    panel.add_child(start)
    var stop := Button.new()
    stop.text = "Stop audio"
    stop.pressed.connect(func():
        engine.stop_audio()
        status.text = "Audio stopped"
    )
    panel.add_child(stop)
    var enabled := CheckButton.new()
    enabled.text = "Enable test tone"
    enabled.toggled.connect(func(value: bool): engine.set_tone_enabled(value))
    panel.add_child(enabled)
    _slider(panel, "Frequency (Hz)", 20.0, 2000.0, 440.0,
        func(value: float): engine.set_frequency(value))
    _slider(panel, "Gain (linear)", 0.0, 0.2, 0.05,
        func(value: float): engine.set_gain(value))
    meter = ProgressBar.new()
    meter.max_value = 1.0
    meter.show_percentage = false
    panel.add_child(meter)
    status.text = "Ready. Start audio, then enable the test tone."

func _slider(panel: VBoxContainer, caption: String, low: float, high: float,
        initial: float, callback: Callable) -> void:
    var label := Label.new()
    label.text = caption
    panel.add_child(label)
    var slider := HSlider.new()
    slider.min_value = low
    slider.max_value = high
    slider.step = 0.001 if high < 1.0 else 1.0
    slider.value = initial
    slider.value_changed.connect(callback)
    panel.add_child(slider)

func _start_audio() -> void:
    var device := "" if devices.selected == 0 else devices.get_item_text(devices.selected)
    if engine.start_audio(device, 48000.0, 256):
        status.text = "Audio started: %s" % str(engine.get_device_info())

func _process(_delta: float) -> void:
    if is_instance_valid(engine) and is_instance_valid(meter):
        meter.value = engine.get_peak()

func _exit_tree() -> void:
    if is_instance_valid(engine):
        engine.stop_audio()
