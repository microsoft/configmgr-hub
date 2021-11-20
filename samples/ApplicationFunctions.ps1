function New-ScopeID {
    
    $GetSiteID = $odata.ExecuteMethod("wmi/SMS_Identification.GetSiteId", "{}");
    
    $SiteID   = $GetSiteID["SiteID"].StringValue;
    $SiteID   = $SiteID.Replace("{","").Replace("}","").ToUpper();
    $ScopeID  = "ScopeId_$($SiteID)";

    return $ScopeID
}

function New-Application {
    param (
        [string]$Name,
        [string]$Description
    )

    Add-Type -Path "$ENV:SMS_ADMIN_UI_PATH\..\Microsoft.ConfigurationManagement.ApplicationManagement.dll";
    $scopeId = New-ScopeId;

    $objectId = New-Object -TypeName "Microsoft.ConfigurationManagement.ApplicationManagement.ObjectId" -ArgumentList @($scopeId,([System.Guid]::NewGuid().ToString().ToUpper()),1);
 
    $app = New-Object -TypeName "Microsoft.ConfigurationManagement.ApplicationManagement.Application" -ArgumentList $objectId;
    $app.Name = $Name;
    $app.Title = $Name;
    $app.Description = $Description;
    
    $displayInfo = New-Object -TypeName "Microsoft.ConfigurationManagement.ApplicationManagement.AppDisplayInfo";
    $displayInfo.Title = $Name;
    $displayInfo.Description = $Description;
    $displayInfo.Language = (Get-Culture).Name
    
    $app.DisplayInfo.Add($displayInfo);


    $appXml = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::SerializeToString($app);

    $body = @{
        "SDMPackageXML" = $appXml;
    }
    
    Invoke-CMPost -odata $odata -body $body -query "wmi/SMS_Application";
}

$odata = Connect-CMAdminService;
New-Application -Name "Test" -Description "Description";