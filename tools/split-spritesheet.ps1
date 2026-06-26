# split-spritesheet.ps1
# Splits a NxN Pixellab spritesheet (tiles separated by 1px gaps) into individual PNGs.
#
# Usage:
#   .\split-spritesheet.ps1 -Source <path-to-spritesheet.png> -OutPrefix <env_tile_grass> -Cols 4 -Rows 4 -TileSize 64
#
# Example:
#   .\split-spritesheet.ps1 -Source "assets\art\tiles\pixellab-grass.png" -OutPrefix "env_tile_empty" -Cols 4 -Rows 4 -TileSize 64
#
# Output files are written next to the source image as <OutPrefix>_01.png, <OutPrefix>_02.png, ...

param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$OutPrefix,
    [int]$Cols     = 4,
    [int]$Rows     = 4,
    [int]$TileSize = 64,
    [int]$Gap      = 1
)

Add-Type -AssemblyName System.Drawing

$sourcePath = Resolve-Path $Source
$outDir     = Split-Path $sourcePath -Parent
$src        = [System.Drawing.Image]::FromFile($sourcePath)

Write-Host "Source:    $sourcePath ($($src.Width)x$($src.Height))"
Write-Host "Tile size: ${TileSize}px  Gap: ${Gap}px  Grid: ${Cols}x${Rows}"
$total = $Cols * $Rows
Write-Host "Output:    $outDir\${OutPrefix}_01.png ... ${OutPrefix}_$( '{0:D2}' -f $total ).png"
Write-Host ""

$n = 1
for ($row = 0; $row -lt $Rows; $row++) {
    for ($col = 0; $col -lt $Cols; $col++) {
        $srcX = $col * ($TileSize + $Gap)
        $srcY = $row * ($TileSize + $Gap)

        $bmp = New-Object System.Drawing.Bitmap($TileSize, $TileSize)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)

        $srcRect = New-Object System.Drawing.Rectangle($srcX, $srcY, $TileSize, $TileSize)
        $dstRect = New-Object System.Drawing.Rectangle(0,    0,      $TileSize, $TileSize)
        $g.DrawImage($src, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()

        $outName = '{0}_{1:D2}.png' -f $OutPrefix, $n
        $outPath = Join-Path $outDir $outName
        $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()

        Write-Host "  Saved $outName"
        $n++
    }
}

$src.Dispose()
Write-Host ""
Write-Host "Done - $($n - 1) tiles saved to $outDir"
