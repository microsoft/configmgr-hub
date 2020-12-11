#Copy missing file to device
#Adam Gross
#https://www.ASquareDozen.com

param(
    $MissingFileFullPath,
    $SourceFileFullPath,
    [bool]$OverwriteExisting
)

try {
    if($OverwriteExisting -or !(Test-Path $MissingFileFullPath -ErrorAction SilentlyContinue)) {
        Copy-Item -Path $SourceFileFullPath -Destination $MissingFileFullPath -Force
    }
}
catch {
    throw $_
}