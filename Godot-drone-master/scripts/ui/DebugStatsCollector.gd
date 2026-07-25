class_name DebugStatsCollector
extends RefCounted

static func collect_stats() -> Array[String]:
	var stat_lines: Array[String] = []
	var rs := RenderingServer

	# ── Performance ───────────────────────────────────────────────────
	var fps := Engine.get_frames_per_second()
	var ms := 0.0
	if fps > 0:
		ms = 1000.0 / fps
	stat_lines.append("─── Performance ───────────────")
	stat_lines.append("FPS:        %d  (%.2f ms)" % [fps, ms])
	stat_lines.append("Engine ver: %s" % Engine.get_version_info().string)

	# ── Memory ─────────────────────────────────────────────────────────
	var static_mem := float(OS.get_static_memory_usage())
	var static_peak := float(OS.get_static_memory_peak_usage())
	stat_lines.append("")
	stat_lines.append("─── Memory ────────────────────")
	stat_lines.append("RAM Used:   %s" % format_bytes(static_mem))
	stat_lines.append("RAM Peak:   %s" % format_bytes(static_peak))

	# ── VRAM / GPU ─────────────────────────────────────────────────────────
	var tex_mem := float(rs.get_rendering_info(rs.RENDERING_INFO_TEXTURE_MEM_USED))
	var buf_mem := float(rs.get_rendering_info(rs.RENDERING_INFO_BUFFER_MEM_USED))
	var total_vram := tex_mem + buf_mem
	stat_lines.append("")
	stat_lines.append("─── VRAM / GPU ────────────────")
	stat_lines.append("Textures:   %s" % format_bytes(tex_mem))
	stat_lines.append("Buffers:    %s" % format_bytes(buf_mem))
	stat_lines.append("VRAM Total: %s" % format_bytes(total_vram))

	# ── Renderer Objects ───────────────────────────────────────────────────
	var objects := rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var primitives := rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var draw_calls := rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)

	stat_lines.append("")
	stat_lines.append("─── Render Pipeline ────────────")
	stat_lines.append("Objects:    %d" % objects)
	stat_lines.append("Primitives: %d" % primitives)
	stat_lines.append("Draw Calls: %d" % draw_calls)

	return stat_lines

static func format_bytes(bytes: float) -> String:
	if bytes < 1024.0:
		return "%.0f B" % bytes
	elif bytes < 1024.0 * 1024.0:
		return "%.2f KB" % (bytes / 1024.0)
	elif bytes < 1024.0 * 1024.0 * 1024.0:
		return "%.2f MB" % (bytes / (1024.0 * 1024.0))
	else:
		return "%.2f GB" % (bytes / (1024.0 * 1024.0 * 1024.0))
