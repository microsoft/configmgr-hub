#This will force the client to update the client.
if (Get-ScheduledTask -TaskName "Configuration Manager Client Upgrade Task") {
     Get-ScheduledTask -TaskName "Configuration Manager Client Upgrade Task" | Start-ScheduledTask
} 
else {
    Start-Process -FilePath 'c:\windows\ccmsetup\ccmsetup.exe' -ArgumentList "/AutoUpgrade";
Start-Sleep -Seconds 30; schtasks /Run /TN "Microsoft\Configuration Manager\Configuration Manager Client Upgrade Task"
}
