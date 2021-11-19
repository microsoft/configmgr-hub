# Plug in admin service FQDN
$ServerName = ""

function Connect-CMAdminService {

    # Get the provider machine
    $AllProviderLocations=Get-WmiObject -Query "SELECT * FROM SMS_ProviderLocation" -Namespace "root\sms"
    foreach($ProviderLocation in $AllProviderLocations)
    {
        $SiteCode = $ProviderLocation.SiteCode
        $ProviderMachineName = $ProviderLocation.Machine

        # Pick first provider
        break;
    }
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