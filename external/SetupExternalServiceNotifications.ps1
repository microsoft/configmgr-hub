<#
  .SYNOPSIS
  Setup Microsoft Configuration Manager to send events to external services

  .DESCRIPTION
  The script sets up Configuration Manager to send specific types of events to external services. Supported event types include Application Approval events and Status Message Filter based events.
  In order to send these events to external systems, you need to create a subscription. Each subscription can be tied to multiple events. Follow "Create a subscription" option to create a subscription. 
  This script also allows creation of status message filter rules that can send matching status messages to an external system. Follow "Create a status filter rule to expose status messages" option to create such a filter. 
  You can also list available subsciptions with associated events by choosing "List available subscriptions".

  .LINK
  https://docs.microsoft.com/en-us/mem/configmgr/core/get-started/2021/technical-preview-2106#bkmk_pushnotify

  .EXAMPLE
  PS> SetupExternalServiceNotifications.ps1
#>


function PromptUserForEventSelection
{
    param 
    (
        [object[]]$Options
    )

    <#
    .SYNOPSIS
    Prompts user to select an event out of available events
    #>

    $AllSelectedEvents = @()
    $SelectedOption = 0
    do
    {
        Write-Host "Select an event number. Enter 0 when done to create new subscription. `n"
        $OptionNo = 0
        foreach ($Option in $Options) 
        {
            $OptionNo += 1
            Write-Host ("$OptionNo`: $($Option.DisplayName)")
        }

        Write-Host ""

        if ([Int]::TryParse((Read-Host), ([ref]$SelectedOption))) 
        {
            Write-Host ""
            if ($SelectedOption -eq 0) 
            {
                return $AllSelectedEvents
            }
            elseif(($SelectedOption -le $Options.Count) -and ($SelectedOption -gt 0)) 
            {
                $NewItem = [system.tuple]::Create($($Options.Get($SelectedOption - 1).EventType), $($Options.Get($SelectedOption - 1).EventName))
                if($AllSelectedEvents.Contains($NewItem) -eq $false)
                {
                    $AllSelectedEvents+=$NewItem
                }
            }
        }
    }while($true)
}

function PromptUser 
{
    param 
    (
        [string]$Message,
        [string[]]$Options
    )

    <#
    .SYNOPSIS
    Prompts user to select an option
    #>
    
    $SelectedOption = 0
    do 
    {
        Write-Host $Message
        Write-Host "0: Skip/Continue"

        $OptionNo = 0
        foreach ($Option in $Options) 
        {
            $OptionNo += 1
            Write-Host ("$OptionNo`: $Option")            
        }

        Write-Host ""

        if ([Int]::TryParse((Read-Host), ([ref]$SelectedOption))) 
        {
            Write-Host ""
            if ($SelectedOption -eq 0) 
            {
                return [system.tuple]::Create(0, '')
            }
            elseif($SelectedOption -le $Options.Count) 
            {
                return [system.tuple]::Create($SelectedOption, $Options.Get($SelectedOption - 1))
            }
        }
    } while($true)
} 

# Check if console is installed
if($null -eq $ENV:SMS_ADMIN_UI_PATH)
{
    Write-Host "Unable to locate Configuration Manager Console on this machine. Please run this script on a machine where Configuration Manager Console is installed."
    exit
}

$ConsoleDir = "$ENV:SMS_ADMIN_UI_PATH\.."

# Try to find Site Server
[bool]$IsSiteServerFound = $false
if($null -ne $(Get-WmiObject -Query "SELECT * FROM __Namespace WHERE Name = `"SMS`"" -Namespace "root"))
{
    $FoundSiteServerPath = [System.Net.Dns]::GetHostByName(($ENV:ComputerName)).HostName
    if($null -ne $FoundSiteServerPath)
    {
        $response = Read-Host -Prompt "This is site server machine with FQDN `"$FoundSiteServerPath`", continue with this site server (Y/N)?"
        if($response -like "Y*")
        {
            $SiteServerPath = $FoundSiteServerPath
            $IsSiteServerFound = $true
        }
    }
}

