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
        $OptionIndex = 0
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
if($ENV:SMS_ADMIN_UI_PATH -eq $null)
{
    Write-Host "Unable to locate Configuration Manager Console on this machine. Please run this script on a machine where Configuration Manager Console is installed."
    exit
}

$ConsoleDir = "$ENV:SMS_ADMIN_UI_PATH\.."

# Try to find Site Server
[bool]$IsSiteServerFound = $false
if($(Get-WmiObject -Query "SELECT * FROM __Namespace WHERE Name = `"SMS`"" -Namespace "root") -ne $null)
{
    $FoundSiteServerPath = [System.Net.Dns]::GetHostByName(($ENV:ComputerName)).HostName
    if($FoundSiteServerPath -ne $null)
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
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
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
$ParentSiteCode = (Get-WmiObject -Query "SELECT ParentSiteCode FROM SMS_SCI_SiteDefinition WHERE SiteServerName=`"$SiteServerPath`"" -Namespace "root\sms\site_$SiteCode" –ComputerName $ProviderMachineName) | Select-Object -ExpandProperty ParentSiteCode
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

    $AllSources = (Get-WmiObject -Query "SELECT DISTINCT moduleName FROM SMS_StatMsgModuleNames" -Namespace "root\sms\site_$SiteCode" –ComputerName $ProviderMachineName) | Select-Object -Property ModuleName
    $SourceRes = PromptUser -Message "Source:" -Options ($AllSources.ModuleName)
    
    $AllSiteCodes = (Get-WmiObject -Query "SELECT DISTINCT SiteCode FROM SMS_ComponentSummarizer" -Namespace "root\sms\site_$SiteCode" –ComputerName $ProviderMachineName) | Select-Object -Property SiteCode
    $SiteCodeRes = PromptUser -Message "Site Code:" -Options ($AllSiteCodes.SiteCode)

    $AllSystems = (Get-WmiObject -Query "SELECT DISTINCT MachineName FROM SMS_ComponentSummarizer" -Namespace "root\sms\site_$SiteCode" –ComputerName $ProviderMachineName) | Select-Object -Property MachineName
    $SystemRes = PromptUser -Message "System:" -Options ($AllSystems.MachineName)
    
    $AllComponents = (Get-WmiObject -Query "SELECT DISTINCT ComponentName FROM SMS_ComponentSummarizer ORDER BY ComponentName" -Namespace "root\sms\site_$SiteCode" –ComputerName $ProviderMachineName) | Select-Object -Property ComponentName
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
            -Namespace "root\sms\site_$SiteCode" –ComputerName $ProviderMachineName) | Select-Object -ExpandProperty AttributeID

        Add-Type -Path "$ConsoleDir\Microsoft.ConfigurationManagement.ManagementProvider.dll"
        $AttributeResourceAssemblyDescription = New-Object -TypeName "Microsoft.ConfigurationManagement.AdminConsole.Schema.AssemblyDescription"
        $AttributeResourceAssemblyDescription.AssemblyPath="$ConsoleDir\AdminUI.UIResources.dll"
        $AttributeResourceAssemblyDescription.AssemblyType="Microsoft.ConfigurationManagement.AdminConsole.UIResources.SMS_StatusMessage-AttributeID.resources"

        $AllPropertyName = @{}
        foreach($PropertyItem in $AllProperties)
        {
            $AllPropertyName.Add([Microsoft.ConfigurationManagement.AdminConsole.Common.UtilityClass]::GetStringFromAssembly($AttributeResourceAssemblyDescription, $PropertyItem), [string]($PropertyItem))
        }

        $PropertyRes = PromptUser -Message "Property:" -Options (($AllPropertyName.Keys) | sort)

        if($PropertyRes.Item1 -ne 0)
        {
            $SelectedPropertyId = $AllPropertyName[$PropertyRes.Item2]
            $AllPropertyValues = (Get-WmiObject -Query "SELECT DISTINCT att.AttributeValue FROM SMS_StatusMessage AS stat INNER JOIN SMS_StatMsgAttributes AS att ON stat.RecordID = att.RecordID WHERE stat.moduleName = `"$($SourceRes.Item2)`" AND att.AttributeID = $SelectedPropertyId ORDER BY att.AttributeValue" `
                -Namespace "root\sms\site_$SiteCode" –ComputerName $ProviderMachineName) | Select-Object -ExpandProperty AttributeValue
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