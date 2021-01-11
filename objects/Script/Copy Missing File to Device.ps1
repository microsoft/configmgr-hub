<#
.SYNOPSIS
    Copy missing file to device
.DESCRIPTION
    Copy missing file to device
.INPUTS
    MissingFileFullPath
.NOTES
    Author:     Adam Gross
    Website:    https://www.ASquareDozen.com
    GitHub:     https://www.github.com/AdamGrossTX
    Twitter:    https://www.twitter.com/AdamGrossTX
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$MissingFileFullPath,

    [Parameter(Mandatory=$true)]
    [string]$SourceFileFullPath,
    
    [Parameter(Mandatory=$true)]
    [string]$OverwriteExisting
)

try {
    if($OverwriteExisting -eq "True" -or !(Test-Path $MissingFileFullPath -ErrorAction SilentlyContinue)) {
        Copy-Item -Path $SourceFileFullPath -Destination $MissingFileFullPath -Force
    }
}
catch {
    throw $_
}