# If this machine is not site server, ask for site server FQDN
if($IsSiteServerFound -eq $false)
{
    Write-Host "Enter Site Server FQDN: " -NoNewline
    $SiteServerPath = Read-Host
}

# Get the provider machine
$AllProviderLocations=Get-WmiObject -Query "SELECT * FROM SMS_ProviderLocation" -Namespace "root\sms" -ComputerName $SiteServerPath
foreach($ProviderLocation in $AllProviderLocations)
{
    $SiteCode = $ProviderLocation.SiteCode
    $ProviderMachineName = $ProviderLocation.Machine

    # Pick first provider
    break;
}


# Customizations
$initParams = @{}

# Import the ConfigurationManager.psd1 module
if($null -eq (Get-Module ConfigurationManager)) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if($null -eq (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Cache current location. Need to switch to this directory when script is finished
$BeforeLocation = Get-Location

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams

# Load OData Provider
Add-Type -Path "$ConsoleDir\AdminUI.WqlQueryEngine.dll"
$WqlConnectionManager = New-Object -TypeName "Microsoft.ConfigurationManagement.ManagementProvider.WqlQueryEngine.WqlConnectionManager"
[void]($WqlConnectionManager.Connect($ProviderMachineName))

# Check Site Version
$SiteVersion = $WqlConnectionManager.NamedValueDictionary["ConnectedSiteVersion"]
if([version]$SiteVersion -lt [version]"5.0.9052.1000")
{
    Write-Host "Site server doesn't support External System Notifications"
    Set-Location $BeforeLocation
    exit
}

# Create ODataConnectionManager to communicate with AdminService
$NamedValuesDictionary = New-Object -TypeName "Microsoft.ConfigurationManagement.ManagementProvider.SmsNamedValuesDictionary"
$NamedValuesDictionary["ConnectedSiteCode"] = $SiteCode
$NamedValuesDictionary["ProviderMachineName"] = $ProviderMachineName
Add-Type -Path "$ConsoleDir\AdminUI.ODataQueryEngine.dll"
$ODataConnectionManager = New-Object -TypeName "Microsoft.ConfigurationManagement.ManagementProvider.ODataQueryEngine.ODataConnectionManager" -ArgumentList $NamedValuesDictionary,$WqlConnectionManager
[void]($ODataConnectionManager.Connect($ProviderMachineName))

$CreateSubAction = 'Create a subscription'
$ListSubsAction = 'List available subscriptions'
$CreateRuleAction = 'Create a status filter rule to expose status messages'

$AvailableActions = @()
$AvailableActions+=$ListSubsAction
$AvailableActions+=$CreateRuleAction

# Create subscription action is only available on top level site
$ParentSiteCode = (Get-WmiObject -Query "SELECT ParentSiteCode FROM SMS_SCI_SiteDefinition WHERE SiteServerName=`"$SiteServerPath`"" -Namespace "root\sms\site_$SiteCode" -ComputerName $ProviderMachineName) | Select-Object -ExpandProperty ParentSiteCode
if($ParentSiteCode.Length -eq 0)
{
    # This is top level site, user can create a subscription
    $AvailableActions+=$CreateSubAction
}
else
{
    Write-Host ""
    Write-Warning "In order to create a subscription, you need to run this script on top level site. Detected top level site code: $ParentSiteCode"
    Write-Host ""
}

# Prompt user to select an action
$Res = PromptUser -Message 'Select an action' -Options $AvailableActions

if($Res.Item2 -eq $CreateSubAction)
{
    Write-Host "Provide a name for the new subscription: " -NoNewline
    $NewSubscriptionName = Read-Host

    Write-Host "Provide a description for the new subscription: " -NoNewline
    $NewSubscriptionDescription = Read-Host

    Write-Host "Specify the URL provided by the external system: " -NoNewline
    $NewSubscriptionUrl = Read-Host
    $NewSubscriptionUrlb = [System.Text.Encoding]::ASCII.GetBytes($NewSubscriptionUrl)
    $r = Invoke-WmiMethod -Namespace "root\sms\site_$SiteCode" -Class "SMS_Site" -Name "EncryptData" -ArgumentList $NewSubscriptionUrlb, $SiteCode -ComputerName $ProviderMachineName
    $EncryptedUrl = $r.EncryptedData
    Write-Host ""    
 
    # Get list of applicable events from AdminService
    $ApplicableEventsODataResultObject=$ODataConnectionManager.ExecuteMethod("v1.0/NotificationEventRule")
    $ApplicableEvents = $ApplicableEventsODataResultObject.PropertyList["value"] | ConvertFrom-Json

    $AllSelectedEventNames = PromptUserForEventSelection -Message -Options $ApplicableEvents

    # Create JSON body
    $SubscribedEvents = @()
    foreach($SelectedEventName in $AllSelectedEventNames)
    {
        $SubscribedEvents+=@{"EventType" = $($SelectedEventName.Item1); "EventName" = $($SelectedEventName.Item2)}
    }
    $CreateSubscriptionBody = @{"Name" = $NewSubscriptionName; "Description" = $NewSubscriptionDescription; "ExternalURL" = $EncryptedUrl; "SubscribedEvents" = $SubscribedEvents}

    # POST the subscription to DB via AdminService
    try
    { 
        $ODataConnectionManager.ExecuteMethod("v1.0/NotificationSubscription", (ConvertTo-Json $CreateSubscriptionBody))
        Write-Host "Subscription created successfuly."
    }
    catch
    { 
        Write-Host $_.Exception 
    }
}
elseif($Res.Item2 -eq $ListSubsAction)
{
    # List available subscriptions
    $AllSubscriptionsODataResultObject=$ODataConnectionManager.ExecuteMethod("v1.0/NotificationSubscription?`$expand=SubscribedEvents")
    $AllSubscriptions = $AllSubscriptionsODataResultObject.PropertyList["value"] | ConvertFrom-Json
    $AllSubscriptions | Select-Object -Property ID,Name,Description,CreatedBy,DateCreated,LastModifiedBy,DateLastModified,SubscribedEvents
}
elseif($Res.Item2 -eq $CreateRuleAction)
{
    # Create a status message filter rule to expose status messages to external notification queue

    Write-Host "Provide a name for the new status message filter rule: " -NoNewline
    $NewRuleName = Read-Host

    $AllSources = (Get-WmiObject -Query "SELECT DISTINCT moduleName FROM SMS_StatMsgModuleNames" -Namespace "root\sms\site_$SiteCode" -ComputerName $ProviderMachineName) | Select-Object -Property ModuleName
    $SourceRes = PromptUser -Message "Source:" -Options ($AllSources.ModuleName)
    
    $AllSiteCodes = (Get-WmiObject -Query "SELECT DISTINCT SiteCode FROM SMS_ComponentSummarizer" -Namespace "root\sms\site_$SiteCode" -ComputerName $ProviderMachineName) | Select-Object -Property SiteCode
    $SiteCodeRes = PromptUser -Message "Site Code:" -Options ($AllSiteCodes.SiteCode)

    $AllSystems = (Get-WmiObject -Query "SELECT DISTINCT MachineName FROM SMS_ComponentSummarizer" -Namespace "root\sms\site_$SiteCode" -ComputerName $ProviderMachineName) | Select-Object -Property MachineName
    $SystemRes = PromptUser -Message "System:" -Options ($AllSystems.MachineName)
    
    $AllComponents = (Get-WmiObject -Query "SELECT DISTINCT ComponentName FROM SMS_ComponentSummarizer ORDER BY ComponentName" -Namespace "root\sms\site_$SiteCode" -ComputerName $ProviderMachineName) | Select-Object -Property ComponentName
    $ComponentRes = PromptUser -Message "Component:" -Options ($AllComponents.ComponentName)

    $MessageTypeRes = PromptUser -Message "Message Type:" -Options `
        ([Microsoft.ConfigurationManagement.Cmdlets.HS.Commands.MessageType]::Milestone, `
         [Microsoft.ConfigurationManagement.Cmdlets.HS.Commands.MessageType]::Detail, `
         [Microsoft.ConfigurationManagement.Cmdlets.HS.Commands.MessageType]::Audit)
    $SeverityRes = PromptUser -Message "Severity:" -Options `
        ([Microsoft.ConfigurationManagement.Cmdlets.HS.Commands.SeverityType]::Informational, `
         [Microsoft.ConfigurationManagement.Cmdlets.HS.Commands.SeverityType]::Warning, `
         [Microsoft.ConfigurationManagement.Cmdlets.HS.Commands.SeverityType]::Error)


    Write-Host "Message ID (0 to skip, 1 to 65535): " -NoNewline
    $MessageIDRes = 0
    while(([int]::TryParse((Read-Host), ([ref]$MessageIDRes)) -eq $false) -or ($MessageIDRes -lt 0) -or ($MessageIDRes -gt 65535)){ Write-Host "Message ID (0 to skip, 1 to 65535): " -NoNewline }

    $PropertyRes=[system.tuple]::Create(0, 'Cancel')
    $PropertyValueRes=[system.tuple]::Create(0, 'Cancel')

    if($SourceRes.Item1 -ne 0)
    {
        $AllProperties = (Get-WmiObject -Query "SELECT DISTINCT att.AttributeID FROM SMS_StatusMessage AS stat INNER JOIN SMS_StatMsgAttributes AS att ON stat.RecordID = att.RecordID WHERE stat.moduleName=`"$($SourceRes.Item2)`"" `
            -Namespace "root\sms\site_$SiteCode" -ComputerName $ProviderMachineName) | Select-Object -ExpandProperty AttributeID

        Add-Type -Path "$ConsoleDir\Microsoft.ConfigurationManagement.ManagementProvider.dll"
        $AttributeResourceAssemblyDescription = New-Object -TypeName "Microsoft.ConfigurationManagement.AdminConsole.Schema.AssemblyDescription"
        $AttributeResourceAssemblyDescription.AssemblyPath="$ConsoleDir\AdminUI.UIResources.dll"
        $AttributeResourceAssemblyDescription.AssemblyType="Microsoft.ConfigurationManagement.AdminConsole.UIResources.SMS_StatusMessage-AttributeID.resources"

        $AllPropertyName = @{}
        foreach($PropertyItem in $AllProperties)
        {
            $AllPropertyName.Add([Microsoft.ConfigurationManagement.AdminConsole.Common.UtilityClass]::GetStringFromAssembly($AttributeResourceAssemblyDescription, $PropertyItem), [string]($PropertyItem))
        }

        $PropertyRes = PromptUser -Message "Property:" -Options (($AllPropertyName.Keys) | Sort-Object)

        if($PropertyRes.Item1 -ne 0)
        {
            $SelectedPropertyId = $AllPropertyName[$PropertyRes.Item2]
            $AllPropertyValues = (Get-WmiObject -Query "SELECT DISTINCT att.AttributeValue FROM SMS_StatusMessage AS stat INNER JOIN SMS_StatMsgAttributes AS att ON stat.RecordID = att.RecordID WHERE stat.moduleName = `"$($SourceRes.Item2)`" AND att.AttributeID = $SelectedPropertyId ORDER BY att.AttributeValue" `
                -Namespace "root\sms\site_$SiteCode" -ComputerName $ProviderMachineName) | Select-Object -ExpandProperty AttributeValue
            $PropertyValueRes = PromptUser -Message "Property value:" -Options ($AllPropertyValues)
        }
    }
    
    $ExternalNotificationFilterNamePrefix = "External Service Notifications "
    $StatulsFilterNamePrefix = "Status Filter Rule: "
    $NewFilterRuleParams = 
    @{
          Name="$ExternalNotificationFilterNamePrefix$NewRuleName"
    }

    if($SourceRes.Item1 -ne 0) {$NewFilterRuleParams.Source = $SourceRes.Item2}
    if($SiteCodeRes.Item1 -ne 0) {$NewFilterRuleParams.StatusFilterRuleSiteCode = $SiteCodeRes.Item2}
    if($SystemRes.Item1 -ne 0) {$NewFilterRuleParams.SiteSystemServerName = $SystemRes.Item2}
    if($ComponentRes.Item1 -ne 0) {$NewFilterRuleParams.ComponentName = $ComponentRes.Item2}
    if($MessageTypeRes.Item1 -ne 0) {$NewFilterRuleParams.MessageType = $MessageTypeRes.Item2}
    if($SeverityRes.Item1 -ne 0) {$NewFilterRuleParams.SeverityType = $SeverityRes.Item2}
    if($MessageIDRes -ne 0) {$NewFilterRuleParams.MessageId = $MessageIDRes}
    if($PropertyRes.Item1 -ne 0) {$NewFilterRuleParams.PropertyId = $PropertyRes.Item2}
    if(($PropertyRes.Item1 -ne 0) -and ($PropertyValueRes.Item1 -ne 0)) {$NewFilterRuleParams.PropertyValue = $PropertyValueRes.Item2}

    Write-Host ""
    Write-Warning "A new status message filter rule with the following filters will be created. 
Modifying this rule's actions in console will remove it from external service notifications' applicable rules."
    $NewFilterRuleParams

    Pause

    Write-Host ""
    
    try
    {
        # Create the status filter rule with specified properties and no actions
        [void](New-CMStatusFilterRule @NewFilterRuleParams)

        $NewRuleName = "$StatulsFilterNamePrefix$ExternalNotificationFilterNamePrefix$NewRuleName"
        Write-Host "Successfully created `"$NewRuleName`"."
    }
    catch
    {
        Write-Error $_.Exception
        Set-Location $BeforeLocation
        exit
    }

    try
    {    
        # Modify the actions of the newly created rule to expose the status messages to external notification queue
        $NewRuleInstance=Get-WmiObject -Query "SELECT * FROM SMS_SCI_SCPropertyList WHERE ItemType=`"SMS_STATUS_MANAGER`" AND PropertyListName=`"$NewRuleName`"" `
            -Namespace "root\sms\site_$SiteCode" -ComputerName $ProviderMachineName
        $RuleValues = $NewRuleInstance.Values

        for ($Index = 0 ; $Index -lt $RuleValues.Count ; $Index++)
        {
            if($RuleValues.Get($Index) -like 'Actions=*')
            {
                $RuleValues[$Index] = "Actions=80"
            }
            if($RuleValues.Get($Index) -like 'Actions Mask=*')
            {
                $RuleValues[$Index] = "Actions Mask=64"
            }
        }

        # Get Status Manager Component
        $StatusManagerComponentInstance=Get-WmiObject -Query "SELECT * FROM SMS_SCI_Component WHERE FileType=2 AND ItemName=`"SMS_STATUS_MANAGER|SMS Site Server`" AND SiteCode=`"$SiteCode`" AND ItemType=`"Component`"" `
            -Namespace "root\sms\site_$SiteCode" -ComputerName $ProviderMachineName
        $StatusManagerComponentPropertyList = $StatusManagerComponentInstance.PropLists

        # Update Status Manager Property List
        $($StatusManagerComponentPropertyList.Where({$_.PropertyListName -eq $NewRuleName})).Values=$RuleValues

        # Update Status Manager Compoennt
        $StatusManagerComponentInstance.PropLists = $StatusManagerComponentPropertyList 

        # Save changes
        [void](Set-WmiInstance -InputObject $StatusManagerComponentInstance)

        Write-Host ""
        Write-Host "Successfully marked `"$NewRuleName`" for external service notifications. Modifying this rule's actions in console will remove it as an applicable event."
    }
    catch
    {
        Write-Error $_.Exception
    }
}

Set-Location $BeforeLocation

# SIG # Begin signature block
# MIIjnwYJKoZIhvcNAQcCoIIjkDCCI4wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAlApS173zZFtJ6
# 4wQdgb75gs2KD2ncxhckIlYSYsLjQ6CCDYEwggX/MIID56ADAgECAhMzAAAB32vw
# LpKnSrTQAAAAAAHfMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjAxMjE1MjEzMTQ1WhcNMjExMjAyMjEzMTQ1WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC2uxlZEACjqfHkuFyoCwfL25ofI9DZWKt4wEj3JBQ48GPt1UsDv834CcoUUPMn
# s/6CtPoaQ4Thy/kbOOg/zJAnrJeiMQqRe2Lsdb/NSI2gXXX9lad1/yPUDOXo4GNw
# PjXq1JZi+HZV91bUr6ZjzePj1g+bepsqd/HC1XScj0fT3aAxLRykJSzExEBmU9eS
# yuOwUuq+CriudQtWGMdJU650v/KmzfM46Y6lo/MCnnpvz3zEL7PMdUdwqj/nYhGG
# 3UVILxX7tAdMbz7LN+6WOIpT1A41rwaoOVnv+8Ua94HwhjZmu1S73yeV7RZZNxoh
# EegJi9YYssXa7UZUUkCCA+KnAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUOPbML8IdkNGtCfMmVPtvI6VZ8+Mw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDYzMDA5MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAnnqH
# tDyYUFaVAkvAK0eqq6nhoL95SZQu3RnpZ7tdQ89QR3++7A+4hrr7V4xxmkB5BObS
# 0YK+MALE02atjwWgPdpYQ68WdLGroJZHkbZdgERG+7tETFl3aKF4KpoSaGOskZXp
# TPnCaMo2PXoAMVMGpsQEQswimZq3IQ3nRQfBlJ0PoMMcN/+Pks8ZTL1BoPYsJpok
# t6cql59q6CypZYIwgyJ892HpttybHKg1ZtQLUlSXccRMlugPgEcNZJagPEgPYni4
# b11snjRAgf0dyQ0zI9aLXqTxWUU5pCIFiPT0b2wsxzRqCtyGqpkGM8P9GazO8eao
# mVItCYBcJSByBx/pS0cSYwBBHAZxJODUqxSXoSGDvmTfqUJXntnWkL4okok1FiCD
# Z4jpyXOQunb6egIXvkgQ7jb2uO26Ow0m8RwleDvhOMrnHsupiOPbozKroSa6paFt
# VSh89abUSooR8QdZciemmoFhcWkEwFg4spzvYNP4nIs193261WyTaRMZoceGun7G
# CT2Rl653uUj+F+g94c63AhzSq4khdL4HlFIP2ePv29smfUnHtGq6yYFDLnT0q/Y+
# Di3jwloF8EWkkHRtSuXlFUbTmwr/lDDgbpZiKhLS7CBTDj32I0L5i532+uHczw82
# oZDmYmYmIUSMbZOgS65h797rj5JJ6OkeEUJoAVwwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIVdDCCFXACAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAd9r8C6Sp0q00AAAAAAB3zAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgiRZ0ss2q
# LXhZcUc9yN24gsoXndk92piX2rh1fS63w6UwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQCEcASlCn7qLys/OACPuZAGTrKrIf5WnRF+S4SVcFz5
# ulWEtZiB1mcY95Y/8jAzlh+4rtjR8ZWqYd50pzpARYq2UwXXRrDCi28BkhyV/zim
# wB2kn2wwGCLa89M0B2HPQFj7p6wJ9M2p7cD3mEUyDIFef4LCK3sjWa/DAFEadHxt
# OYucGkBlm0GVJIIBujd9DnWt0xJrgHbrFgeyIlwI9g2go6AeP+kGHk7SBLi9HPC2
# lUAOZshg2cND+mjJQtSHBUP10ajZknYDCwg/GpO2s+v87hYTevNbLulbjw/IfSAC
# teGZvbRnYsT4/FXGosaUX4BHFnGH4hkIg9jgNMKIvXofoYIS/jCCEvoGCisGAQQB
# gjcDAwExghLqMIIS5gYJKoZIhvcNAQcCoIIS1zCCEtMCAQMxDzANBglghkgBZQME
# AgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIIYvAHPCDoyswKo8TY4bIQHONOYQcxGM5d9Z+p4p
# xos+AgZg1KBTSzcYEzIwMjEwNzA4MTkxOTM1LjMyN1owBIACAfSggdikgdUwgdIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046OEQ0MS00QkY3LUIzQjcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2Wggg5NMIIE+TCCA+GgAwIBAgITMwAAATqNjTH3d0lJ
# wgAAAAABOjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yMDEwMTUxNzI4MjJaFw0yMjAxMTIxNzI4MjJaMIHSMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
# SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjhENDEtNEJGNy1CM0I3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzl8k518P
# lz8JTIXYn/O9OakqcWqdJ8ZXJhAks9hyLB8+ANW7Zngb1t7iw7TmgeooOwMnbhCQ
# QH14UwWd8hQFWexKqVpcIFnY3b15+PYmgVeQ4XKfWJ3PPMjTiXu73epXHj9XX7mh
# S2IVqwEvDOudOI3yQL8D8OOG24b+10zDDEyN5wvZ5A1Wcvl2eQhCG61GeHNaXvXO
# loTQblVFbMWOmGviHvgRlRhRjgNmuv1J2y6fQFtiEw0pdXKCQG68xQlBhcu4Ln+b
# YL4HoeT2mrtkpHEyDZ+frr+Ka/zUDP3BscHkKdkNGOODfvJdWHaV0Wzr1wnPuUgt
# ObfnBO0oSjIpBQIDAQABo4IBGzCCARcwHQYDVR0OBBYEFBRWoJ8WXxJrpslvHHWs
# rQmFRfPLMB8GA1UdIwQYMBaAFNVjOlyKMZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRP
# ME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1
# Y3RzL01pY1RpbVN0YVBDQV8yMDEwLTA3LTAxLmNybDBaBggrBgEFBQcBAQROMEww
# SgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMv
# TWljVGltU3RhUENBXzIwMTAtMDctMDEuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0l
# BAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQELBQADggEBAF435D6kAS2jeAJ8BG1K
# Tm5Az0jpbdjpqSvMLt7fOVraAEHldgk04BKcTmhzjbTXsjwgCMMCS+jX4Toqi0cn
# zcSoD2LphZA98DXeH6lRH7qQdXbHgx0/vbq0YyVkltSTMv1jzzI75Z5dhpvc4Uwn
# 4Fb6CCaF2/+r7Rr0j+2DGCwl8aWqvQqzhCJ/o7cNoYUfJ4WSCHs1OsjgMmWTmglu
# PIxt3kV8iLZl2IZgyr5cNOiNiTraFDq7hxI16oDsoW0EQKCV84nV1wWSWe1SiAKI
# wr5BtqYwJ+hlocPw5qehWbBiTLntcLrwKdAbwthFr1DHf3RYwFoDzyNtKSB/TJsB
# 2bMwggZxMIIEWaADAgECAgphCYEqAAAAAAACMA0GCSqGSIb3DQEBCwUAMIGIMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNy
# b3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0xMDA3MDEy
# MTM2NTVaFw0yNTA3MDEyMTQ2NTVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqR0NvHcRijog7PwT
# l/X6f2mUa3RUENWlCgCChfvtfGhLLF/Fw+Vhwna3PmYrW/AVUycEMR9BGxqVHc4J
# E458YTBZsTBED/FgiIRUQwzXTbg4CLNC3ZOs1nMwVyaCo0UN0Or1R4HNvyRgMlhg
# RvJYR4YyhB50YWeRX4FUsc+TTJLBxKZd0WETbijGGvmGgLvfYfxGwScdJGcSchoh
# iq9LZIlQYrFd/XcfPfBXday9ikJNQFHRD5wGPmd/9WbAA5ZEfu/QS/1u5ZrKsajy
# eioKMfDaTgaRtogINeh4HLDpmc085y9Euqf03GS9pAHBIAmTeM38vMDJRF1eFpwB
# BU8iTQIDAQABo4IB5jCCAeIwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFNVj
# OlyKMZDzQ3t8RhvFM2hahW1VMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsG
# A1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJc
# YmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9z
# b2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIz
# LmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0
# MIGgBgNVHSABAf8EgZUwgZIwgY8GCSsGAQQBgjcuAzCBgTA9BggrBgEFBQcCARYx
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL1BLSS9kb2NzL0NQUy9kZWZhdWx0Lmh0
# bTBABggrBgEFBQcCAjA0HjIgHQBMAGUAZwBhAGwAXwBQAG8AbABpAGMAeQBfAFMA
# dABhAHQAZQBtAGUAbgB0AC4gHTANBgkqhkiG9w0BAQsFAAOCAgEAB+aIUQ3ixuCY
# P4FxAz2do6Ehb7Prpsz1Mb7PBeKp/vpXbRkws8LFZslq3/Xn8Hi9x6ieJeP5vO1r
# VFcIK1GCRBL7uVOMzPRgEop2zEBAQZvcXBf/XPleFzWYJFZLdO9CEMivv3/Gf/I3
# fVo/HPKZeUqRUgCvOA8X9S95gWXZqbVr5MfO9sp6AG9LMEQkIjzP7QOllo9ZKby2
# /QThcJ8ySif9Va8v/rbljjO7Yl+a21dA6fHOmWaQjP9qYn/dxUoLkSbiOewZSnFj
# nXshbcOco6I8+n99lmqQeKZt0uGc+R38ONiU9MalCpaGpL2eGq4EQoO4tYCbIjgg
# tSXlZOz39L9+Y1klD3ouOVd2onGqBooPiRa6YacRy5rYDkeagMXQzafQ732D8OE7
# cQnfXXSYIghh2rBQHm+98eEA3+cxB6STOvdlR3jo+KhIq/fecn5ha293qYHLpwms
# ObvsxsvYgrRyzR30uIUBHoD7G4kqVDmyW9rIDVWZeodzOwjmmC3qjeAzLhIp9cAv
# VCch98isTtoouLGp25ayp0Kiyc8ZQU3ghvkqmqMRZjDTu3QyS99je/WZii8bxyGv
# WbWu3EQ8l1Bx16HSxVXjad5XwdHeMMD9zOZN+w2/XU/pnR4ZOC+8z1gFLu8NoFA1
# 2u8JJxzVs341Hgi62jbb01+P3nSISRKhggLXMIICQAIBATCCAQChgdikgdUwgdIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046OEQ0MS00QkY3LUIzQjcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAAclkdn1j1gXgdyvYj41
# B8rkNZ4IoIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJ
# KoZIhvcNAQEFBQACBQDkkZNJMCIYDzIwMjEwNzA4MjMwNzUzWhgPMjAyMTA3MDky
# MzA3NTNaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOSRk0kCAQAwCgIBAAICEPIC
# Af8wBwIBAAICEUowCgIFAOSS5MkCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYB
# BAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOB
# gQAPRY6xjNjMuBp2LHLMm8do0q13DXiPxhpNOFw00nPf2S4NGRv9QImLEFov48wz
# oghDdXnxOGTPjbQEBpSl5AZS0nyOwsSKUxxj/JHXSuDTSF6wVtUkCBVBj2BY5yeW
# Y4CXRo9FMFKjoXB+zOSn+GS+SQ3FtDgHDC0u1LF8LYXX5DGCAw0wggMJAgEBMIGT
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABOo2NMfd3SUnCAAAA
# AAE6MA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQ
# AQQwLwYJKoZIhvcNAQkEMSIEIBKZNDLwHVdAnJo8qa167NgvALYFF/wk9TnkF+9j
# yyzOMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgn6/QhAepLF/7Bdsvfu8G
# OT+ihL9c4cgo5Nf1aUN8tG0wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAATqNjTH3d0lJwgAAAAABOjAiBCDbEdAZcom5bztKqzVKMUNK
# AMesjn+KEVR3GXOIEUoZMzANBgkqhkiG9w0BAQsFAASCAQCF9Qb/vnqKKgAsNqfb
# SV3L73Oqs/s7LX8lvqimvECBPKUWcUu2+eceEB0itYGTDQKTpSLIBwymqRkkEdqr
# yH2GddZbD1oJtnIXt/cCSxJjzUUGVuj3H1Fk5a2N5P9MUlIYry81Z9plRUhHBukD
# 3Xv8BVbxigQXjKt94bINNPsLaP6gD1+QJUVvYvpX7aRnGJRXYKCATt0pJ6vMFPLU
# bpIqD0LBF5/ksQMJKWH+fzRI6iY3tIIHb2Yfbcby/xVRha98gZWQQCayg8gfOXXr
# XxNXQP06ONNXB0Ek4qtFA/HnBg6jnlcUBrmLNziDfHsvky/wgIaqP8oqzUZjkLK+
# qgr3
# SIG # End signature block
