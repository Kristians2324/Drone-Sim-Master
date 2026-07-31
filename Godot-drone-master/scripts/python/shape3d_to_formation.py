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

def process_3d_shape(file_path, target_count=0, output_json_path=None, scale_size=28.0):
    if not os.path.exists(file_path):
        print(f"Error: File '{file_path}' does not exist.")
        return False

    raw_points = parse_3d_file(file_path)
    if not raw_points or len(raw_points) == 0:
        print(f"Error: No valid 3D points extracted from '{file_path}'.")
        return False

    pts_arr = np.array(raw_points, dtype=np.float32)

    # Filter out origin dummy vertices (0,0,0)
    non_zero_mask = np.sum(np.abs(pts_arr), axis=1) > 0.001
    if np.any(non_zero_mask):
        pts_arr = pts_arr[non_zero_mask]

    # Full 360-degree 3D bounding box
    p_min = np.min(pts_arr, axis=0)
    p_max = np.max(pts_arr, axis=0)

    center = (p_min + p_max) * 0.5
    dims = p_max - p_min
    max_dim = float(np.max(dims))
    if max_dim <= 0.0001:
        max_dim = 1.0

    scale_factor = scale_size / max_dim
    scaled_pts = (pts_arr - center) * scale_factor
    total_pts = len(scaled_pts)

    desired_count = target_count if target_count > 0 else 150
    desired_count = min(desired_count, total_pts)

    # Spatial shuffle candidates to eliminate OBJ sequential line/mesh group bias
    np.random.seed(42)
    shuffled_pts = scaled_pts.copy()
    np.random.shuffle(shuffled_pts)

    # STAGE 1: FORM THE ENTIRE OVERALL 3D SHAPE FIRST (First 65% of drones, wide spatial spacing)
    stage1_target = max(10, int(round(desired_count * 0.65)))
    stage1_min_dist = max(0.6, 2.0 * math.sqrt(25.0 / float(desired_count)))
    stage1_min_dist_sq = stage1_min_dist * stage1_min_dist

    accepted = []
    for pt in shuffled_pts:
        if len(accepted) >= stage1_target:
            break
        pt_list = [float(pt[0]), float(pt[1]), float(pt[2])]
        too_close = False
        for acc in accepted:
            dx = pt_list[0] - acc[0]
            dy = pt_list[1] - acc[1]
            dz = pt_list[2] - acc[2]
            if (dx*dx + dy*dy + dz*dz) < stage1_min_dist_sq:
                too_close = True
                break
        if not too_close:
            accepted.append(pt_list)

    # STAGE 2: FILL LARGEST GAPS WITH REMAINING DRONES (Farthest Point Sampling)
    remaining_needed = desired_count - len(accepted)
    if remaining_needed > 0 and len(shuffled_pts) > len(accepted):
        sample_pool_size = min(len(shuffled_pts), desired_count * 10)
        pool = shuffled_pts[:sample_pool_size]

        for _ in range(remaining_needed):
            best_cand = None
            best_max_dist = -1.0

            for cand in pool:
                cand_list = [float(cand[0]), float(cand[1]), float(cand[2])]
                min_d_sq = 999999.0
                for acc in accepted:
                    dx = cand_list[0] - acc[0]
                    dy = cand_list[1] - acc[1]
                    dz = cand_list[2] - acc[2]
                    d_sq = dx*dx + dy*dy + dz*dz
                    if d_sq < min_d_sq:
                        min_d_sq = d_sq

                if min_d_sq > best_max_dist and min_d_sq > 0.04:
                    best_max_dist = min_d_sq
                    best_cand = cand_list

            if best_cand is not None:
                accepted.append(best_cand)
            else:
                break

    # Final fallback if needed to reach exact desired count
    if len(accepted) < desired_count:
        for cand in shuffled_pts:
            if len(accepted) >= desired_count:
                break
            cand_list = [float(cand[0]), float(cand[1]), float(cand[2])]
            too_close = False
            for acc in accepted:
                dx = cand_list[0] - acc[0]
                dy = cand_list[1] - acc[1]
                dz = cand_list[2] - acc[2]
                if (dx*dx + dy*dy + dz*dz) < 0.04:
                    too_close = True
                    break
            if not too_close:
                accepted.append(cand_list)

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
        print(f"Success: Wrote 2-stage 3D shape formation ({len(sampled_points)} drones) to '{output_json_path}'.")

    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python shape3d_to_formation.py <file_path> [target_count] [output_json_path] [scale_size]")
        sys.exit(1)

    input_file = sys.argv[1]
    count_arg = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    out_json = sys.argv[3] if len(sys.argv) > 3 else "user_custom_3d_shape.json"
    scale_arg = float(sys.argv[4]) if len(sys.argv) > 4 else 28.0

    success = process_3d_shape(input_file, count_arg, out_json, scale_arg)
    sys.exit(0 if success else 1)
