import sys
import os
import json
import math
import numpy as np

def parse_3d_file(file_path):
    ext = os.path.splitext(file_path)[1].lower()
    groups = {}
    current_group = "default"
    groups[current_group] = []

    ignored_keywords = ["floor", "ground", "backdrop", "plane", "studio", "camera", "light", "grid", "shadow", "stage", "environment", "box"]

    if ext == ".obj":
        file_size = os.path.getsize(file_path)
        stride = 1
        if file_size > 30 * 1024 * 1024:
            stride = 5
        elif file_size > 10 * 1024 * 1024:
            stride = 2

        line_count = 0
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line_count += 1
                if stride > 1 and line_count % stride != 0:
                    continue
                line = line.strip()

                if line.startswith("o ") or line.startswith("g "):
                    g_name = line.split(maxsplit=1)[1].lower()
                    if not any(k in g_name for k in ignored_keywords):
                        current_group = g_name
                        if current_group not in groups:
                            groups[current_group] = []
                    else:
                        current_group = "ignored"

                elif line.startswith("v ") or line.startswith("v\t") or line.startswith("v  "):
                    if current_group == "ignored":
                        continue
                    parts = line.split()
                    if len(parts) >= 4 and parts[0] == "v":
                        try:
                            x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
                            groups[current_group].append([x, y, z])
                        except ValueError:
                            pass
    elif ext in [".stl", ".ply"]:
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if line.startswith("vertex ") or not line.startswith("element"):
                    parts = line.split()
                    if len(parts) >= 3:
                        try:
                            x, y, z = float(parts[-3]), float(parts[-2]), float(parts[-1])
                            groups[current_group].append([x, y, z])
                        except ValueError:
                            pass
    elif ext == ".json":
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            data = json.load(f)
            pts = data.get("points", [])
            for pt in pts:
                if isinstance(pt, dict):
                    groups[current_group].append([float(pt.get("x", 0.0)), float(pt.get("y", 0.0)), float(pt.get("z", 0.0))])

    all_pts = []
    for g_name, pts in groups.items():
        if g_name != "ignored" and len(pts) > 0:
            all_pts.extend(pts)

    if len(all_pts) == 0 and len(groups.get("ignored", [])) > 0:
        all_pts = groups["ignored"]

    return all_pts

def filter_outer_surface_shell_only(scaled_pts):
    if len(scaled_pts) < 20:
        return scaled_pts

    norms = np.linalg.norm(scaled_pts, axis=1)
    max_norm = np.max(norms)
    if max_norm <= 0.001:
        return scaled_pts

    unit_dirs = scaled_pts / np.maximum(norms[:, np.newaxis], 1e-5)
    dir_bins = {}

    for i, p in enumerate(scaled_pts):
        u = unit_dirs[i]
        r = norms[i]
        key = (int(round(u[0] * 6)), int(round(u[1] * 6)), int(round(u[2] * 6)))
        if key not in dir_bins:
            dir_bins[key] = []
        dir_bins[key].append((r, p))

    outer_pts = []
    for key, items in dir_bins.items():
        max_r_in_bin = max(item[0] for item in items)
        shell_min_r = max_r_in_bin * 0.85
        for r, p in items:
            if r >= shell_min_r:
                outer_pts.append(p)

    if len(outer_pts) < 15:
        return scaled_pts

    return np.array(outer_pts, dtype=np.float32)

def calculate_smart_optimal_3d_drone_count(pts_arr, scale_size=20.0):
    if len(pts_arr) < 10:
        return 80

    p_min = np.min(pts_arr, axis=0)
    p_max = np.max(pts_arr, axis=0)
    dims = p_max - p_min
    max_dim = float(np.max(dims))
    if max_dim <= 0.001:
        max_dim = 1.0

    sx = (dims[0] / max_dim) * scale_size
    sy = (dims[1] / max_dim) * scale_size
    sz = (dims[2] / max_dim) * scale_size

    estimated_surface_area = 2.0 * (sx * sy + sy * sz + sz * sx)
    # Target spacing: ~1.4 meters per drone to guarantee crisp separation in 20x20x20m volume
    target_area_per_drone = 1.96
    raw_optimal = estimated_surface_area / target_area_per_drone

    return int(round(max(40, min(250, raw_optimal))))

