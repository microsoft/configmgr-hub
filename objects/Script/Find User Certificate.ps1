<#
    .DESCRIPTION
        Search for a user certificate. If found, return the certificate expiration date

    .PARAMETER CertificateStore
        Specify the certificate store to search in. Valid values are "Personal", "Root", and "Intermediate"

    .PARAMETER TemplateName
        Specify the certificate template name to search for. Cannot use this parameter with the SubjectName parameter

    .PARAMETER SubjectName
        Specify the certificate subject name to search for. Cannot use this parameter with the TemplateName parameter

    .NOTES
        Created by: Jon Anderson (@ConfigJon)
        Website: https://www.configjon.com
#>

#Parameters
param(
    [Parameter(Mandatory=$True)][String]$CertificateStore,
    [Parameter(Mandatory=$False)][String]$TemplateName,
    [Parameter(Mandatory=$False)][String]$SubjectName
)

#Functions
Function Remove-ScriptFiles
{
    param(
        [Parameter(Mandatory=$True)][String]$UserFile,
        [Parameter(Mandatory=$False)][String]$UserOutput,
        [Parameter(Mandatory=$False)][String]$TaskName
    )
    Remove-Item -Path $UserFile -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $UserOutput -Force -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$False -ErrorAction SilentlyContinue
}

#Parameter validation
if(!$TemplateName -and !$SubjectName)
{
    Write-Output "Must specify either a TemplateName or SubjectName to search for"
    exit 1
}
if(($CertificateStore -ne "Personal") -and ($CertificateStore -ne "Root") -and ($CertificateStore -ne "Intermediate"))
{
    Write-Output "Invalid certificate store specified. Valid values are Personal, Root, and Intermediate"
    exit 1
}

#Convert the certificate store value
switch($CertificateStore)
{
    "Personal" {$CertStore = "My"}
    "Root" {$CertStore = "Root"}
    "Intermediate" {$CertStore = "CA"}
}

#Set user script variables
$UserFile = "$env:windir\Temp\GetUserCert.ps1"
$UserOutput = "$env:windir\Temp\UserResult.txt"
$UserScript = @'
param(
    [Parameter(Mandatory=$True)][String]$CertStore,
    [Parameter(Mandatory=$False)][String]$TemplateName,
    [Parameter(Mandatory=$False)][String]$SubjectName
)
#Get all certificates in the specified store
$Certificates = Get-ChildItem -Path "Cert:\CurrentUser\$CertStore"
#Search for the certificate
ForEach($Certificate in $Certificates)
{
    $ErrorActionPreference = "SilentlyContinue"
    if($TemplateName)
    {
        if(($Certificate.Extensions.Format(1)[0].Split('(')[0] -Replace "Template=") -eq $TemplateName)
        {
            if($CertResult -eq $null)
            {
                $CertResult = $Certificate
            }
            elseif($Certificate.NotAfter -gt $CertResult.NotAfter)
            {
                $CertResult = $Certificate
            }
            $ReturnText = "Found $TemplateName - Expiration Date: $($CertResult.NotAfter)"
            $FoundCert = $True
        }
    }
    if($SubjectName)
    {
        if($Certificate.Subject -match $SubjectName)
        {
            if($CertResult -eq $null)
            {
                $CertResult = $Certificate
            }
            elseif($Certificate.NotAfter -gt $CertResult.NotAfter)
            {
                $CertResult = $Certificate
            }
            $ReturnText = "Found $SubjectName - Expiration Date: $($CertResult.NotAfter)"
            $FoundCert = $True
        }
    }
}
#Unable to find the certificate
if(!$FoundCert)
{
    if($TemplateName)
    {
        $ReturnText = "Unable to find $TemplateName for user $env:username"
    }
    if($SubjectName)
    {
        $ReturnText = "Unable to find $SubjectName for user $env:username"
    }
}
#Output ReturnText to a file
$ReturnText | Out-File -FilePath "$env:windir\Temp\UserResult.txt"
'@
$UserScript | Out-File -FilePath $UserFile -Force

#Get the currently logged on user
$User = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName
if([String]::IsNullOrEmpty($User))
{
    Write-Output "Unable to find a logged on user account"
    exit 1
}
$TaskName = "GetUserCert"

#Cleanup previous attempts
if((Get-ScheduledTask | Where-Object -Property TaskName -eq $TaskName).TaskName)
{
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$False -ErrorAction SilentlyContinue
}
if(Test-Path -Path $UserOutput)
{
    Remove-Item -Path $UserOutput -Force -ErrorAction SilentlyContinue
}

#Create the scheduled task
if($TemplateName)
{
    $TaskAction = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File $UserFile -CertStore $CertStore -TemplateName ""$TemplateName"""
}
elseif($SubjectName)
{
    $TaskAction = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File $UserFile -CertStore $CertStore -SubjectName ""$SubjectName"""
}
$TaskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:01:00
$TaskPrincipal = New-ScheduledTaskPrincipal -UserId $User
Register-ScheduledTask -TaskName "$TaskName" -Action $TaskAction -Settings $TaskSettings -Principal $TaskPrincipal | Out-Null

#Run the scheduled task
Start-ScheduledTask -TaskName $TaskName | Out-Null
$Counter = 0
$TaskStatus = (Get-ScheduledTask -TaskName $TaskName).State
while(($TaskStatus -ne "Ready") -and ($Counter -lt 12))
{
    Start-Sleep -Seconds 5
    $TaskStatus = (Get-ScheduledTask -TaskName $TaskName).State
    $Counter++
}

#Wait for the scheduled task to complete
if($TaskStatus -ne "Ready")
{
    Write-Output "Timeout waiting for the scheduled task to complete"
    Remove-ScriptFiles -UserFile $UserFile -UserOutput $UserOutput -TaskName $TaskName
    exit 1
}

#Output results
if(Test-Path -Path $UserOutput)
{
    $UserResult = Get-Content -Path $UserOutput
    if($UserResult -eq $null)
    {
        Write-Output "The scheduled task failed to run"
        Remove-ScriptFiles -UserFile $UserFile -UserOutput $UserOutput -TaskName $TaskName
        exit 1
    }
    else
    {
        $UserResult = [String]$UserResult
        Write-Output $UserResult
    }
}
else
{
    Write-Output "The scheduled task failed to run"
    Remove-ScriptFiles -UserFile $UserFile -UserOutput $UserOutput -TaskName $TaskName
    exit 1
}

#Cleanup
Remove-ScriptFiles -UserFile $UserFile -UserOutput $UserOutput -TaskName $TaskName