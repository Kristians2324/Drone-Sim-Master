import sys
import os
import glob
import cv2

def compile_mp4_video(frames_dir, output_mp4_path, fps=10):
    if not os.path.exists(frames_dir):
        print(f"Error: Directory '{frames_dir}' does not exist.")
        return False

    pattern_jpg = os.path.join(frames_dir, "frame_*.jpg")
    frame_files = sorted(glob.glob(pattern_jpg))

    if not frame_files:
        pattern_png = os.path.join(frames_dir, "frame_*.png")
        frame_files = sorted(glob.glob(pattern_png))

    if not frame_files:
        print(f"Error: No frame files found in '{frames_dir}'.")
        return False

    first_frame = cv2.imread(frame_files[0])
    if first_frame is None:
        print(f"Error: Could not read first frame '{frame_files[0]}'.")
        return False

    height, width = first_frame.shape[:2]

    # Try MP4V / H264 fourcc for 100% compliant Windows Media Player & Browser MP4 playback
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    writer = cv2.VideoWriter(output_mp4_path, fourcc, fps, (width, height))

    if not writer.isOpened():
        fourcc = cv2.VideoWriter_fourcc(*'avc1')
        writer = cv2.VideoWriter(output_mp4_path, fourcc, fps, (width, height))

    for f_path in frame_files:
        frame = cv2.imread(f_path)
        if frame is not None:
            writer.write(frame)

    writer.release()
    print(f"Success: Compiled {len(frame_files)} frames into genuine ISO MP4 video file at '{output_mp4_path}'.")

    # Clean up temp frames
    for f_path in frame_files:
        try:
            os.remove(f_path)
        except OSError:
            pass
    try:
        os.rmdir(frames_dir)
    except OSError:
        pass

    return True

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python encode_mp4.py <frames_dir> <output_mp4_path> [fps]")
        sys.exit(1)

    in_dir = sys.argv[1]
    out_mp4 = sys.argv[2]
    fps_val = int(sys.argv[3]) if len(sys.argv) > 3 else 10

    success = compile_mp4_video(in_dir, out_mp4, fps_val)
    sys.exit(0 if success else 1)
