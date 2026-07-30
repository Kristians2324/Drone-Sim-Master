import sys
import os
import json
import math
import cv2
import numpy as np

def process_image_to_drone_formation(image_path, target_count=0, output_json_path=None, scale_size=28.0):
    if not os.path.exists(image_path):
        print(f"Error: Image path '{image_path}' does not exist.")
        return False

    img_bgra = cv2.imread(image_path, cv2.IMREAD_UNCHANGED)
    if img_bgra is None:
        print(f"Error: Could not load image from '{image_path}'.")
        return False

    h, w = img_bgra.shape[:2]

    # --- 1. UNIVERSAL MULTI-STRATEGY IMAGE SEGMENTATION ---
    has_alpha = False
    binary_mask = None

    # Strategy A: Alpha Channel (for transparent PNGs/WebPs)
    if len(img_bgra.shape) == 3 and img_bgra.shape[2] == 4:
        alpha = img_bgra[:, :, 3]
        if np.min(alpha) < 220:
            has_alpha = True
            _, binary_mask = cv2.threshold(alpha, 25, 255, cv2.THRESH_BINARY)
            img_bgr = img_bgra[:, :, :3]
        else:
            img_bgr = img_bgra[:, :, :3]
    else:
        img_bgr = img_bgra

    # Strategy B: Color Distance + Adaptive Border Sampling (for opaque JPGs/PNGs)
    if not has_alpha or binary_mask is None:
        # Sample border pixels around all 4 edges to detect background color
        border_pixels = np.concatenate([img_bgr[0, :, :], img_bgr[h-1, :, :], img_bgr[:, 0, :], img_bgr[:, w-1, :]])
        bg_color = np.median(border_pixels, axis=0)

        # 3-channel Euclidean color distance from background color
        color_diff = np.linalg.norm(img_bgr.astype(np.float32) - bg_color, axis=2)
        _, binary_mask = cv2.threshold(color_diff.astype(np.uint8), 18, 255, cv2.THRESH_BINARY)

        # Micro 2x2 kernel to preserve narrow wing/body gaps and fine organic details
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2, 2))
        binary_mask = cv2.morphologyEx(binary_mask, cv2.MORPH_CLOSE, kernel)

    # Strategy C: Multi-scale Canny Fallback if mask is empty
    contours, _ = cv2.findContours(binary_mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    if len(contours) == 0:
        gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(gray)
        blurred = cv2.GaussianBlur(enhanced, (3, 3), 0)
        canny = cv2.Canny(blurred, 30, 110)
        contours, _ = cv2.findContours(canny, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)

    if len(contours) == 0:
        print("Error: No valid outer contours found in image.")
        return False

    # --- 2. MULTI-CONTOUR & FEATURE ANALYSIS ---
    # Filter tiny noise contours (perimeter > 25px) and sort by length
    valid_contours = [c for c in contours if cv2.arcLength(c, True) > 25.0]
    if len(valid_contours) == 0:
        valid_contours = contours

    valid_contours = sorted(valid_contours, key=lambda c: cv2.arcLength(c, True), reverse=True)
    total_valid_peri = sum(cv2.arcLength(c, True) for c in valid_contours)

    significant_contours = []
    accum_peri = 0.0
    for c in valid_contours:
        c_len = cv2.arcLength(c, True)
        if c_len < 30.0 and len(significant_contours) > 0:
            continue
        significant_contours.append(c)
        accum_peri += c_len
        if accum_peri >= total_valid_peri * 0.95 or len(significant_contours) >= 20:
            break

    if len(significant_contours) == 0:
        significant_contours = [valid_contours[0]]

    total_perimeter = sum(cv2.arcLength(c, True) for c in significant_contours)
    main_contour = significant_contours[0]

    # Shape type & corner detection
    approx_corners = cv2.approxPolyDP(main_contour, 0.005 * total_perimeter, True)
    num_corners = len(approx_corners)
    is_rectangle = (len(significant_contours) == 1 and len(cv2.approxPolyDP(main_contour, 0.03 * total_perimeter, True)) == 4)

    shape_type = "Universal Object / Logo"
    if is_rectangle:
        shape_type = "Rectangle / Box"
    elif num_corners == 3:
        shape_type = "Triangle"
    elif num_corners >= 5 and num_corners <= 12:
        shape_type = "Polygon / Star"
    elif len(significant_contours) > 1:
        shape_type = f"Multi-Part / Detailed Shape ({len(significant_contours)} contours)"

    # --- 3. DYNAMIC DRONE COUNT SCALING ---
    max_dim = float(max(w, h))
    norm_total_perimeter = total_perimeter / max_dim
    total_corners = sum(len(cv2.approxPolyDP(c, 0.005 * cv2.arcLength(c, True), True)) for c in significant_contours)
    num_contours = len(significant_contours)

    if target_count <= 0:
        if is_rectangle:
            target_count = 80
        else:
            # High-density auto-detection based on normalized perimeter, corner complexity & contour count
            base_count = norm_total_perimeter * 42.0
            corner_bonus = min(100.0, total_corners * 2.5)
            contour_bonus = min(120.0, (num_contours - 1) * 25.0)
            target_count = max(80, min(450, int(round(base_count + corner_bonus + contour_bonus))))

    sampled_2d_pts = []

    # --- 4. POINT SAMPLING ENGINE ---
    if is_rectangle:
        # Symmetrical 4-side distribution for rectangles
        rect = cv2.minAreaRect(main_contour)
        box = cv2.boxPoints(rect)
        box = np.int32(box)
        
        pts_sum = box.sum(axis=1)
        top_left = box[np.argmin(pts_sum)]
        bot_right = box[np.argmax(pts_sum)]
        pts_diff = np.diff(box, axis=1)
        top_right = box[np.argmin(pts_diff)]
        bot_left = box[np.argmax(pts_diff)]

        side_w = float(np.linalg.norm(top_right - top_left))
        side_h = float(np.linalg.norm(bot_left - top_left))

        nh = max(6, int(round(target_count * (side_w / (side_w + side_h)) / 2.0)))
        nv = max(3, int(round(target_count * (side_h / (side_w + side_h)) / 2.0)))

        for i in range(nh):
            t = (i + 0.5) / float(nh)
            sampled_2d_pts.append(top_left + t * (top_right - top_left))
        for i in range(nv):
            t = (i + 0.5) / float(nv)
            sampled_2d_pts.append(top_right + t * (bot_right - top_right))
        for i in range(nh):
            t = (i + 0.5) / float(nh)
            sampled_2d_pts.append(bot_right + t * (bot_left - bot_right))
        for i in range(nv):
            t = (i + 0.5) / float(nv)
            sampled_2d_pts.append(bot_left + t * (top_left - bot_left))

    else:
        # Multi-Contour Arc-Length Point Allocation
        remaining_drones = target_count
        for c_idx, contour in enumerate(significant_contours):
            c_peri = float(cv2.arcLength(contour, True))
            if c_peri <= 0:
                continue

            if c_idx == len(significant_contours) - 1:
                c_drones = max(1, remaining_drones)
            else:
                c_drones = max(1, int(round(target_count * (c_peri / max(total_perimeter, 1e-5)))))
                c_drones = min(c_drones, remaining_drones - (len(significant_contours) - 1 - c_idx))

            remaining_drones -= c_drones

            contour_pts = contour[:, 0, :]
            num_contour = len(contour_pts)

            segment_lengths = [0.0]
            for i in range(num_contour):
                p1 = contour_pts[i]
                p2 = contour_pts[(i + 1) % num_contour]
                segment_lengths.append(segment_lengths[-1] + float(np.linalg.norm(p2 - p1)))
            seg_total_len = segment_lengths[-1]
            step_len = seg_total_len / float(c_drones)
            for k in range(c_drones):
                target_dist = ((k + 0.5) * step_len) % seg_total_len
                idx = 0
                while idx < num_contour and segment_lengths[idx + 1] < target_dist:
                    idx += 1
                if idx >= num_contour: idx = num_contour - 1
                seg_len = segment_lengths[idx + 1] - segment_lengths[idx]
                t = (target_dist - segment_lengths[idx]) / max(seg_len, 1e-5)
                p1 = contour_pts[idx]
                p2 = contour_pts[(idx + 1) % num_contour]
                sampled_2d_pts.append(p1 + t * (p2 - p1))

    # --- 5. 3D CENTERING & ASPECT RATIO CONVERSION ---
    max_dim = float(max(w, h))
    pts_3d = []

    for pt in sampled_2d_pts:
        px, py = float(pt[0]), float(pt[1])
        
        ix, iy = int(clampf(px, 0, w - 1)), int(clampf(py, 0, h - 1))
        b, g, r = img_bgr[iy, ix]

        norm_x = (px - (w / 2.0)) / max_dim
        norm_y = ((h / 2.0) - py) / max_dim # Invert Y for 3D altitude

        world_x = norm_x * scale_size
        world_y = norm_y * scale_size
        world_z = 0.0

        pts_3d.append({
            "x": round(world_x, 3),
            "y": round(world_y, 3),
            "z": round(world_z, 3),
            "r": round(float(r) / 255.0, 3),
            "g": round(float(g) / 255.0, 3),
            "b": round(float(b) / 255.0, 3)
        })

    result_data = {
        "image_path": image_path,
        "shape_type": shape_type,
        "drone_count": len(pts_3d),
        "scale_size": scale_size,
        "points": pts_3d
    }

    if output_json_path:
        os.makedirs(os.path.dirname(os.path.abspath(output_json_path)), exist_ok=True)
        with open(output_json_path, "w") as f:
            json.dump(result_data, f, indent=2)
        print(f"Successfully processed {shape_type}: {len(pts_3d)} universal drones -> '{output_json_path}'")

    return True

def clampf(v, min_v, max_v):
    return max(min_v, min(max_v, v))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python image_edge_to_formation.py <image_path> [target_count] [output_json_path] [scale_size]")
        sys.exit(1)

    img_p = sys.argv[1]
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    out_p = sys.argv[3] if len(sys.argv) > 3 else "user://custom_image_formation.json"
    scale = float(sys.argv[4]) if len(sys.argv) > 4 else 28.0

    success = process_image_to_drone_formation(img_p, count, out_p, scale)
    sys.exit(0 if success else 1)
