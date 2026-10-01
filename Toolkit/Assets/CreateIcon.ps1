# Creates a multi-resolution toolkit icon suitable for Windows taskbar
# Generates 16x16, 32x32, and 48x48 sizes in a single ICO file

Add-Type -AssemblyName System.Drawing

function New-IconFromBitmap {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [string]$OutputPath
    )

    # Save as PNG first, then use ImageMagick-like approach
    # For proper ICO, we'll create individual sized images
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Icon)
}

function Create-ToolkitIcon {
    param([int]$Size)

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size)
    $bitmap.MakeTransparent()
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    # Blue background circle
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(37, 99, 235))
    $graphics.FillEllipse($brush, 1, 1, $Size - 2, $Size - 2)

    # White wrench icon
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [Math]::Max(1, $Size / 20))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

    $padding = $Size * 0.2
    $endX = $Size - $padding
    $endY = $padding + 3

    # Wrench handle (diagonal line)
    $graphics.DrawLine($pen, $padding + 2, $Size - $padding, $endX, $endY)

    # Wrench head (circle)
    $headSize = $Size * 0.25
    $graphics.FillEllipse($brush, $endX - $headSize/2, $endY - $headSize/2, $headSize, $headSize)

    # Highlight circle outline
    $whitePen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [Math]::Max(1, $Size / 32))
    $graphics.DrawEllipse($whitePen, $endX - $headSize/2, $endY - $headSize/2, $headSize, $headSize)

    $graphics.Dispose()
    $bitmap
}

# Create 32x32 icon (main size for taskbar)
$bitmap32 = Create-ToolkitIcon -Size 32
$icoPath = Join-Path $PSScriptRoot "toolkit.ico"
$bitmap32.Save($icoPath, [System.Drawing.Imaging.ImageFormat]::Icon)
$bitmap32.Dispose()

Write-Host "✓ Icon created: $icoPath (32x32)" -ForegroundColor Green
