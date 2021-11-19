function Connect-CMAdminService {

    # Get the provider machine - add server name if remote from the site server
    $AllProviderLocations=Get-WmiObject -Query "SELECT * FROM SMS_ProviderLocation" -Namespace "root\sms"
    foreach($ProviderLocation in $AllProviderLocations)
    {
        $SiteCode = $ProviderLocation.SiteCode
        $ProviderMachineName = $ProviderLocation.Machine

        # Pick first provider
        break;
    }

    # This function expects console to be installed
    $ConsoleDir = "$ENV:SMS_ADMIN_UI_PATH\.."

    Add-Type -Path "$ConsoleDir\AdminUI.WqlQueryEngine.dll"
    $WqlConnectionManager = New-Object -TypeName "Microsoft.ConfigurationManagement.ManagementProvider.WqlQueryEngine.WqlConnectionManager"
    [void]($WqlConnectionManager.Connect($ProviderMachineName))

    # Create ODataConnectionManager to communicate with AdminService
    $NamedValuesDictionary = New-Object -TypeName "Microsoft.ConfigurationManagement.ManagementProvider.SmsNamedValuesDictionary"
    $NamedValuesDictionary["ConnectedSiteCode"] = $SiteCode
    $NamedValuesDictionary["ProviderMachineName"] = $ProviderMachineName
    Add-Type -Path "$ConsoleDir\AdminUI.ODataQueryEngine.dll"
    $ODataConnectionManager = New-Object -TypeName "Microsoft.ConfigurationManagement.ManagementProvider.ODataQueryEngine.ODataConnectionManager" -ArgumentList $NamedValuesDictionary,$WqlConnectionManager
    [void]($ODataConnectionManager.Connect($ProviderMachineName))

    return $ODataConnectionManager;
}

function Invoke-CMGet {
    param (
        $odata,
        $query
    )

    # Doesn't appear to work as desired
    # $results = $odata.ExecuteMethod($query);
    # return $results.PropertyList["value"] | ConvertFrom-Json;

    # Using invoke REST method for now, requires SSL cert bound to the port
    $uri = $odata.BaseUrl + $query;
    return (Invoke-RestMethod -Method Get -Uri $uri -UseDefaultCredentials).value;
}

function Invoke-CMPost {
    param (
        $odata,
        $query,
        $body
    )

    # Doesn't appear to work as desired
    # return $odata.ExecuteMethod($query, $body);
    $uri = $odata.BaseUrl + $query;
    return (Invoke-RestMethod -Method Post -Uri $uri -UseDefaultCredentials -Body (ConvertTo-Json $body) -ContentType "application/json");
}

function Get-CMDevice {
    
    $uri = "v1.0/Device";
    $odata = Connect-CMAdminService
    Invoke-CMGet $odata $uri
}


function New-CMCollection {
    param (
        [string]$Name,
        [int]$Type = 2, # 1 = user, 2 = device
        [string]$Comment = ""
    )

    $uri = "wmi/SMS_Collection";
    $body = @{
        CollectionType = $Type;
        Comment = $Comment;
        LimitToCollectionID = "SMS00001";
        Name = $Name
    };
    
    $odata = Connect-CMAdminService
    Invoke-CMPost $odata $uri $body
}

function Add-CMCollectionMember {
    param (
        [string]$CollectionID,
        [int]$ResourceID,
        [string]$RuleName = "Test Rule"
    )

    # This only works in the more recent Tech Preview builds (2110+)
    $uri = "wmi/SMS_Collection/$($CollectionID)/AdminService.AddMembershipRule"
    $body = @{
        "collectionRule" = @{
            "@odata.type"="#AdminService.SMS_CollectionRuleDirect";
            ResourceClassName="SMS_R_System";
            RuleName=$RuleName;
            ResourceID=$ResourceID
        }
    }
    
    $odata = Connect-CMAdminService
    Invoke-CMPost $odata $uri $body
}

# Sample usage

# Create a collection and add device as direct member
$collection = New-CMCollection -Name "Test Collection 1"
$device = (Get-CMDevice)[0]
Add-CMCollectionMember -CollectionID $collection.CollectionID -ResourceID $device.MachineId -RuleName "Direct member $($device.Name)"


