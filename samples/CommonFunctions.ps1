function Connect-CMAdminService {

    # Get the provider machine - add server name if remote from the site server
    $AllProviderLocations=Get-WmiObject -Query "SELECT * FROM SMS_ProviderLocation" -Namespace "root\sms"
    foreach($ProviderLocation in $AllProviderLocations)
    {
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
    Add-Type -Path "$ConsoleDir\AdminUI.ODataQueryEngine.dll"
    $ODataConnectionManager = New-Object -TypeName "Microsoft.ConfigurationManagement.ManagementProvider.ODataQueryEngine.ODataConnectionManager" -ArgumentList $WqlConnectionManager.NamedValueDictionary,$WqlConnectionManager
    [void]($ODataConnectionManager.Connect($ProviderMachineName))

    return $ODataConnectionManager;
}

function Invoke-CMGet {
    param (
        $odata,
        $query
    )

    # Use OData connection manager

    # This path takes care of admin service communication for intranet scenarios, both HTTPS and Enhanced HTTP (no PKI cert required)
    $results = $odata.ODataServiceCaller.ExecuteGetQuery($odata.BaseUrl + $query, $null);
    if ($null -ne $results)
    {
        return ($results.ToString() | ConvertFrom-Json).value;
    }
    return $null;

    # Using invoke REST method, for the intranet scenario, requires PKI cert bound to the port, but the same method can be used for token auth scenarios
    # $uri = $odata.BaseUrl + $query;
    # return (Invoke-RestMethod -Method Get -Uri $uri -UseDefaultCredentials).value;
}

function Invoke-CMPost {
    param (
        $odata,
        $query,
        $body
    )

    # This path takes care of admin service communication for intranet scenarios, both HTTPS and Enhanced HTTP (no PKI cert required)
    $jsonBody = (ConvertTo-Json $body);
    $results = $odata.ODataServiceCaller.ExecutePost($odata.BaseUrl + $query, $null, $jsonBody);
    if ($null -ne $results)
    {
        return ($results.ToString() | ConvertFrom-Json);
    }
    return $null;

    # Using invoke REST method, for the intranet scenario, requires PKI cert bound to the port, but the same method can be used for token auth scenarios
    # $uri = $odata.BaseUrl + $query;
    # return (Invoke-RestMethod -Method Post -Uri $uri -UseDefaultCredentials -Body (ConvertTo-Json $body) -ContentType "application/json");
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

function Get-CMApplication {
    $uri = "v1.0/Application";
    $odata = Connect-CMAdminService
    Invoke-CMGet $odata $uri
}

function Invoke-CMApplicationInstall {
    param (
        [string]$CIGUID,
        [string]$SMSID
    )

    $uri = "v1.0/Application($($CIGUID))/AdminService.InstallApplication"
    $body = @{
        "Devices" = @($SMSID);
    }
    
    $odata = Connect-CMAdminService
    Invoke-CMPost $odata $uri $body
}

function Invoke-CMApplicationUninstall {
    param (
        [string]$CIGUID,
        [string]$SMSID
    )

    $uri = "v1.0/Application($($CIGUID))/AdminService.UninstallApplication"
    $body = @{
        "Devices" = @($SMSID);
    }
    
    $odata = Connect-CMAdminService
    Invoke-CMPost $odata $uri $body
}
