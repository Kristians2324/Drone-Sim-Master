import sys
import os
import json
import math
import numpy as np
import cv2

def clampf(val, min_v, max_v):
    return max(min_v, min(max_v, val))

def process_image(image_path, target_count=0, output_json_path=None, scale_size=28.0, simplify_level=0.0):
    if not os.path.exists(image_path):
        print(f"Error: Image '{image_path}' does not exist.")
        return False

    img_bgr = cv2.imread(image_path)
    if img_bgr is None:
        print(f"Error: Failed to read image '{image_path}'.")
        return False

    h, w = img_bgr.shape[:2]

    # --- 1. PREPROCESSING & EDGE ENHANCEMENT ---
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)

    high_thresh, _ = cv2.threshold(blur, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    low_thresh = max(10.0, high_thresh * 0.4)
    edges = cv2.Canny(blur, low_thresh, high_thresh)

    kernel = np.ones((3, 3), np.uint8)
    dilated_edges = cv2.dilate(edges, kernel, iterations=1)

    # --- 2. CONTOUR EXTRACTION ---
    contours, _ = cv2.findContours(dilated_edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)

    if not contours or len(contours) == 0:
        _, mask = cv2.threshold(blur, 128, 255, cv2.THRESH_BINARY_INV)
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)

    if not contours or len(contours) == 0:
        print("Error: No valid contours found in image.")
        return False

    perimeters = [cv2.arcLength(c, True) for c in contours]
    max_peri = max(perimeters)
    
    valid_contours = []
    for c, peri in zip(contours, perimeters):
        if peri >= max(15.0, max_peri * 0.02):
            valid_contours.append(c)

    if len(valid_contours) == 0:
        valid_contours = [contours[np.argmax(perimeters)]]

    valid_contours = sorted(valid_contours, key=lambda c: cv2.arcLength(c, True), reverse=True)
    top_contours = valid_contours

    simplified_contours = []
    for c in top_contours:
        if simplify_level > 0.0:
            c_peri = cv2.arcLength(c, True)
            epsilon = simplify_level * c_peri
            approx = cv2.approxPolyDP(c, epsilon, True)
            if len(approx) >= 4:
                simplified_contours.append(approx)
            else:
                simplified_contours.append(c)
        else:
            simplified_contours.append(c)

    if target_count <= 0:
        target_count = 150

    # --- 3. ARC-LENGTH POINT ALLOCATION & UNIFIED SILHOUETTE ---
    sampled_2d_pts = []
    remaining_drones = target_count

    main_contour = simplified_contours[0]
    sub_contours = simplified_contours[1:]

    main_drones = max(30, int(round(target_count * 0.75))) if len(sub_contours) > 0 else target_count
    remaining_drones -= main_drones

    # Sample main outer silhouette contour
    main_pts = main_contour[:, 0, :]
    num_m = len(main_pts)
    m_seg_lens = [0.0]
    for i in range(num_m):
        p1 = main_pts[i]
        p2 = main_pts[(i + 1) % num_m]
        m_seg_lens.append(m_seg_lens[-1] + float(np.linalg.norm(p2 - p1)))
    m_total_len = m_seg_lens[-1]

    step_len = m_total_len / float(main_drones)
    for k in range(main_drones):
        target_dist = ((k + 0.5) * step_len) % m_total_len
        idx = 0
        while idx < num_m and m_seg_lens[idx + 1] < target_dist:
            idx += 1
        if idx >= num_m: idx = num_m - 1
        seg_len = m_seg_lens[idx + 1] - m_seg_lens[idx]
        t = (target_dist - m_seg_lens[idx]) / max(seg_len, 1e-5)
        p1 = main_pts[idx]
        p2 = main_pts[(idx + 1) % num_m]
        sampled_2d_pts.append(p1 + t * (p2 - p1))

    # Sample major sub-features (wheels/windows)
    if len(sub_contours) > 0 and remaining_drones > 0:
        sub_total_peri = sum(cv2.arcLength(c, True) for c in sub_contours)
        for c_idx, sc in enumerate(sub_contours):
            sc_peri = cv2.arcLength(sc, True)
            if c_idx == len(sub_contours) - 1:
                c_drones = max(1, remaining_drones)
            else:
                c_drones = max(1, int(round(remaining_drones * (sc_peri / max(sub_total_peri, 1e-5)))))
            remaining_drones -= c_drones

            sc_pts = sc[:, 0, :]
            num_sc = len(sc_pts)
            sc_seg_lens = [0.0]
            for i in range(num_sc):
                p1 = sc_pts[i]
                p2 = sc_pts[(i + 1) % num_sc]
                sc_seg_lens.append(sc_seg_lens[-1] + float(np.linalg.norm(p2 - p1)))
            sc_total_len = sc_seg_lens[-1]

            sc_step = sc_total_len / float(max(1, c_drones))
            for k in range(c_drones):
                target_dist = ((k + 0.5) * sc_step) % sc_total_len
                idx = 0
                while idx < num_sc and sc_seg_lens[idx + 1] < target_dist:
                    idx += 1
                if idx >= num_sc: idx = num_sc - 1
                seg_len = sc_seg_lens[idx + 1] - sc_seg_lens[idx]
                t = (target_dist - sc_seg_lens[idx]) / max(seg_len, 1e-5)
                p1 = sc_pts[idx]
                p2 = sc_pts[(idx + 1) % num_sc]
                sampled_2d_pts.append(p1 + t * (p2 - p1))

    # --- 4. SUBJECT BOUNDING BOX CENTERING & SCALING ---
    xs = [float(pt[0]) for pt in sampled_2d_pts]
    ys = [float(pt[1]) for pt in sampled_2d_pts]

    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    subj_w = max(xs) - min(xs)
    subj_h = max(ys) - min(ys)
    subj_max_dim = float(max(subj_w, subj_h))
    if subj_max_dim <= 0.0001:
        subj_max_dim = 1.0

    scale_factor = scale_size / subj_max_dim

    pts_3d = []
    for pt in sampled_2d_pts:
        px, py = float(pt[0]), float(pt[1])

        ix, iy = int(clampf(px, 0, w - 1)), int(clampf(py, 0, h - 1))
        b, g, r = img_bgr[iy, ix]

        world_x = (px - cx) * scale_factor
        world_y = (cy - py) * scale_factor
        world_z = 0.0

        pts_3d.append({
            "x": round(world_x, 3),
            "y": round(world_y, 3),
            "z": round(world_z, 3),
            "r": round(float(r) / 255.0, 3),
            "g": round(float(g) / 255.0, 3),
            "b": round(float(b) / 255.0, 3)
        })

    ext_name = os.path.splitext(os.path.basename(image_path))[0].upper()
    shape_type = f"Simplified Contour ({ext_name})"

    result_data = {
        "success": True,
        "is_3d": False,
        "shape_type": shape_type,
        "drone_count": len(pts_3d),
        "scale_size": scale_size,
        "points": pts_3d
    }

    if output_json_path:
        with open(output_json_path, "w", encoding="utf-8") as f:
            json.dump(result_data, f, indent=2)
        print(f"Success: Wrote simplified image shape formation ({len(pts_3d)} drones) to '{output_json_path}'.")

    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python image_edge_to_formation.py <image_path> [target_count] [output_json_path] [scale_size]")
        sys.exit(1)

    input_img = sys.argv[1]
    count_arg = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    out_json = sys.argv[3] if len(sys.argv) > 3 else "user_custom_shape.json"
    scale_arg = float(sys.argv[4]) if len(sys.argv) > 4 else 28.0

    success = process_image(input_img, count_arg, out_json, scale_arg)
    sys.exit(0 if success else 1)
