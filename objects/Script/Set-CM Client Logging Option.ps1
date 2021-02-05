<#
.SYNOPSIS
    --.
.DESCRIPTION
Script Used for Run Script in ConfigMgr.
This will set logging options for a Config Mgr Client and cycle the Service

NOTE: This will not return any results to the Console since for these setting to take effect, we have to cycle the CM Client Service.

To Confirm the script works, you can check the registry values
https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/about-log-files


.INPUTS
    None.
.OUTPUTS
    None.
.NOTES
    Created by @gwblok
.LINK
    https://garytown.com
.LINK
    https://www.recastsoftware.com
.COMPONENT
    --
.FUNCTIONALITY
    --
#>

## Set script requirements
#Requires -Version 3.0

##*=============================================
##* VARIABLE DECLARATION
##*=============================================
#region VariableDeclaration
[cmdletbinding()]
    param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("Default","Verbose","Warnings and Errors","Errors Only")]
    [string] $LogLevel = "Default",
    [Parameter(Mandatory=$false)]
    [int] $LogMaxHistory = 3,
    [Parameter(Mandatory=$false)]
    [int] $LogMaxSizeMB = 2,
    [Parameter(Mandatory=$false)]
    [string]$DebugLogging = "FALSE"
    )

$ScriptVersion = "20.12.24.9"



#endregion
##*=============================================
##* END VARIABLE DECLARATION
##*=============================================

##*=============================================
##* FUNCTION LISTINGS
##*=============================================
#region FunctionListings

Function Set-CMClientLogging {
    #https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/about-log-files
    [cmdletbinding()]
    param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("Default","Verbose","Warnings and Errors","Errors Only")]
    [string] $LogLevel,
    [Parameter(Mandatory=$false)]
    [int] $LogMaxHistory,
    [Parameter(Mandatory=$false)]
    [int] $LogMaxSizeMB,
    [Parameter(Mandatory=$false)]
    [string]$DebugLogging
    
    )
    $CMClientLogsKeysPath = "HKLM:SOFTWARE\Microsoft\CCM\Logging\@GLOBAL"
    $CMClientParentLogsKeysPath = "HKLM:SOFTWARE\Microsoft\CCM\Logging"
    $CMClientDebuggingLogsKeysPath = "HKLM:SOFTWARE\Microsoft\CCM\Logging\DebugLogging"
    if ($LogLevel){
        if ($LogLevel -eq "Default"){Set-ItemProperty -Path $CMClientLogsKeysPath -Name "LogLevel" -Value "1"}
        elseif ($LogLevel -eq "Verbose"){Set-ItemProperty -Path $CMClientLogsKeysPath -Name "LogLevel" -Value "0"}
        elseif ($LogLevel -eq "Warnings and Errors"){Set-ItemProperty -Path $CMClientLogsKeysPath -Name "LogLevel" -Value "2"}
        elseif ($LogLevel -eq "Errors Only"){Set-ItemProperty -Path $CMClientLogsKeysPath -Name "LogLevel" -Value "3"}
        else {Set-ItemProperty -Path $CMClientLogsKeysPath -Name "LogLevel" -Value "1"}
        Write-Output "Set LogLevel to $LogLevel | "
        }
    if ($LogMaxHistory){
        Set-ItemProperty -Path $CMClientLogsKeysPath -Name "LogMaxHistory" -Value $LogMaxHistory
       Write-Output "Set LogMaxHistory to $LogMaxHistory | "
        }
    if ($LogMaxSizeMB){
        $LogMaxSize = $LogMaxSizeMB * 1048576
        Set-ItemProperty -Path $CMClientLogsKeysPath -Name "LogMaxSize" -Value $LogMaxSize
        Write-Output "Set LogMaxSize to $LogMaxSize | "
        }
    if ($DebugLogging){
        if ($DebugLogging -eq "TRUE")
            {
            if (!(test-path -Path $CMClientDebuggingLogsKeysPath -ErrorAction SilentlyContinue)){New-Item -Path $CMClientParentLogsKeysPath -Name "DebugLogging" | Out-Null}
            Set-ItemProperty -Path $CMClientDebuggingLogsKeysPath -Name "Enabled" -Value "True"
            Write-Output "Set $($CMClientDebuggingLogsKeysPath) Name Enabled to True | "
            }
        else
            {
            Set-ItemProperty -Path $CMClientDebuggingLogsKeysPath -Name "Enabled" -Value "False"
            }
        Write-Output "Set LogMaxSize to $LogMaxSize | "
        }
    Restart-Service -Name CcmExec
    }

#endregion
##*=============================================
##* END FUNCTION LISTINGS
##*=============================================

##*=============================================
##* SCRIPT BODY
##*=============================================
#region ScriptBody

Set-CMClientLogging -LogMaxHistory $LogMaxHistory -LogMaxSizeMB $LogMaxSizeMB -LogLevel $LogLevel -DebugLogging $DebugLogging

exit $exitcode
#endregion
##*=============================================
##* END SCRIPT BODY
##*=============================================