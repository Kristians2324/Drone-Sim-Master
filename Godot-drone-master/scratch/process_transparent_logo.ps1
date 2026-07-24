Add-Type -AssemblyName System.Drawing

$srcPath = "C:\Users\USER\.gemini\antigravity-ide\brain\d298e65a-e49a-45ef-a096-bfad86f30c06\drone_logo_1784870909454.png"
$srcImg = [System.Drawing.Image]::FromFile($srcPath)
$srcBmp = New-Object System.Drawing.Bitmap($srcImg)

$width = $srcBmp.Width
$height = $srcBmp.Height

# Create a new 32-bit ARGB bitmap for true transparency
$dstBmp = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

for ($y = 0; $y -lt $height; $y++) {
    for ($x = 0; $x -lt $width; $x++) {
        $c = $srcBmp.GetPixel($x, $y)
        $r = [int]$c.R
        $g = [int]$c.G
        $b = [int]$c.B
        
        $maxC = [Math]::Max($r, [Math]::Max($g, $b))
        $minC = [Math]::Min($r, [Math]::Min($g, $b))
        $chroma = $maxC - $minC
        
        # Determine if pixel belongs to neon cyan/yellow drone lines or glow
        # Cyan: high G & B, significantly higher than R
        $isCyan = ($g -gt 90 -and $b -gt 90 -and ($g - $r -gt 25 -or $b - $r -gt 25))
        # Yellow: high R & G, significantly higher than B
        $isYellow = ($r -gt 110 -and $g -gt 110 -and ($r - $b -gt 35 -or $g - $b -gt 35))
        # White highlight / core: very bright high intensity
        $isCore = ($r -gt 180 -and $g -gt 180 -and $b -gt 180)
        # Glow halo: moderate color intensity with color saturation
        $isGlow = ($maxC -gt 80 -and $chroma -gt 20)

        if ($isCyan -or $isYellow -or $isCore) {
            # Full opacity for drone body & lines
            $dstBmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $r, $g, $b))
        } elseif ($isGlow) {
            # Smooth semi-transparent alpha for neon glow around the drone
            $alpha = [int](([double]$chroma / 60.0) * 255.0)
            if ($alpha -lt 40) { $alpha = 40 }
            if ($alpha -gt 255) { $alpha = 255 }
            $dstBmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, $r, $g, $b))
        } else {
            # 100% TRANSPARENT for background
            $dstBmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        }
    }
}

$dest1 = "c:\Users\USER\Documents\Drone-Sim-Master\Godot-drone-master\icon.png"
$dest2 = "c:\Users\USER\Documents\Drone-Sim-Master\Godot-drone-master\assets\textures\drone_logo.png"

$dstBmp.Save($dest1, [System.Drawing.Imaging.ImageFormat]::Png)
$dstBmp.Save($dest2, [System.Drawing.Imaging.ImageFormat]::Png)

$dstBmp.Dispose()
$srcBmp.Dispose()
$srcImg.Dispose()

Write-Host "Processed transparent drone logo with ZERO background!"
