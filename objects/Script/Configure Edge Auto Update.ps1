param
(
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Beta", "Dev", "Stable")]
    [string]$ChannelID,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("True", "False")]
    [string]$DoAutoUpdate
)

[string]$ChannelGuid
# Check Channel
switch($ChannelID)
{
    "Stable" {$ChannelGuid = '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'; break}
    "Dev" {$ChannelGuid = '{0D50BFEC-CD6A-4F9A-964C-C7416E3ACB10}'; break}
    "Beta" {$ChannelGuid = '{2CD8A007-E189-409D-A2C8-9AF4EF3C72AA}'; break}
}

[int]$AutoUpdate
# See if autoupdate is false
switch($DoAutoUpdate)
{
    "False" {$AutoUpdate = 0; break}
    "True" {$AutoUpdate = 1; break}
}

# Registry value name is in the format "Update<{ChannelID}> where ChannelID is the GUID
Set-Variable -Name "AutoUpdateValueName" -Value "Update$ChannelGuid" -Option Constant
Set-Variable -Name "RegistryPath" -Value "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" -Option Constant

# Test if the registry key exists. If it doesn't, create it
$EdgeUpdateRegKeyExists = Test-Path -Path $RegistryPath

if (!$EdgeUpdateRegKeyExists)
{
    New-Item -Path $RegistryPath
}

# See if the autoupdate value exists
Set-ItemProperty -Path $RegistryPath -Name $AutoUpdateValueName -Value $AutoUpdate

$AutoupdateValue = (Get-ItemProperty -Path $RegistryPath -Name $AutoUpdateValueName).$AutoUpdateValueName

# If the value is not equal to $AutoUpdate, auto update is not turned off, this is a failure
if ($AutoupdateValue -ne $AutoUpdate)
{
    Write-Host "Autoupdate value set incorrectly"
    return -1
}