function New-Application {
    param (
        [string]$Name,
        [string]$Description
    )

    Add-Type -Path "$ConsoleDir\Microsoft.ConfigurationManagement.ApplicationManagement.dll";
 
    $app = New-Object -TypeName "Microsoft.ConfigurationManagement.ApplicationManagement.Application";
    app.Name = $Name;
    app.Description = $Description;
    
    $displayInfo = New-Object -TypeName "Microsoft.ConfigurationManagement.ApplicationManagement.AppDisplayInfo";
    $displayInfo.Title = $Name;
    $displayInfo.Description = $Description;
    $displayInfo.Language = (Get-Culture).Name
    
    app.DisplayInfo.Add(displayInfo);


    $appXml = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::Serialize($app);

    $body = @{
        "SDMPackageXML" = @($appXml);
    }
    
    Invoke-CMPost -odata Connect-CMAdminService -body $body -query "wmi/SMS_Application";
}

New-Application -Name "Test" -Description "Description";