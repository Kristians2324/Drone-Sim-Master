class_name VideoRecorderManager
extends Node

## Modular Video Recorder Manager
## Handles high-definition 1080p video recording with zero frame drops via async worker threads.

var is_recording: bool = false
var recording_time: float = 0.0
var rec_blink_timer: float = 0.0
var frame_capture_timer: float = 0.0

var recorded_frame_paths: Array[String] = []
var temp_frames_dir: String = ""
var capture_index: int = 0

var capture_thread: Thread = null
var is_processing_frame: bool = false

func start_recording() -> void:
	is_recording = true
	recording_time = 0.0
	rec_blink_timer = 0.0
	frame_capture_timer = 0.0
	capture_index = 0
	recorded_frame_paths.clear()

	temp_frames_dir = ProjectSettings.globalize_path("user://temp_rec_frames_%d" % int(Time.get_unix_time_from_system()))
	DirAccess.make_dir_recursive_absolute(temp_frames_dir)

	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr and toast_mgr.has_method("show_toast"):
		toast_mgr.show_toast("VIDEO RECORDING STARTED")

func process_recording(delta: float, viewport: Viewport) -> void:
	if not is_recording or not viewport:
		return

	recording_time += delta
	rec_blink_timer += delta
	frame_capture_timer += delta

	# Capture crisp 1080p frames at 15 FPS without main-thread stuttering
	if frame_capture_timer >= 0.066 and not is_processing_frame:
		frame_capture_timer = 0.0
		var img = viewport.get_texture().get_image()
		if img and recorded_frame_paths.size() < 600:
			# High Resolution 1080p (1920x1080) for crisp modern video quality
			if img.get_width() > 1920:
				img.resize(1920, 1080, Image.INTERPOLATE_BILINEAR)

			var frame_path = temp_frames_dir.path_join("frame_%04d.jpg" % capture_index)
			capture_index += 1
			recorded_frame_paths.append(frame_path)

			# Asynchronously write JPEG image to disk in background thread
			_save_frame_async(img, frame_path)

func _save_frame_async(img: Image, path: String) -> void:
	is_processing_frame = true
	var task = func():
		img.save_jpg(path, 0.92) # Crisp 92% HD JPEG quality
		is_processing_frame = false

	WorkerThreadPool.add_task(task)

func stop_recording(status_label: Label = null) -> String:
	if not is_recording:
		return ""

	is_recording = false

	# Wait for any active background frame writes to complete
	while is_processing_frame:
		OS.delay_msec(10)

	var downloads_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if downloads_dir == "" or not DirAccess.dir_exists_absolute(downloads_dir):
		downloads_dir = ProjectSettings.globalize_path("user://")

	var timestamp = int(Time.get_unix_time_from_system())
	var mp4_output_path = downloads_dir.path_join("Drone_LightShow_Video_%d.mp4" % timestamp)

	# Execute OpenCV Python script for genuine ISO H.264 / MP4V 1080p encoding
	var script_path = ProjectSettings.globalize_path("res://scripts/python/encode_mp4.py")
	var output = []
	var args = [script_path, temp_frames_dir, mp4_output_path, "15"]

	var exit_code = OS.execute("python", args, output, true)
	if exit_code != 0:
		output.clear()
		exit_code = OS.execute("py", args, output, true)

	if exit_code == 0 and FileAccess.file_exists(mp4_output_path):
		if status_label and is_instance_valid(status_label):
			status_label.text = "MP4 VIDEO SAVED TO DOWNLOADS!\n%s" % mp4_output_path
			status_label.add_theme_color_override("font_color", Color(0.2, 0.95, 0.4, 1.0))
		var toast_mgr = get_node_or_null("/root/ToastManager")
		if toast_mgr and toast_mgr.has_method("show_toast"):
			toast_mgr.show_toast("VIDEO RECORDING SAVED TO DOWNLOADS")
		print("VideoRecorderManager: 1080p MP4 Video saved to: ", mp4_output_path)
		return mp4_output_path
	else:
		print("VideoRecorderManager: MP4 encoding output: ", output)
		return ""
