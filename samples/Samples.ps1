
# Sample usage, run CommonFunctions.ps1 first to import the functions

# Create collection and add one direct member
$collection = New-CMCollection -Name "Test Collection 1"
$device = (Get-CMDevice)[0]
Add-CMCollectionMember -CollectionID $collection.CollectionID -ResourceID $device.MachineId -RuleName "Direct member $($device.Name)"

# Invoke app install remotely for a device-available application already deployed to the client (for this one client must know about this app)
$deviceName = "MyDevice"
$applicationName = "My Application"
$device = Get-CMDevice | Where-Object {$_.Name -eq $deviceName}
$application = Get-CMApplication | Where-Object {$_.DisplayName -eq $applicationName}
Invoke-CMApplicationInstall -CIGUID $application.CIGUID -SMSID $device.SMSID

# Invoke app uninstall remotely for a device-available application already deployed to the client (for this one client must know about this app)
$deviceName = "MyDevice"
$applicationName = "My Application"
$device = Get-CMDevice | Where-Object {$_.Name -eq $deviceName}
$application = Get-CMApplication | Where-Object {$_.DisplayName -eq $applicationName}
Invoke-CMApplicationUninstall -CIGUID $application.CIGUID -SMSID $device.SMSID

# Invoke on-demand app install - create a suspended deployment ("require approval" flag selected) to a device collection. Such deployment stays on the server and the API below triggers installation for that app/device only. 
# Note: the action is similar to CreateApprovedRequest method in SMS_ApplicationRequest WMI class and is available as of CM2103 release. 
$deviceName = "MyDevice"
$applicationName = "My Application"
$device = Get-CMDevice | Where-Object {$_.Name -eq $deviceName}
$application = Get-CMApplication | Where-Object {$_.DisplayName -eq $applicationName}
Invoke-CMApplicationOnDemandInstall -CIGUID $application.CIGUID -SMSID $device.SMSID

# Create a script, approve, and initiate on a device. If same user is approving the script, disable "Script authors require additional script approver" option in the Hierarchy Settings.
$deviceName = "MyDevice"
$device = Get-CMDevice | Where-Object {$_.Name -eq $deviceName}
New-CMScript -Name "Test Script 5" -ScriptText "(Get-WMIObject win32_operatingsystem).Name"
$script = Get-CMScript | Where-Object {$_.ScriptName -eq 'Test Script 5'}
Approve-CMScript -ScriptGuid $script.ScriptGuid 
$runResult = Invoke-CMRunScript -ResourceId $device.MachineId -ScriptGuid $script.ScriptGuid 
Invoke-WaitScriptResult -ResourceId $device.MachineId -OperationId $runResult.value