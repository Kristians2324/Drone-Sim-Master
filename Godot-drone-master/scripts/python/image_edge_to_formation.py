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

    # 1. Background vs Subject Shape binary mask
    has_alpha = False
    binary = None

    if len(img_bgra.shape) == 3 and img_bgra.shape[2] == 4:
        alpha = img_bgra[:, :, 3]
        if np.min(alpha) < 200: # Transparent PNG background
            has_alpha = True
            _, binary = cv2.threshold(alpha, 30, 255, cv2.THRESH_BINARY)
            img_bgr = img_bgra[:, :, :3]
        else:
            img_bgr = img_bgra[:, :, :3]
    else:
        img_bgr = img_bgra

    if not has_alpha or binary is None:
        gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
        border_pixels = np.concatenate([gray[0, :], gray[h-1, :], gray[:, 0], gray[:, w-1]])
        bg_val = int(np.median(border_pixels))
        
        diff = cv2.absdiff(gray, bg_val)
        _, binary = cv2.threshold(diff, 18, 255, cv2.THRESH_BINARY)
        
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)

    # 2. Extract ONLY main external contour
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)

    if len(contours) == 0:
        gray_fb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray_fb, (5, 5), 0)
        canny = cv2.Canny(blurred, 40, 120)
        contours, _ = cv2.findContours(canny, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)

    if len(contours) == 0:
        print("Error: No outer contours found in image.")
        return False

    valid_contours = [c for c in contours if cv2.arcLength(c, True) > 40.0]
    if len(valid_contours) == 0:
        valid_contours = contours

    main_contour = max(valid_contours, key=cv2.contourArea)
    peri = float(cv2.arcLength(main_contour, True))

    # Check if shape is a Rectangle / Box
    approx = cv2.approxPolyDP(main_contour, 0.03 * peri, True)
    is_rectangle = (len(approx) == 4)

    shape_type = "Custom Outline"
    if is_rectangle:
        shape_type = "Rectangle / Box"
    elif len(approx) == 3:
        shape_type = "Triangle"
    elif len(approx) >= 5 and len(approx) <= 12:
        shape_type = "Polygon / Star"

    sampled_2d_pts = []

    if is_rectangle:
        # Bounding box calculation for perfect symmetrical 4-side distribution
        rect = cv2.minAreaRect(main_contour)
        box = cv2.boxPoints(rect)
        box = np.int32(box)
        
        # Sort corners: top-left, top-right, bottom-right, bottom-left
        pts_sum = box.sum(axis=1)
        top_left = box[np.argmin(pts_sum)]
        bot_right = box[np.argmax(pts_sum)]
        pts_diff = np.diff(box, axis=1)
        top_right = box[np.argmin(pts_diff)]
        bot_left = box[np.argmax(pts_diff)]

        side_w = float(np.linalg.norm(top_right - top_left))
        side_h = float(np.linalg.norm(bot_left - top_left))

        # Calculate exact optimal drones for top/bottom and left/right
        nh = max(5, int(round(side_w / 35.0))) if target_count <= 0 else max(3, int(round(target_count * (side_w / (side_w + side_h)) / 2.0)))
        nv = max(3, int(round(side_h / 35.0))) if target_count <= 0 else max(2, int(round(target_count * (side_h / (side_w + side_h)) / 2.0)))

        # 1. Top side (top-left to top-right)
        for i in range(nh):
            t = (i + 0.5) / float(nh)
            sampled_2d_pts.append(top_left + t * (top_right - top_left))

        # 2. Right side (top-right to bottom-right)
        for i in range(nv):
            t = (i + 0.5) / float(nv)
            sampled_2d_pts.append(top_right + t * (bot_right - top_right))

        # 3. Bottom side (bottom-right to bottom-left)
        for i in range(nh):
            t = (i + 0.5) / float(nh)
            sampled_2d_pts.append(bot_right + t * (bot_left - bot_right))

        # 4. Left side (bottom-left to top-left)
        for i in range(nv):
            t = (i + 0.5) / float(nv)
            sampled_2d_pts.append(bot_left + t * (top_left - bot_left))

    else:
        # General closed contour midpoint arc-length sampling
        if target_count <= 0:
            target_count = max(24, min(60, int(peri / 22.0)))

        contour_pts = main_contour[:, 0, :]
        num_pts = len(contour_pts)
        
        segment_lengths = [0.0]
        for i in range(num_pts):
            p1 = contour_pts[i]
            p2 = contour_pts[(i + 1) % num_pts]
            dist = float(np.linalg.norm(p2 - p1))
            segment_lengths.append(segment_lengths[-1] + dist)

        total_len = segment_lengths[-1]

        if total_len > 0.0:
            step_len = total_len / float(target_count)
            for k in range(target_count):
                target_dist = ((k + 0.5) * step_len) % total_len # Midpoint sampling
                idx = 0
                while idx < num_pts and segment_lengths[idx + 1] < target_dist:
                    idx += 1
                if idx >= num_pts:
                    idx = num_pts - 1
                    
                seg_start_dist = segment_lengths[idx]
                seg_end_dist = segment_lengths[idx + 1]
                seg_len = seg_end_dist - seg_start_dist
                
                t = (target_dist - seg_start_dist) / max(seg_len, 1e-5)
                p1 = contour_pts[idx]
                p2 = contour_pts[(idx + 1) % num_pts]
                interpolated_pt = p1 + t * (p2 - p1)
                sampled_2d_pts.append(interpolated_pt)

    # Convert 2D pixel coordinates to centered 3D world coordinates
    max_dim = float(max(w, h))
    pts_3d = []

    for pt in sampled_2d_pts:
        px, py = float(pt[0]), float(pt[1])
        
        ix, iy = int(clampf(px, 0, w - 1)), int(clampf(py, 0, h - 1))
        b, g, r = img_bgr[iy, ix]

        norm_x = (px - (w / 2.0)) / max_dim
        norm_y = ((h / 2.0) - py) / max_dim

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
        print(f"Successfully processed {shape_type}: {len(pts_3d)} drones forming clean perimeter -> '{output_json_path}'")

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
