<#
    .DESCRIPTION
        Search for a computer certificate. If found, return the certificate expiration date

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

#Get all certificates in the specified store
$Certificates = Get-ChildItem -Path "Cert:\LocalMachine\$CertStore"
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
            $Result =  "Found $TemplateName - Expiration Date: $($CertResult.NotAfter)"
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
            $Result =  "Found $SubjectName - Expiration Date: $($CertResult.NotAfter)"
        }
    }
}
#Unable to find the certificate
if(!$Result)
{
    if($TemplateName)
    {
        $Result = "Unable to find $TemplateName"
    }
    if($SubjectName)
    {
        $Result = "Unable to find $SubjectName"
    }
}
return $Result