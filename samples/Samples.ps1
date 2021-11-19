
# Sample usage, run CommonFunctions.ps1 first to import the functions

# Create collection and add one direct member
$collection = New-CMCollection -Name "Test Collection 1"
$device = (Get-CMDevice)[0]
Add-CMCollectionMember -CollectionID $collection.CollectionID -ResourceID $device.MachineId -RuleName "Direct member $($device.Name)"

# Invoke app install remotely for an application already deployed to the client (for this one client must know about this app)
$deviceName = "MyDevice"
$applicationName = "My Application"
$device = Get-CMDevice | Where-Object {$_.Name -eq $deviceName}
$application = Get-CMApplication | Where-Object {$_.DisplayName -eq $applicationName}
Invoke-CMApplicationInstall -CIGUID $application.CIGUID -SMSID $device.SMSID

# Invoke app uninstall remotely for an available application already deployed to the client (for this one client must know about this app)
$deviceName = "MyDevice"
$applicationName = "My Application"
$device = Get-CMDevice | Where-Object {$_.Name -eq $deviceName}
$application = Get-CMApplication | Where-Object {$_.DisplayName -eq $applicationName}
Invoke-CMApplicationUninstall -CIGUID $application.CIGUID -SMSID $device.SMSID
