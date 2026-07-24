Add-Type -AssemblyName System.Drawing

$srcPath = "C:\Users\USER\.gemini\antigravity-ide\brain\d298e65a-e49a-45ef-a096-bfad86f30c06\drone_logo_1784870909454.png"
$bmp = New-Object System.Drawing.Bitmap($srcPath)

for ($y = 0; $y -lt $bmp.Height; $y++) {
    for ($x = 0; $x -lt $bmp.Width; $x++) {
        $c = $bmp.GetPixel($x, $y)
        $maxC = [Math]::Max($c.R, [Math]::Max($c.G, $c.B))
        $minC = [Math]::Min($c.R, [Math]::Min($c.G, $c.B))
        $sat = $maxC - $minC
        
        # Checkerboard grid tiles are dark grays (maxC < 85 and saturation < 30)
        if ($maxC -lt 85 -and $sat -lt 30) {
            $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        } elseif ($maxC -lt 120 -and $sat -lt 35) {
            # Smooth anti-aliased edge transition for neon glow border
            $alpha = [int](([double]($maxC - 85) / 35.0) * 255.0)
            if ($alpha -lt 0) { $alpha = 0 }
            if ($alpha -gt 255) { $alpha = 255 }
            $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, $c.R, $c.G, $c.B))
        }
    }
}

$dest1 = "c:\Users\USER\Documents\Drone-Sim-Master\Godot-drone-master\icon.png"
$dest2 = "c:\Users\USER\Documents\Drone-Sim-Master\Godot-drone-master\assets\textures\drone_logo.png"

$bmp.Save($dest1, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Save($dest2, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "Successfully cleaned checkerboard background and saved transparent PNGs!"
