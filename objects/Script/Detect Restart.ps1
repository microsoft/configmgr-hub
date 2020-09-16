# Show Machine restart time by Matthew Hudson, MVP
Function Check-Registry ($Regkey,$Regvalue)
{
$Foundit = Get-ItemProperty $Regkey $Regvalue -ErrorAction SilentlyContinue 
if (($Foundit -eq $null) -or ($Foundit.Length -eq 0))
        {
             Exit           
        }
        
}


Check-Registry ("HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData","RebootBy")

$UTCEPOCH = Get-ItemPropertyValue -path "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData" -name RebootBy



$REstartseconds =  (Get-CimInstance -Namespace root\ccm\policy\machine\requestedconfig -ClassName CCM_RebootSettings).RebootCountdown

If ((Get-TimeZone).SupportsDaylightSavingTime) {$TOffset=3600}
$newTime = $UTCEPOCH + (Get-TimeZone).BaseUTCOffset.totalSeconds+ $TOffset + $REstartseconds

$UTCTime = (Get-Date 01.01.1970)+([System.TimeSpan]::fromseconds($newTime))
"$UTCTime UTC" 

$ClientLocaltime =  [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date 01.01.1970)+([System.TimeSpan]::fromseconds($newTime)), (Get-TimeZone))
"$ClientLocaltime Client Local time "  