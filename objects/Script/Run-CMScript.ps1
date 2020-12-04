<#
.SYNOPSIS
    Runs a script in the MEMCM run script feature.
.DESCRIPTION
    Runs a string input in the MEMCM run script feature by converting it to a script block and using Invoke-Command.
.PARAMETER
    Script.
.EXAMPLE
    Run-CMScript.ps1 -Script 'Get-BCStatus | Select-Object -Property BranchCacheIsEnabled, BranchCacheServiceStatus'
.INPUTS
    System.String.
.OUTPUTS
    System.String.
.NOTES
    Created by Ioan Popovici
.LINK
    https://SCCM.Zone/
.LINK
    https://SCCM.Zone/GIT
.LINK
    https://SCCM.Zone/ISSUES
.COMPONENT
    CM
.FUNCTIONALITY
    Run Script
#>

## Set script requirements
#Requires -Version 3.0

##*=============================================
##* SCRIPT BODY
##*=============================================
#region ScriptBody

Param (
    [Parameter(Mandatory=$true,Position=0)]
    [ValidateNotNullorEmpty()]
    [Alias('scr')]
    [string]$Script
)
Begin {
    $ScriptBlock = [ScriptBlock]::Create($Script)
}

Process {
    Try {
        $Result = Invoke-Command -ScriptBlock $ScriptBlock
    }
    Catch {
        $Result = $($_.Exception.Message)
    }
    Finally {
        Write-Output -InputObject $Result
    }
}

#endregion
##*=============================================
##* END SCRIPT BODY
##*=============================================