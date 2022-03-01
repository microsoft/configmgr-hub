<#
.Description
This script is meant to be used as a wrapper for the dsregcmd.exe utility from within the Configuration Manager console.
It's used to manage and troubleshoot device's AAD Hybrid Join.



When adding to the MECM Console, be sure that the parameters are configured as 'lists' using the values in the ValidateSet for each.



.Parameter Action
Join - Instructs a device to join AAD
Leave - Disjoin AAD
Status - Returns the current AAD join status

.Parameter SimpleOutput
Set to "True" to only return the AzureADJoined value from dsregcmd, otherwise the full output is parsed
If "False" (Default) an object will be returned that contains
#>

Param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("Join","Leave", "StatusOnly")]
    [STRING]$Action = "Status",

    [Parameter(Mandatory=$false)]
    [ValidateSet("True","False")]
    [STRING]$SimpleOutput = 0
)

$objJoin = "None"


#Attempt to join if requested. Pause for a bit to allow the action to complete before proceeding
if ($Action -eq "Join") {
    $join = dsregcmd /join /debug

    $objJoin = [pscustomobject]@{
        Property = "JoinDebugOutput"
        Status   = $join
    }

    Start-Sleep -Seconds 300
}

#Attempt to leave if requested. Pause for a bit to allow the action to complete before proceeding
if ($Action -eq "Leave") {
    $join = dsregcmd /leave /debug

    $objJoin = [pscustomobject]@{
        Property = "JoinDebugOutput"
        Status   = $join
    }

    Start-Sleep -Seconds 300
}

#Get the current status
$dsregstatus = dsregcmd /status

#dsregcmd doesn't give us very easy to parse output. First we'll trim it down and parse out all of the useful values on any line that matches 'name : value'
#To avoid accidentally parsing out URLs later, replace ' : ' with '~'
$TrimmedOutput = ($dsregstatus | where-object {$_ -like "* : *"}).replace(" : ","~") |
        ForEach-Object {$_.Trim() }


#Build a return object out of the dsregcmd output.
#Using convertfrom-string to change the name~value pairs into object properties
$objReturn = [PSCustomObject]@{}
Foreach ($thisStatus in $TrimmedOutput) {
        $tempStatus = $thisStatus | ConvertFrom-String -Delimiter "~"
        $objReturn| Add-Member -MemberType NoteProperty -Name $tempStatus.P1 -Value $tempStatus.P2
}

<#
#Create a new object that tells us if the device is joined, join status details and the output of dsregcmd /join or /leave if it was specified
$objReturn = [PSCustomObject]@{
    AzureADJoined = $objstatus.AzureAdJoined
    StatusDetail = $objstatus
    ActionDetail = $objJoin
}#>

#Exit Cleanly
if ($SimpleOutput -eq "True") {
    Return ($objReturn | Select-Object -Property azureadjoined)
} else {
    return $objReturn
}

