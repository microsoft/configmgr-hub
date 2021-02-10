<#
.SYNOPSIS
    Enables the built-in local Administrator account
.DESCRIPTION
    Enables the built-in local Administrator account
.PARAMETER Enable
    Set to True to Enable the account    
    Set to False to Disable the account
.NOTES
    Author:     Adam Gross
    Website:    https://www.ASquareDozen.com
    GitHub:     https://www.github.com/AdamGrossTX
    Twitter:    https://www.twitter.com/AdamGrossTX

    Using NET commands instead
        net user Administrator /ACTIVE:YES
        net user Administrator P@ssw0rd
        
    Removing the option to set the password here since the env uses LAPS and password parameter is passed in plain text and will show in the client logs.
#>
Param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("True","False")]
    [string]$Enable
    #,[string]$Password = "P@ssw0rd"
)

Try {
    $LocalAdminSIDSearchString = "S-1-5-21-*-500"
    
    $Account = Get-LocalUser | Where-Object {$_.SID -like $LocalAdminSIDSearchString}
    $Return = @()
    If($Account) {

        If($Enable -eq "True") {
            If(-not $Account.Enabled) {
                $Account | Enable-LocalUser
                $Return += "Account Enabled"
            }
            Else {
                $Return += "Account Already Enabled"
            }
        }
        Else {
            If($Account.Enabled) {
                $Account | Disable-LocalUser
                $Return += "Account Disabled"
            }
            Else {
                $Return += "Account Already Diabled"
            }
        }
        <#If($Password) {
            $SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
            $Account | Set-LocalUser -Password $SecurePassword
            $Return += "Password Reset"
        }#>
    }
    $Return
}
Catch {
    Return $Error[0]
}

