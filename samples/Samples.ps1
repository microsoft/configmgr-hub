
# Sample usage

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

