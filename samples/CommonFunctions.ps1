# This function expects console to be installed
$ConsoleDir = "$ENV:SMS_ADMIN_UI_PATH\.."

function Connect-CMAdminService {

    $WqlConnectionManager = Get-WmiConnectionManager
    $ProviderMachineName = $WqlConnectionManager.NamedValueDictionary["ProviderMachineName"];

    # Create ODataConnectionManager to communicate with AdminService
    Add-Type -Path "$ConsoleDir\AdminUI.ODataQueryEngine.dll"
    $ODataConnectionManager = New-Object -TypeName "Microsoft.ConfigurationManagement.ManagementProvider.ODataQueryEngine.ODataConnectionManager" -ArgumentList $WqlConnectionManager.NamedValueDictionary,$WqlConnectionManager
    [void]($ODataConnectionManager.Connect($ProviderMachineName))

    return $ODataConnectionManager;
}

function Get-WmiConnectionManager {
    
    # Get the provider machine - add server name if remote from the site server
    $AllProviderLocations=Get-WmiObject -Query "SELECT * FROM SMS_ProviderLocation" -Namespace "root\sms"
    foreach($ProviderLocation in $AllProviderLocations)
    {
        $ProviderMachineName = $ProviderLocation.Machine

        # Pick first provider
        break;
    }

    Add-Type -Path "$ConsoleDir\AdminUI.WqlQueryEngine.dll"
    $WqlConnectionManager = New-Object -TypeName "Microsoft.ConfigurationManagement.ManagementProvider.WqlQueryEngine.WqlConnectionManager"
    [void]($WqlConnectionManager.Connect($ProviderMachineName))

    return $WqlConnectionManager;
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

    $jsonBody = (ConvertTo-Json $body);

    # Enable this to troubleshoot POST issues
    # Write-Host ($odata.BaseUrl + $query)
    # Write-Host $jsonBody

    # This path takes care of admin service communication for intranet scenarios, both HTTPS and Enhanced HTTP (no PKI cert required)
    $results = $odata.ODataServiceCaller.ExecutePost($odata.BaseUrl + $query, $null, $jsonBody);
    if ($null -ne $results)
    {
        return ($results.ToString() | ConvertFrom-Json);
    }
    return $null;

    # Using invoke REST method, for the intranet scenario, requires PKI cert bound to the port, but the same method can be used for token auth scenarios
    # $uri = $odata.BaseUrl + $query;
    # return (Invoke-RestMethod -Method Post -Uri $uri -UseDefaultCredentials -Body $jsonBody -ContentType "application/json");
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

function Invoke-CMApplicationOnDemandInstall {
    param (
        [string]$CIGUID,
        [string]$SMSID
    )

    $uri = "v1.0/Application($($CIGUID))/AdminService.InstallApplication"
    $body = @{
        "Devices" = @($SMSID);
        "InstallationType" = 1;
    }
    
    $odata = Connect-CMAdminService
    Invoke-CMPost $odata $uri $body
}

function Get-CMScript {
    $uri = "wmi/SMS_Scripts";
    $odata = Connect-CMAdminService
    Invoke-CMGet $odata $uri
}

function New-CMScript {
    param (
        [string]$Name,
        [string]$ScriptText
    )

    $scriptGuid = [System.Guid]::NewGuid().ToString().ToUpper();
    [Byte[]]$scriptByteArray = [Text.Encoding]::Unicode.GetPreamble();
    $scriptByteArray+=[Text.Encoding]::Unicode.GetBytes($ScriptText);
    $scriptBody = [Convert]::ToBase64String($scriptByteArray);
    $uri = "wmi/SMS_Scripts.CreateScripts";
    $body = @{
        "ParamsDefinition" = "";
        "ScriptName" = $Name;
        "Author" = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name;
        "Script" = $scriptBody;
        "ScriptVersion" = "1";
        "ScriptType" = 0; # Powershell
        "ParameterlistXML" = "";
        "ScriptGuid" = $scriptGuid;
    };
    
    $odata = Connect-CMAdminService
    Invoke-CMPost $odata $uri $body
}

function Approve-CMScript {
    param (
        [string]$ScriptGuid,
        [string]$Comments = ""
    )

    $uri = "wmi/SMS_Scripts/$($ScriptGuid)/AdminService.UpdateApprovalState";
    $body = @{
        "Approver" = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name;
        "ApprovalState" = "3"; #Approved
        "Comment" = $Comments;
    };
    
    $odata = Connect-CMAdminService
    Invoke-CMPost $odata $uri $body
}

function Invoke-CMRunScript {
    param (
        [string]$ScriptGuid,
        [int]$ResourceId
    )

    $uri = "v1.0/Device($($ResourceId))/AdminService.RunScript"
    $body = @{
        "ScriptGuid" = $ScriptGuid;
    }
    
    $odata = Connect-CMAdminService
    Invoke-CMPost $odata $uri $body
}


function Get-CMScriptResult {
    param (
        [int]$ResourceId,
        [int]$OperationId
    )

    $uri = "v1.0/Device($($ResourceId))/AdminService.ScriptResult(OperationId=$($OperationId))"
    
    $odata = Connect-CMAdminService
    Invoke-CMGet $odata $uri
}

function Invoke-WaitScriptResult {
    param (
        [int]$ResourceId,
        [int]$OperationId
    )

    $startTime = [System.DateTime]::Now;
    $status = 0;
    while ($status -eq 0)
    {
        try 
        {
            $scriptResult = Get-CMScriptResult -ResourceId $ResourceId -OperationId $operationId
            $status = $scriptResult.Status
            Write-Host "Script completed in $(([System.DateTime]::Now - $startTime).TotalSeconds) seconds."
            Write-Host "Script result: $($scriptResult.Result)."
        }
        catch
        {
            # 404 from this API means script result is not found yet. Need to improve looking for specific status code rather than catch all. 
            $status = 0 # still waiting for result
            Write-Host "Waiting for the device to report script result..."
            Start-sleep 5
        }
    
        # Need to time out eventually, wait 1 minute
        $currentTime = [System.DateTime]::Now
        if (($currentTime - $startTime).TotalSeconds -ge 60)
        {
            Write-Host "Timed out waiting for script result"
            $status = 2
        }
    }
}



# Additional troubleshooting notes
# For each admin service request, there will be corresponding entry in AdminService.log. Look at the URI and check if it is valid.
# For WMI methods, there are two different types - static and instance methods. Either mof (wmi definition) or $metadata will show the type of method.
#    Static methods are triggered directly based on the class, such as AdminService/wmi/WMIClassName.MethodName
#    Instance methods are triggered with id of the instance, such as AdminService/wmi/WmiClassName/id/AdminService.MethodName
# One of the ways to pull in WMI metadata of admin service:
# https://admin_service_fqdn/AdminService/wmi/$metadata
# If you are stuck getting 404 when calling WMI method, follow these steps:
#     Capture URI and Json POST body (add Write-Host debug line in Invoke-CMPost method)
#     Use a tool such as Fiddler or Invoke-RestMethod to make POST request manually using URI and body
#     Look at the error details in the response. Error message should point to either incorrect entity / method name OR incorrect value/type of the parameters to the method (such as int vs string)
