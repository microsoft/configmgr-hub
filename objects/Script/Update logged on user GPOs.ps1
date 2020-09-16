# Scirpt to update User GPO from System context using a Schedule Task
# Written by Jörgen Nilsson
# ccmexec.com

# Creates a local vbscript, which will run GPUpdate without displaying anything for the end user
$VBScript = @"
Set objShell = WScript.CreateObject("WScript.Shell")
Result = objShell.Run ("cmd /c echo n | gpupdate /target:user /force",0,true)
Wscript.quit(Result)
"@
 
$VBScript | Out-File -FilePath "$env:Windir\RunUserGPO.vbs" -Force 

# Gets the logged on user
$computer = $env:COMPUTERNAME
$computerSystem = Get-WMIObject -class Win32_ComputerSystem -ComputerName $computer
$LoggedUser = $computerSystem.UserName
If ($LoggedUser -eq $null) {
    Write-output "No user logged on"
    Exit 1
}
# Creates and run a Schedule Task as the logged on user
$TaskName= "GPupdateUser"
$Action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "$env:Windir\RunUserGPO.vbs /NoLogo"
$Principal = New-ScheduledTaskPrincipal "$loggedUser"
$Settings = New-ScheduledTaskSettingsSet
 
$Task = New-ScheduledTask -Action $Action -Principal $Principal -Settings $Settings
Register-ScheduledTask $TaskName -InputObject $Task | out-null
Start-ScheduledTask $TaskName | out-null

# Wait for Schedule task to complete 
$Counter = 200 # 40 s
while ((Get-ScheduledTask -TaskName $TaskName).State -ne 'Ready' -and $Counter-- -gt 0) {
    Start-Sleep -Milliseconds 200
}

if ($Counter -lt 0) {
    Write-Output "Timeout waiting for Scheduled Task"
    exit 1
}

# Verify Result
$St = Get-ScheduledTask -TaskName $TaskName
$Result = (Get-ScheduledTaskInfo -InputObject $St).LastTaskResult
if ($Result -eq 0) {
    Write-Output "Completed Succesfully"
}
else {
     Write-Output "Error running Schedule task, error code = $('0x{0:x}' -f $Result)"
}

# Cleaning up 
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Remove-Item -Path "$env:Windir\RunUserGPO.vbs" -Force