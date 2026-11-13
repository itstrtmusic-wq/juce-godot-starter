extends SceneTree

var errors: Array[String] = []
var starts := 0

func _initialize() -> void:
    if not ClassDB.class_exists("JuceEngine"):
        push_error("JuceEngine did not register")
        quit(1)
        return
    var engine: Node = ClassDB.instantiate("JuceEngine")
    root.add_child(engine)
    engine.audio_error.connect(func(message: String): errors.append(message))
    engine.audio_started.connect(func(): starts += 1)
    assert(not engine.is_running())
    assert(engine.get_peak() == 0.0)
    engine.set_gain(0.05)
    engine.set_frequency(440.0)
    engine.set_tone_enabled(true)
    assert(not engine.start_audio("", -1.0, 256))
    assert(errors.size() == 1)
    assert(not engine.get_last_error().is_empty())
    assert(not engine.is_running())
    assert(starts == 0)
    assert(engine.get_device_info().is_empty())
    engine.stop_audio()
    engine.stop_audio()
    if "--expect-no-device" in OS.get_cmdline_user_args():
        assert(engine.get_output_devices().is_empty())
        assert(not engine.start_audio())
        assert(errors.size() == 2)
        assert(not engine.is_running())
    engine.free()
    print("GDScript registration, controls, startup validation, signals and shutdown passed")
    quit(0)
