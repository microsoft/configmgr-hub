<#	
.Synopsis
LocalAdminGroup is a script that can be deployed in a Domain environment, from ConfigMgr, that will add or remove individual users from the Local Administrators group.
Careful thought should be exercised on why you would want to use this.

.Description
===========================================================================
	 Created on:   	05/03/2021
	 Created by:   	Ben Whitmore
	 Organization: 	-
	 Filename:     	LocalAdminGroup.ps1
===========================================================================

Version:
1.0.1 - 05/03/2021
- Replaced ADSI command with Add-LocalGroupMember and Remove-LocalGroupMember. Thanks @IoanPopovici

1.0 - 05/03/2021

.Parameter Username
SAMAccountName of the user being added

.Parameter Action
"Add" will add the user to the Local Administrators Group
"Remove" will remove the user from the Local Administrators Group

.Example
LocalAdminGroup.ps1 -Username ernest.shackleton -Action "Add"

.Example
LocalAdminGroup.ps1 -Username ernest.shackleton -Action "Remove"

#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [String]$Username,
    [Parameter(Position = 1, Mandatory = $true)]
    [ValidateSet ("Add", "Remove")]
    [String]$Action
)

$LocalAdmins = Get-LocalGroupMember Administrators | Select-Object -ExpandProperty Name
$User = Join-Path -Path $env:USERDOMAIN -ChildPath $Username
$UserExists = $Null
$UserExistsFinal = $Null

Switch ($Action) {

    Add {
        Write-Output "Checking if $Username is already in the Local Administrators Group"
        foreach ($Admin in $LocalAdmins) {

            If ($Admin -eq $User) {
                Write-Output "$Username already exists in the Local Administrators Group"
                $UserExists = $True
            }
        }

        If (!($UserExists)) {
            Write-Output "Adding $Username to Local Administrators Group"
            Try {
                Add-LocalGroupMember -Group "Administrators" -Member $User -ErrorAction Stop
            }
            Catch {
                Write-Warning $error[0]
            }
        }
    }

    Remove {
        Write-Output "Checking if $Username is in the Local Administrators Group"
        foreach ($Admin in $LocalAdmins) {

            If ($Admin -eq $User) {
                Write-Output "$Username is in the Local Administrators Group"
                $UserExists = $True
            }
        }

        If ($UserExists) {
            Write-Output "Removing $Username from Local Administrators Group"
            Try {
                Remove-LocalGroupMember -Group "Administrators" -Member $User -ErrorAction Stop
            }
            Catch {
                Write-Warning $error[0]
            }
        }
    }
}

$LocalAdminsFinal = Get-LocalGroupMember Administrators | Select-Object -ExpandProperty Name

foreach ($Admin in $LocalAdminsFinal) {

    If ($Admin -eq $User) {
        $UserExistsFinal = $True
    }
}

If ($UserExistsFinal) {
    Write-Output "Summary: $Username is present in the Local Administrators Group on $env:ComputerName"
}
else {
    Write-Output "Summary: $Username is absent from the Local Administrators Group on $env:ComputerName"
}