def process_3d_shape(file_path, target_count=0, output_json_path=None, scale_size=20.0):
    if not os.path.exists(file_path):
        print(f"Error: File '{file_path}' does not exist.")
        return False

    raw_points = parse_3d_file(file_path)
    if not raw_points or len(raw_points) == 0:
        print(f"Error: No valid 3D points extracted from '{file_path}'.")
        return False

    pts_arr = np.array(raw_points, dtype=np.float32)

    # Filter out origin dummy vertices
    non_zero_mask = np.sum(np.abs(pts_arr), axis=1) > 0.001
    if np.any(non_zero_mask):
        pts_arr = pts_arr[non_zero_mask]

    # FULL STANDARD 20x20x20 METER VOLUME BOUNDING BOX
    p_min = np.min(pts_arr, axis=0)
    p_max = np.max(pts_arr, axis=0)

    center = (p_min + p_max) * 0.5
    dims = p_max - p_min
    max_dim = float(np.max(dims))
    if max_dim <= 0.0001:
        max_dim = 1.0

    # Scale model to standard 20m x 20m x 20m bounding volume
    scale_factor = scale_size / max_dim
    scaled_pts = (pts_arr - center) * scale_factor

    # Filter outer surface shell only
    outer_shell_pts = filter_outer_surface_shell_only(scaled_pts)
    total_pts = len(outer_shell_pts)

    if target_count <= 0:
        desired_count = calculate_smart_optimal_3d_drone_count(outer_shell_pts, scale_size)
    else:
        desired_count = target_count

    desired_count = min(desired_count, total_pts)

    # ENFORCE STRICT MINIMUM SEPARATION DISTANCE (1.35m) IN 20x20x20m VOLUME TO PREVENT CLUMPING!
    min_dist = max(1.35, 1.8 * math.sqrt(20.0 / float(desired_count)))
    min_dist_sq = min_dist * min_dist

    np.random.seed(42)
    indices = np.random.permutation(total_pts)

    accepted = []
    for idx in indices:
        if len(accepted) >= desired_count:
            break
        pt = outer_shell_pts[idx]
        pt_list = [float(pt[0]), float(pt[1]), float(pt[2])]
        too_close = False
        for acc in accepted:
            dx = pt_list[0] - acc[0]
            dy = pt_list[1] - acc[1]
            dz = pt_list[2] - acc[2]
            if (dx*dx + dy*dy + dz*dz) < min_dist_sq:
                too_close = True
                break
        if not too_close:
            accepted.append(pt_list)

    # Multi-pass fallbacks with strict 1.0m floor separation
    for fb_scale in [0.8, 0.6, 0.4]:
        if len(accepted) >= desired_count:
            break
        fb_dist = max(1.0, min_dist * fb_scale)
        fb_dist_sq = fb_dist * fb_dist
        for idx in indices:
            if len(accepted) >= desired_count:
                break
            pt = outer_shell_pts[idx]
            pt_list = [float(pt[0]), float(pt[1]), float(pt[2])]
            too_close = False
            for acc in accepted:
                dx = pt_list[0] - acc[0]
                dy = pt_list[1] - acc[1]
                dz = pt_list[2] - acc[2]
                if (dx*dx + dy*dy + dz*dz) < fb_dist_sq:
                    too_close = True
                    break
            if not too_close:
                accepted.append(pt_list)

    sampled_points = [{"x": round(p[0], 3), "y": round(p[1], 3), "z": round(p[2], 3)} for p in accepted]

    ext_name = os.path.splitext(os.path.basename(file_path))[0].upper()
    shape_type = f"3D Mesh ({ext_name})"

    result_data = {
        "success": True,
        "is_3d": True,
        "shape_type": shape_type,
        "drone_count": len(sampled_points),
        "scale_size": scale_size,
        "points": sampled_points
    }

    if output_json_path:
        with open(output_json_path, "w", encoding="utf-8") as f:
            json.dump(result_data, f, indent=2)
        print(f"Success: Standard 20x20x20m volume 3D formation ({len(sampled_points)} drones, min 1.35m separation) written to '{output_json_path}'.")

    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python shape3d_to_formation.py <file_path> [target_count] [output_json_path] [scale_size]")
        sys.exit(1)

    input_file = sys.argv[1]
    count_arg = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    out_json = sys.argv[3] if len(sys.argv) > 3 else "user_custom_3d_shape.json"
    scale_arg = float(sys.argv[4]) if len(sys.argv) > 4 else 20.0

    success = process_3d_shape(input_file, count_arg, out_json, scale_arg)
    sys.exit(0 if success else 1)
