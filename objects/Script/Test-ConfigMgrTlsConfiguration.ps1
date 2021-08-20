#************************************************************************************************************
# Disclaimer
#
# This sample script is not supported under any Microsoft standard support program or service. This sample
# script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties
# including, without limitation, any implied warranties of merchantability or of fitness for a particular
# purpose. The entire risk arising out of the use or performance of this sample script and documentation
# remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation,
# production, or delivery of this script be liable for any damages whatsoever (including, without limitation,
# damages for loss of business profits, business interruption, loss of business information, or other
# pecuniary loss) arising out of the use of or inability to use this sample script or documentation, even
# if Microsoft has been advised of the possibility of such damages.
#
# Source: https://github.com/jonasatgit/scriptrepo/tree/master/Security
#************************************************************************************************************
# Changelog:
# 20210412: Minor changes
# 20201126: Updated Get-SQLServerConnectionString 
# 20201126: Changed Test-SiteRole
# 20201125: Added "$statusObj.OverallTestStatus = "No ConfigMgr system detected. No tests performed."" for non ConfigMgr systems.

																																
<#
.Synopsis
    Script to validate the neccesary prerequisites to enforce TLS 1.2 in a ConfigMgr environment
.DESCRIPTION
    Every test based on the following article:
    https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/security/enable-tls-1-2-server

    The tests in a nutshell:
    Site servers (central, primary, or secondary)
    - Update .NET Framework (Version prüfen)
     - - NET Framework 4.6.2 and later supports TLS 1.1 and TLS 1.2. Confirm the registry settings, but no additional changes are required.
     - - Update NET Framework 4.6 and earlier versions to support TLS 1.1 and TLS 1.2. For more information, see .NET Framework versions and dependencies.
     - - If you're using .NET Framework 4.5.1 or 4.5.2 on Windows 8.1 or Windows Server 2012, the relevant updates and details are also available from the Download Center.
    - Verify strong cryptography settings (Registry settings)

    Site database server	
    - Update SQL Server and its client components. Version: "11.*.7001.0"
    - Microsoft SQL Server 2016 and later support TLS 1.1 and TLS 1.2. Earlier versions and dependent libraries might require updates. For more information, see KB 3135244: TLS 1.2 support for Microsoft SQL Server.

    - SQL Server 2014 SP3 is the SQL supported service pack at the moment. Version: 12.0.6024.0
    - SQL Server 2012 SP4 is the SQL supported service pack at the moment. Version: 11.0.7001.0
    - SQL Server 2016 and above is okay: 13.0.1601.5

    Secondary site servers 
    - Update SQL Server and it's client components to a compliant version of SQL Express
    - Secondary site servers need to use at least SQL Server 2016 Express with Service Pack 2 (13.2.5026.0) or later.

    Site system roles (also SMS Provider)
    - Update .NET Framework 
    - Verify strong cryptography settings
    - Update SQL Server and its client components on roles that require it, including the SQL Server Native Client

    Reporting services point
    - Update .NET Framework on the site server, the SQL Reporting Services servers, and any computer with the console
    - Restart the SMS_Executive service as necessary
    - Check SQL Version

    Software update point
    - Update WSUS
    - For WSUS server that's running Windows Server 2012, install update 4022721 or a later rollup update.
    - For WSUS server that's running Windows Server 2012 R2, install update 4022720 or a later rollup update

    Cloud management gateway
    - Enforce TLS 1.2 (check console setting)

    Configuration Manager console	
    - Update .NET Framework
    - Verify strong cryptography settings

    Configuration Manager client with HTTPS site system roles
    - Update Windows to support TLS 1.2 for client-server communications by using WinHTTP

    Software Center
    - Update .NET Framework
    - Verify strong cryptography settings

    Windows 7 clients
    - Before you enable TLS 1.2 on any server components, update Windows to support TLS 1.2 for client-server communications by using WinHTTP. If you enable TLS 1.2 on server components first, you can orphan earlier versions of clients.
.EXAMPLE
    Test-ConfigMgrTlsConfiguration.ps1
.EXAMPLE
    Test-ConfigMgrTlsConfiguration.ps1 -Infomode
.EXAMPLE
    Test-ConfigMgrTlsConfiguration.ps1 -Infomode -Verbose
.EXAMPLE
    Test-ConfigMgrTlsConfiguration.ps1 -CipherChecks
.LINK
    https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/security/enable-tls-1-2-server
.LINK 
    https://github.com/jonasatgit/scriptrepo/tree/master/Security
    
#>


#region Parameters / Prereqs
[CmdletBinding()]
param
(
    [switch]$InfoMode,
    [switch]$CipherChecks
)

$commandName = $MyInvocation.MyCommand.Name

#Ensure that the Script is running with elevated Permissions
if(-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Warning 'The script needs admin rights to run. Start PowerShell with administrative rights and run the script again'
    return 
}
#endregion


#region Test-SQLClientVersion
<#
.Synopsis
   Test-SQLClientVersion
.DESCRIPTION
   Minor versions schould not be checked, since the minor version varies: "11.*.7001.0"
   Major  Minor  Build  Revision
   -----  -----  -----  --------
   11     *      7001   0  
.EXAMPLE
   Test-SQLClientVersion
.EXAMPLE
   Test-SQLClientVersion -MinSQLClientVersion '11.4.7462.6'
.EXAMPLE
   Test-SQLClientVersion -Verbose
#>
function Test-SQLClientVersion
{
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [version]$MinSQLClientVersion = "11.4.7004.0"
    )

    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    Write-Verbose "$commandName`: https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/security/enable-tls-1-2-server#bkmk_sql"

    $outObj = New-Object -TypeName psobject | Select-Object -Property  InstalledVersion, MinRequiredVersion, TestResult
    $outObj.MinRequiredVersion = $MinSQLClientVersion.ToString()
    Write-Verbose "$commandName`: Minimum SQL ClientVersion: $($MinSQLClientVersion.ToString())"
    $SQLNCLI11RegPath = "HKLM:SOFTWARE\Microsoft\SQLNCLI11"
    If (Test-Path $SQLNCLI11RegPath)
    {
        [version]$InstalledVersion = (Get-ItemProperty $SQLNCLI11RegPath -ErrorAction SilentlyContinue)."InstalledVersion"
        if ($InstalledVersion)
        {
            $outObj.InstalledVersion = $InstalledVersion.ToString()
            # leaving minor version out
            Write-Verbose "$commandName`: Installed SQL ClientVersion: $($InstalledVersion.ToString())"
            if (($InstalledVersion.Major -ge $MinSQLClientVersion.Major) -and ($InstalledVersion.Build -ge $MinSQLClientVersion.Build) -and ($InstalledVersion.Revision -ge $MinSQLClientVersion.Revision))
            {
                $outObj.TestResult = $true
                return $outObj
            }
            else
            {
                Write-Verbose "$commandName`: Versions doen't match"
                $outObj.TestResult = $false
                return $outObj
            }
        }
        else
        {
            Write-Verbose "$commandName`: No SQL client version found in registry"
            $outObj.TestResult = $false
            return $outObj
        } 
    }
    else
    {
        Write-Verbose "$commandName`: RegPath not found `"$SQLNCLI11RegPath`""
        $outObj.TestResult = $false
        return $outObj
    }
}
#endregion

#region Test-NetFrameworkVersion
<#
.Synopsis
   Test-NetFrameworkVersion
.DESCRIPTION
   #
.EXAMPLE
   Test-NetFrameworkVersion
.EXAMPLE
   Test-NetFrameworkVersion -MinNetFrameworkRelease 393295
.EXAMPLE
   Test-NetFrameworkVersion -Verbose
#>
function Test-NetFrameworkVersion
{
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [int32]$MinNetFrameworkRelease = 393295
    )

    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    Write-Verbose "$commandName`: https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/security/enable-tls-1-2-server#bkmk_net"

    $outObj = New-Object -TypeName psobject | Select-Object -Property InstalledVersion, MinRequiredVersion, TestResult
    $outObj.MinRequiredVersion = $MinNetFrameworkRelease

    Write-Verbose "$commandName`: Minimum .Net Framework release: $MinNetFrameworkRelease"
    $NetFrameWorkRegPath = "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\"
    If (Test-Path $NetFrameWorkRegPath)
    {
        [int32]$ReleaseRegValue = (Get-ItemProperty $NetFrameWorkRegPath -ErrorAction SilentlyContinue).Release
        if ($ReleaseRegValue)
        {
            $outObj.InstalledVersion = $ReleaseRegValue
            Write-Verbose "$commandName`: Installed .Net Framework release: $MinNetFrameworkRelease"
            if ($ReleaseRegValue -ge $MinNetFrameworkRelease)
            {
                $outObj.TestResult = $true
                return $outObj
            }
            else
            {
                Write-Verbose "$commandName`: Versions doen't match"
                $outObj.TestResult = $false
                return $outObj
            }
            
        }
        else
        {
            Write-Verbose "$commandName`: No .Net version found in registry"
            $outObj.TestResult = $false
            return $outObj
        }
        
    }
    else
    {
        Write-Verbose "$commandName`: RegPath not found `"$NetFrameWorkRegPath`""
        $outObj.TestResult = $false
        return $outObj
    }
}
#endregion

#region Test-NetFrameworkSettings
<#
.Synopsis
   Test-NetFrameworkSettings
.DESCRIPTION
   #
.EXAMPLE
   Test-NetFrameworkSettings
.EXAMPLE
   Test-NetFrameworkSettings -Verbose
#>
function Test-NetFrameworkSettings
{
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    Write-Verbose "$commandName`: https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/security/enable-tls-1-2-server#bkmk_net"

    [array]$dotNetVersionList = @('v2.0.50727','v4.0.30319')
    [array]$regPathPrefixList = @('HKLM:\SOFTWARE\Microsoft\.NETFramework','HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework')

    [bool]$expectedValuesSet = $true
    foreach ($dotNetVersion in $dotNetVersionList)
    {
        foreach ($regPathPrefix in $regPathPrefixList)
        {
            $regPath = "{0}\{1}" -f $regPathPrefix, $dotNetVersion
            Write-Verbose "$commandName`: Working on: `"$regPath`""
            $regProperties = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            if ($regProperties)
            {
                Write-Verbose "$commandName`: SystemDefaultTlsVersions = $($regProperties.SystemDefaultTlsVersions)"
                Write-Verbose "$commandName`: SchUseStrongCrypto = $($regProperties.SchUseStrongCrypto)"
                if (($regProperties.SystemDefaultTlsVersions -ne 1) -and ($regProperties.SchUseStrongCrypto -ne 1))
                {
                    $expectedValuesSet = $false
                    Write-Verbose "$commandName`: Wrong settings"
                }   
                else
                {
                    Write-Verbose "$commandName`: Settings okay"
                }        
            }
            else
            {
                $expectedValuesSet = $false
                Write-Verbose "$commandName`: No values found"
            }
        }
    }
    return $expectedValuesSet
}
#endregion

#region Test-SQLServerVersion
<#
.Synopsis
   Test-SQLServerVersion
.DESCRIPTION
    - Microsoft SQL Server 2016 and later support TLS 1.1 and TLS 1.2. Earlier versions and dependent libraries might require updates. 
      For more information, see KB 3135244: TLS 1.2 support for Microsoft SQL Server.
    - SQL Server 2014 SP3 is the only supported SP at the moment. Version: 12.0.6024.0
    - SQL Server 2012 SP4 is the only supported SP at the moment. Version: 11.0.7001.0
    - SQL Server 2016 and above is okay: 13.0.1601.5
    - Secondary site servers need to use at least SQL Server 2016 Express with Service Pack 2 (13.2.5026.0) or later.

    Using EngineEdition (int) to detect SQL Express
    1 = Personal or Desktop Engine (Not available in SQL Server 2005 (9.x) and later versions.)
    2 = Standard (This is returned for Standard, Web, and Business Intelligence.)
    3 = Enterprise (This is returned for Evaluation, Developer, and Enterprise editions.)
    4 = Express (This is returned for Express, Express with Tools, and Express with Advanced Services)
    5 = SQL Database
    6 = Microsoft Azure Synapse Analytics (formerly SQL Data Warehouse)
    8 = Azure SQL Managed Instance
    9 = Azure SQL Edge (this is returned for both editions of Azure SQL Edge

.EXAMPLE
   Test-SQLServerVersion
.EXAMPLE
   Test-SQLServerVersion -Verbose
#>
function Test-SQLServerVersion
{
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [string]$SQLServerName
    )

    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    Write-Verbose "$commandName`: https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/security/enable-tls-1-2"
    Write-Verbose "$commandName`: For SQL Express: https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/security-and-privacy-for-site-administration#update-sql-server-express-at-secondary-sites"
    $outObj = New-Object -TypeName psobject | Select-Object -Property InstalledVersion, MinRequiredVersion, TestResult

    $connectionString = "Server=$SQLServerName;Database=master;Integrated Security=True"
    Write-Verbose "$commandName`: Connecting to SQL: `"$connectionString`""
    $SqlQuery = "Select SERVERPROPERTY('ProductVersion') as 'Version', SERVERPROPERTY('EngineEdition') as 'EngineEdition'"
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $connectionString
    $SqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandText = $SqlQuery
    $SqlAdapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter
    Write-Verbose "$commandName`: Running Query: `"$SqlQuery`""
    $SqlAdapter.SelectCommand = $SqlCmd
    $ds = New-Object -TypeName System.Data.DataSet
    $SqlAdapter.Fill($ds) | Out-Null
    $SQLOutput = $ds.Tables[0]
    $SqlCmd.Dispose()
    [version]$SQLVersion = $SQLOutput.Version
    [int]$SQLEngineEdition = $SQLOutput.EngineEdition
    Write-Verbose "$commandName`: SQL EngineEdition: $SQLEngineEdition"
    Write-Verbose "$commandName`: SQL Version:$($SQLVersion.ToString())"
    $outObj.InstalledVersion = $SQLVersion.ToString()

    if ($SQLVersion -and $SQLEngineEdition)
    {
        switch ($SQLVersion.Major)
        {
            11 
            {
                [version]$minSQLVersion = '11.0.7001.0' #SQL Server 2012 SP4
                Write-Verbose "$commandName`: Minimum version for SQL Server 2012 SP4: $($minSQLVersion.ToString())"
            }

            12 
            {
                [version]$minSQLVersion = '12.0.6024.0' #SQL Server 2014 SP3
                Write-Verbose "$commandName`: Minimum version for SQL Server 2014 SP3: $($minSQLVersion.ToString())"
            }

            13 
            {
                if ($SQLEngineEdition -eq 4) # 4 = Express Edition
                {
                    [version]$minSQLVersion = '13.2.5026.0' # SQL Server 2016 SP2 Express and higher
                    Write-Verbose "$commandName`: Minimum version for SQL Server 2016 SP2 Express and higher: $($minSQLVersion.ToString())"
                }
                else
                {
                    [version]$minSQLVersion = '13.0.1601.5' #SQL Server 2016 and higher
                    Write-Verbose "$commandName`: Minimum version for SQL Server 2016 and higher: $($minSQLVersion.ToString())"
                }
            }
            
            Default
            {
                [version]$minSQLVersion = '14.0.0.0' #SQL Server 2017 and higher
                Write-Verbose "$commandName`: Minimum version for SQL Server 2017 and higher: $($minSQLVersion.ToString())"         
            }
        } # end switch

        $outObj.MinRequiredVersion = $minSQLVersion.ToString()
        if ($SQLVersion -ge $minSQLVersion)
        {
            $outObj.TestResult = $true
            return $outObj
        }
        else
        {
            $outObj.TestResult = $false
            return $outObj
        } 

    }
    else
    {
        Write-Verbose "$commandName`: Failed to get SQL version and EngineEdition!"
        $outObj.TestResult = $False
        return $outObj
    }
}
#endregion

#region Test-WSUSVersion
<#
.Synopsis
   Test-WSUSVersion
.DESCRIPTION
   #
.EXAMPLE
   Test-WSUSVersion
.EXAMPLE
   Test-WSUSVersion -Verbose
#>
function Test-WSUSVersion
{
    [CmdletBinding()]
    [OutputType([object])]
    param()

    $commandName = $MyInvocation.MyCommand.Name
    # only applicable to Server 2012 or 2012 R2, higher versions are TLS 1.2 capable
    # https://docs.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem
    Write-Verbose "$commandName`: "
    Write-Verbose "$commandName`: https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/security/enable-tls-1-2" 
    Write-Verbose "$commandName`: Getting OS version"
    $wmiQuery = "SELECT * FROM Win32_OperatingSystem WHERE ProductType<>'1'"
    Write-Verbose "$commandName`: Get-WmiObject -Namespace `"root\cimv2`" `"$wmiQuery`""

    $serverOS = Get-WmiObject -Namespace "root\cimv2" -query "$wmiQuery" -ErrorAction SilentlyContinue
    if ($serverOS)
    {
        [version]$serverOSVersion = $serverOS.Version
        Write-Verbose "$commandName`: Server OS version: $($serverOSVersion.ToString())"
    }

    $outObj = New-Object -TypeName psobject | Select-Object -Property InstalledVersion, MinRequiredVersion, TestResult, Info
    
    Write-Verbose "$commandName`: Getting WsusService.exe version"    
    $regPath = "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup"
    $wsusServiceEntries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue 
    if ($wsusServiceEntries)
    {
        $WsusServicePath = "{0}{1}" -f ($wsusServiceEntries.TargetDir), "Services\WsusService.exe"
        $WsusServiceFile = Get-Item $WsusServicePath -ErrorAction SilentlyContinue
        [version]$WsusServiceFileVersion = $WsusServiceFile.VersionInfo.FileVersion
        Write-Verbose "$commandName`: WsusService.exe version: $($WsusServiceFileVersion.ToString())"
        $outObj.InstalledVersion = $WsusServiceFileVersion.ToString()

        if($wsusServiceEntries.UsingSSL -ne 1)
        {
            Write-Verbose "$commandName`: WSUS configuration not following best practices. SSL should be enabled. UsingSSL = $($wsusServiceEntries.UsingSSL)"
            $outObj.Info = "WSUS configuration not following best practices. SSL should be enabled."
        }   

        # only applicable to Server 2012 or 2012 R2, higher versions are TLS 1.2 capable
        $majorMinor = "{0}.{1}" -f ($WsusServiceFileVersion.Major), ($WsusServiceFileVersion.Minor)

        switch ($majorMinor)
        {
            '6.0' # Windows Server 2008
            {
                [version]$minWsusServiceVersion = '0.0'
                $outObj.MinRequiredVersion = $minWsusServiceVersion.ToString()
            }
            '6.1' # Windows Server 2008 R2
            {
                [version]$minWsusServiceVersion = '0.0'
                $outObj.MinRequiredVersion = $minWsusServiceVersion.ToString()
            }
            '6.2' # Windows Server 2012
            {
                [version]$minWsusServiceVersion = '6.2.9200.22167'
                $outObj.MinRequiredVersion = $minWsusServiceVersion.ToString()

            }
            '6.3' # Windows Server 2012 R2
            {
                [version]$minWsusServiceVersion = '6.3.9600.18694'
                $outObj.MinRequiredVersion = $minWsusServiceVersion.ToString()

            }
            '10.0' # Windows Server 2016 and higher
            {
                [version]$minWsusServiceVersion =  '10.0'
                $outObj.MinRequiredVersion = $minWsusServiceVersion.ToString()
            }
            Default
            {
                Write-Verbose "$commandName`:Unknown OS version: $majorMinor"
                [version]$minWsusServiceVersion = '999.0' # making sure nothing is higher
                $outObj.MinRequiredVersion = $minWsusServiceVersion.ToString()
            }
        }

        if($WsusServiceFileVersion -ge $minWsusServiceVersion)
        {
            $outObj.TestResult = $true
            return $outObj
        }
        else
        {
            $outObj.TestResult = $false
            return $outObj
        }

    }
}
#endregion

#region Test-CMGSettings
<#
.Synopsis
   Test-CMGSettings
.DESCRIPTION
   #
.EXAMPLE
   Test-CMGSettings
.EXAMPLE
   Test-CMGSettings -Verbose
#>
function Test-CMGSettings
{
    [CmdletBinding()]
    [OutputType([bool])]
    param()


    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    [bool]$expectedValuesSet = $true
    # getting sitecode first
    $query = 'Select SiteCode From SMS_ProviderLocation Where ProviderForLocalSite=1'
    Write-Verbose "$commandName`: Running: `"$query`""
    try
    {
        $SiteCode = Get-WmiObject -Namespace "root\sms" -Query $query -ErrorAction Stop | Select-Object -ExpandProperty SiteCode 
    }
    catch 
    {
        Write-Warning "$commandName Not able to get sitecode: $_"
        return 
    }
    Write-Verbose "$commandName`: SiteCode: $SiteCode"
    # getting cmg info
    $query = "SELECT * FROM SMS_AzureService WHERE ServiceType = 'CloudProxyService'"
    Write-Verbose "$commandName`: Running: `"$query`""
    [array]$azureServices = Get-WmiObject -Namespace "root\sms\site_$SiteCode" -Query $query
    if ($azureServices)
    {
        $azureServices | ForEach-Object {
        
            if (-NOT($_.ClientCertRevocationEnabled))
            {
                Write-Verbose "$commandName`: CMG not using certificate best practices. ClientCertRevocationEnabled = $($_.ClientCertRevocationEnabled)"
            }

            if($_.ProxySecurityProtocol -eq 3072)
            {
                Write-Verbose "$commandName`: CMG `"$($_.Name)`" set to enforce TLS 1.2"
            }
            else
            {
                Write-Verbose "$commandName`: CMG `"$($_.Name)`" not set to enforce TLS 1.2"
                $expectedValuesSet = $false          
            }
         }
    }
    else
    {
        Write-Verbose "$commandName`: No Cloud Management Gateway (CMG) found!"
        return
    }
    
    if (-NOT($expectedValuesSet))
    {
        Write-verbose "$commandName`: https://docs.microsoft.com/en-us/mem/configmgr/core/clients/manage/cmg/setup-cloud-management-gateway"
        return $false
    }
    else
    {
        return $true
    }
}
#endregion

#region Test-WinHTTPSettings
<#
.Synopsis
   Test-WinHTTPSettings
.DESCRIPTION
   Windows 8.1, Windows Server 2012 R2, Windows 10, Windows Server 2016, and later versions of Windows natively support TLS 1.2 
   for client-server communications over WinHTTP. 
   Earlier versions of Windows, such as Windows 7 or Windows Server 2012, don't enable TLS 1.1 or TLS 1.2 by default for secure 
   communications using WinHTTP. For these earlier versions of Windows, install Update 3140245 to enable the registry values below, 
   which can be set to add TLS 1.1 and TLS 1.2 to the default secure protocols list for WinHTTP. With the patch installed, create the following registry values:
   HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp\
   DefaultSecureProtocols = (DWORD): 0xAA0
   HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp\
   DefaultSecureProtocols = (DWORD): 0xAA0
   https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/security/enable-tls-1-2-client#bkmk_winhttp
.EXAMPLE
   Test-WinHTTPSettings
.EXAMPLE
   Test-WinHTTPSettings -Verbose
#>
function Test-WinHTTPSettings
{
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $commandName = $MyInvocation.MyCommand.Name
    #Write-Verbose "$commandName`: "
    # Check for update: http://support.microsoft.com/kb/3140245
    # in quickfixengineering 
    # plus reg key check

}
#endregion

#region Test-SCHANNELKeyExchangeAlgorithms
<#
.Synopsis
   Test-SCHANNELKeyExchangeAlgorithms
.DESCRIPTION
   # https://docs.microsoft.com/en-us/dotnet/framework/network-programming/tls#configuring-schannel-protocols-in-the-windows-registry
   # https://docs.microsoft.com/en-us/troubleshoot/windows-server/windows-security/restrict-cryptographic-algorithms-protocols-schannel
.EXAMPLE
   Test-SCHANNELKeyExchangeAlgorithms
.EXAMPLE
   Test-SCHANNELKeyExchangeAlgorithms -Verbose
#>
function Test-SCHANNELKeyExchangeAlgorithms
{
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    Write-Verbose "$commandName`: https://docs.microsoft.com/en-us/troubleshoot/windows-server/windows-security/restrict-cryptographic-algorithms-protocols-schannel"
    
    $desiredKeyExchangeAlgorithmStates = [ordered]@{
        "Diffie-Hellman" = "Enabled"; 
        "PKCS" = "Enabled"; 
        "ECDH" = "Enabled"; 
    }
    $DiffieHellmanServerMinKeyBitLength = 2048

    $expectedValuesSet = $true
    $desiredKeyExchangeAlgorithmStates.GetEnumerator() | ForEach-Object {
        
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms\{0}" -f ($_.Name)
        Write-Verbose "$commandName`: Working on: `"$regPath`""
        $regProperties = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
        if ($regProperties)
        {
            $enabledValue = if ($_.Value -eq 'Enabled'){4294967295}else{0} # enabled is decimal 4294967295 or hex 0xffffffff

            if ($_.Name -eq 'Diffie-Hellman')
            {
                if ($regProperties.ServerMinKeyBitLength -ne $DiffieHellmanServerMinKeyBitLength)
                {
                    Write-Verbose "$commandName`: Diffie-Hellman ServerMinKeyBitLength is set to: $($regProperties.ServerMinKeyBitLength)" 
                    Write-Verbose "$commandName`: Expected value: $DiffieHellmanServerMinKeyBitLength"
                    $expectedValuesSet = $false
                }
                else
                {
                    Write-Verbose "$commandName`: Diffie-Hellman ServerMinKeyBitLength is set correctly to: $($regProperties.ServerMinKeyBitLength)"    
                }
            }


            Write-Verbose "$commandName`: Enabled = $($regProperties.Enabled)"
            if ($regProperties.Enabled -ne $enabledValue)
            {
                $expectedValuesSet = $false
                Write-Verbose "$commandName`: Wrong settings"
            }
            else
            {
                Write-Verbose "$commandName`: Settings okay"
            }  

        }
        else
        {
            $expectedValuesSet = $false
            Write-Verbose "$commandName`: No values found"
        }
   
    }
    return $expectedValuesSet
}
#endregion

#region Test-SCHANNEHashes
<#
.Synopsis
   Test-SCHANNEHashes
.DESCRIPTION
   # https://docs.microsoft.com/en-us/dotnet/framework/network-programming/tls#configuring-schannel-protocols-in-the-windows-registry
   # https://docs.microsoft.com/en-us/troubleshoot/windows-server/windows-security/restrict-cryptographic-algorithms-protocols-schannel
.EXAMPLE
   Test-SCHANNEHashes
.EXAMPLE
   Test-SCHANNEHashes -Verbose
#>
function Test-SCHANNELHashes
{
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    Write-Verbose "$commandName`: https://docs.microsoft.com/en-us/troubleshoot/windows-server/windows-security/restrict-cryptographic-algorithms-protocols-schannel"

    $desiredHashStates = [ordered]@{
        "SHA256" = "Enabled"; 
        "SHA384" = "Enabled"; 
        "SHA512" = "Enabled"; 
    }

    $expectedValuesSet = $true
    $desiredHashStates.GetEnumerator() | ForEach-Object {
        
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes\{0}" -f ($_.Name)
        Write-Verbose "$commandName`: Working on: `"$regPath`""
        $regProperties = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if ($regProperties)
        {
            $enabledValue = if ($_.Value -eq 'Enabled'){4294967295}else{0} # enabled is decimal 4294967295 or hex 0xffffffff

            Write-Verbose "$commandName`: Enabled = $($regProperties.Enabled)"
            if ($regProperties.Enabled -ne $enabledValue)
            {
                $expectedValuesSet = $false
                Write-Verbose "$commandName`: Wrong settings"
            }
            else
            {
                Write-Verbose "$commandName`: Settings okay"
            }  

        }
        else
        {
            $expectedValuesSet = $false
            Write-Verbose "$commandName`: No values found"
        }     
    }
    return $expectedValuesSet
}
#endregion

#region Test-SCHANNECiphers
<#
.Synopsis
   Test-SCHANNECiphers
.DESCRIPTION
   # https://docs.microsoft.com/en-us/dotnet/framework/network-programming/tls#configuring-schannel-protocols-in-the-windows-registry
   # https://docs.microsoft.com/en-us/troubleshoot/windows-server/windows-security/restrict-cryptographic-algorithms-protocols-schannel
.EXAMPLE
   Test-SCHANNECiphers
.EXAMPLE
   Test-SCHANNECiphers -Verbose
#>
function Test-SCHANNELCiphers
{
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    Write-Verbose "$commandName`: https://docs.microsoft.com/en-us/troubleshoot/windows-server/windows-security/restrict-cryptographic-algorithms-protocols-schannel"

    $desiredCipherStates = [ordered]@{
        "NULL" = "Disabled"; 
        "DES 56/56" = "Disabled"; 
        "RC2 40/128" = "Disabled"; 
        "RC2 56/128" = "Disabled"; 
        "RC2 128/128" = "Disabled";
        "RC4 40/128" = "Disabled";
        "RC4 56/128" = "Disabled";
        "RC4 64/128" = "Disabled";
        "RC4 128/128" = "Disabled";
        "Triple DES 168" = "Disabled"; # Sweet32 birthday attack 
        "AES 128/128" = "Enabled";
        "AES 256/256" = "Enabled"
    }

    $expectedValuesSet = $true
    $desiredCipherStates.GetEnumerator() | ForEach-Object {
        
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\{0}" -f ($_.Name)
        Write-Verbose "$commandName`: Working on: `"$regPath`""
        $regProperties = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if ($regProperties)
        {
            $enabledValue = if ($_.Value -eq 'Enabled'){4294967295}else{0} # enabled is decimal 4294967295 or hex 0xffffffff

            Write-Verbose "$commandName`: Enabled = $($regProperties.Enabled)"
            if ($regProperties.Enabled -ne $enabledValue)
            {
                $expectedValuesSet = $false
                Write-Verbose "$commandName`: Wrong settings"
            }
            else
            {
                Write-Verbose "$commandName`: Settings okay"
            }  

        }
        else
        {
            $expectedValuesSet = $false
            Write-Verbose "$commandName`: No values found"
        }     
    }
    return $expectedValuesSet
}
#endregion

#region Test-CipherSuites
<#
.Synopsis
   Test-CipherSuites
.DESCRIPTION
   # https://docs.microsoft.com/en-us/troubleshoot/windows-server/windows-security/restrict-cryptographic-algorithms-protocols-schannel
   # https://docs.microsoft.com/en-us/windows/win32/secauthn/cipher-suites-in-schannel
    
    IMPORTANT:
    Cipher suites can only be negotiated for TLS versions which support them. The highest supported TLS version is always preferred in the TLS handshake.

    Example cipher suite string:
    TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384_P384
    ECDHE       = Key Exchnage
    ECDSA       = Signature
    AES_256_GCM = Bulk Encryption (Cypther)
    SHA384      = Message Authentication
    P384        = Elliptic Curve (only attached to the string in older OS versions)
.EXAMPLE
   Test-CipherSuites
.EXAMPLE
   Test-CipherSuites -Verbose
#>
function Test-CipherSuites
{
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory=$true)]
        [version]$OSVersion
    )

    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    Write-Verbose "$commandName`: https://docs.microsoft.com/en-us/windows/win32/secauthn/cipher-suites-in-schannel"

    Write-Verbose "$commandName`: Using cipher suites for OS version $($OSVersion.ToString())" 
    $desiredCipherSuiteStates = [ordered]@{}
    switch ($OSVersion.Build)
    {
        '9200' # Window 8 and Windows Server 2012
        {


        }
        '9600' # Windows 8.1 and Server 2012 R2
        {


        }
        '10586' # Windows 10 1511
        {


        }
        '14393' # Windows 10 1607 and Windows Server 2016 
        {
            $desiredCipherSuiteStates = [ordered]@{
                    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384" = "Enabled";
                    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256" = "Enabled";
                    "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384" = "Enabled";
                    "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256" = "Enabled";
                    "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA" = "Enabled";
                    "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA" = "Enabled";
                    "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384" = "Enabled";
                    "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256" = "Enabled";
                    "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384" = "Enabled";
                    "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256" = "Enabled";
                    "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA" = "Enabled";
                    "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA" = "Enabled";
                    "TLS_RSA_WITH_AES_256_GCM_SHA384" = "Enabled";
                    "TLS_RSA_WITH_AES_128_GCM_SHA256" = "Enabled";
                    "TLS_RSA_WITH_AES_256_CBC_SHA256" = "Enabled";
                    "TLS_RSA_WITH_AES_128_CBC_SHA256" = "Enabled";
                    "TLS_RSA_WITH_AES_256_CBC_SHA" = "Enabled";
                    "TLS_RSA_WITH_AES_128_CBC_SHA" = "Enabled";
                    "TLS_DHE_RSA_WITH_AES_256_GCM_SHA384" = "Disabled";
                    "TLS_DHE_RSA_WITH_AES_128_GCM_SHA256" = "Disabled";
                    "TLS_DHE_RSA_WITH_AES_256_CBC_SHA" = "Disabled";
                    "TLS_DHE_RSA_WITH_AES_128_CBC_SHA" = "Disabled";
                    "TLS_RSA_WITH_3DES_EDE_CBC_SHA" = "Disabled";
                    "TLS_DHE_DSS_WITH_AES_256_CBC_SHA256" = "Disabled";
                    "TLS_DHE_DSS_WITH_AES_128_CBC_SHA256" = "Disabled";
                    "TLS_DHE_DSS_WITH_AES_256_CBC_SHA" = "Disabled";
                    "TLS_DHE_DSS_WITH_AES_128_CBC_SHA" = "Disabled";
                    "TLS_DHE_DSS_WITH_3DES_EDE_CBC_SHA" = "Disabled";
                    "TLS_RSA_WITH_RC4_128_SHA" = "Disabled";
                    "TLS_RSA_WITH_RC4_128_MD5" = "Disabled";
                    "TLS_RSA_WITH_NULL_SHA256" = "Disabled";
                    "TLS_RSA_WITH_NULL_SHA" = "Disabled";
                    "TLS_PSK_WITH_AES_256_GCM_SHA384" = "Disabled";
                    "TLS_PSK_WITH_AES_128_GCM_SHA256" = "Disabled";
                    "TLS_PSK_WITH_AES_256_CBC_SHA384" = "Disabled";
                    "TLS_PSK_WITH_AES_128_CBC_SHA256" = "Disabled";
                    "TLS_PSK_WITH_NULL_SHA384" = "Disabled";
                    "TLS_PSK_WITH_NULL_SHA256" = "Disabled"
                }
        }
        '15063' # Windows 10 1703
        {


        }
        '16299' # Windows 10 1709
        {


        }
        '17134' # Windows 10 1803
        {


        }
        '17763' # Windows 10 1809 and Server 2019
        {


        }
        '18362' # Windows 10 1903
        {


        }
        '18363' # Windows 10 1909
        {


        }
        '19041' # Windows 10 2004
        {


        }
        Default
        {
            Write-Verbose "$commandName`:Unknown OS version or client OS!"
            return
        }
    }

    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002"
    
    if ($desiredCipherSuiteStates)
    {
        # building string from hashtable, because the value ist stored that way in the registry
        # the hashtable is just an easy way of ordering and enabling or disabling cipher suites
        [string]$desiredCipherSuiteStateString = ""
        $desiredCipherSuiteStates.GetEnumerator() | ForEach-Object {

            if ($_.Value -eq 'Enabled')
            {
                $desiredCipherSuiteStateString += "{0}," -f $_.Name
            }
        }
        #removing last comma
        $desiredCipherSuiteStateString = $desiredCipherSuiteStateString -replace '.$'

        Write-Verbose "$commandName`: Cipher suite order can be adjusted using the following registry path."
        Write-Verbose "$commandName`: IMPORTANT: the value is just an example and you might need to adjust the values for your environment."
        Write-Verbose "$commandName`: Path: `"$regPath`""
        Write-Verbose "$commandName`: REG_SZ: `"Functions`""
        Write-Verbose "$commandName`: Value: `"$desiredCipherSuiteStateString`""


        # getting current cipher suite configuration
        # IMPORTANT: only working on Windows 10 1607 and Windows Server 2016 or higher
        [array]$currentCipherSuites = Get-TlsCipherSuite -ErrorAction SilentlyContinue
        if (-NOT($currentCipherSuites))
        {
            Write-Verbose "$commandName`: No cipher suite settings found with: `"Get-TlsCipherSuite`""
            return $false
        }
        else
        {
            # list of active cipher suites has to have the same entry count as the desired state
            $enabledCipherSuites = $desiredCipherSuiteStates.GetEnumerator() | Where-Object {$_.Value -eq 'Enabled'}
            if(-NOT($currentCipherSuites.Count -eq  $enabledCipherSuites.Count))
            {
                Write-Verbose "$commandName`: Current cipherSuites not in desired state"
                return $false
            }
            else
            {
                # checking cipher suite order

                $i = 0
                $desiredStateSet = $true
                $enabledcipherSuites | ForEach-Object {
                    if (-NOT($_.Name -eq $currentcipherSuites[$i].Name))
                    {
                        $desiredStateSet = $false
                    }
                    $i++
                }
                if ($desiredStateSet)
                {
                    Write-Verbose "$commandName`: cipher suite order set as desired"
                    return $true
                }
                else
                {
                    Write-Verbose "$commandName`: cipher suite order NOT set as desired"
                    return $false
                }
            }     
        }
    }
    else
    {
        return
    } # end of "if ($desiredCipherSuiteStates)"
}
#endregion


#region Test-SCHANNELSettings
<#
.Synopsis
   Test-SCHANNELSettings
.DESCRIPTION
   # https://docs.microsoft.com/en-us/dotnet/framework/network-programming/tls#configuring-schannel-protocols-in-the-windows-registry
   # https://docs.microsoft.com/en-us/troubleshoot/windows-server/windows-security/restrict-cryptographic-algorithms-protocols-schannel
.EXAMPLE
   Test-SCHANNELSettings
.EXAMPLE
   Test-SCHANNELSettings -Verbose
#>
function Test-SCHANNELSettings
{
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    Write-Verbose "$commandName`: https://docs.microsoft.com/en-us/troubleshoot/windows-server/windows-security/restrict-cryptographic-algorithms-protocols-schannel"

    $desiredProtocolStates = [ordered]@{
        "SSL 2.0" = "Disabled"; # Disabled, will automatically validate DisabledByDefault with the opposite value, to ensure the same settings
        "SSL 3.0" = "Disabled"; # Disabled, will automatically validate DisabledByDefault with the opposite value, to ensure the same settings
        "TLS 1.0" = "Disabled"; # Disabled, will automatically validate DisabledByDefault with the opposite value, to ensure the same settings
        "TLS 1.1" = "Disabled"; # Disabled, will automatically validate DisabledByDefault with the opposite value, to ensure the same settings
        "TLS 1.2" = "Enabled"  # Enabled, will automatically validate DisabledByDefault with the opposite value, to ensure the same settings
    }

    [array]$subKeyCollection = ("Client","Server")
    [bool]$expectedValuesSet = $true

    $desiredProtocolStates.GetEnumerator() | ForEach-Object {

        foreach ($subKey in $subKeyCollection)
        {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\{0}\{1}" -f ($_.Name), $subKey
            Write-Verbose "$commandName`: Working on: `"$regPath`""
            $regProperties = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
            if ($regProperties)
            {
                $disabledByDefaultValue = if ($_.Value -eq 'Disabled'){1}else{0} 

                $enabledValue = if ($_.Value -eq 'Enabled'){1}else{0} # enabled is 1

                Write-Verbose "$commandName`: DisabledByDefault = $($regProperties.DisabledByDefault)"
                Write-Verbose "$commandName`: Enabled = $($regProperties.Enabled)"
                # both values schould be set
                if (($regProperties.DisabledByDefault -ne $disabledByDefaultValue) -or ($regProperties.Enabled -ne $enabledValue))
                {
                    $expectedValuesSet = $false
                    Write-Verbose "$commandName`: Wrong settings"
                }
                else
                {
                    Write-Verbose "$commandName`: Settings okay"
                }  

            }
            else
            {
                $expectedValuesSet = $false
                Write-Verbose "$commandName`: No values found"
            }
        }
    }
    return $expectedValuesSet
}
#endregion

#region Get-OSTypeInfo
<#
.Synopsis
   Get-OSTypeInfo
.DESCRIPTION
   Get-OSTypeInfo
.EXAMPLE
   Get-OSTypeInfo
.EXAMPLE
   Get-OSTypeInfo -Verbose
#>
function Get-OSTypeInfo
{
    [CmdletBinding()]
    [OutputType([object])]
    param()

    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    Write-Verbose "$commandName`: Getting OS type information"
    $wmiQuery = "SELECT * FROM Win32_OperatingSystem"
    Write-Verbose "$commandName`: Get-WmiObject -Namespace `"root\cimv2`" `"$wmiQuery`""
    $Win32OperatingSystem = Get-WmiObject -Namespace "root\cimv2" -query "$wmiQuery" -ErrorAction SilentlyContinue
    if ($Win32OperatingSystem)
    {
        switch ($Win32OperatingSystem.ProductType)
        {
            1 {$Win32OperatingSystem | Add-Member -Name 'ProductTypeName' -Value 'Workstation' -MemberType NoteProperty}
            2 {$Win32OperatingSystem | Add-Member -Name 'ProductTypeName' -Value 'Domain Controller' -MemberType NoteProperty}
            3 {$Win32OperatingSystem | Add-Member -Name 'ProductTypeName' -Value 'Server' -MemberType NoteProperty}
            Default {}
        }
        return $Win32OperatingSystem | Select-Object -Property Caption, Version, ProductType, ProductTypeName
    }
    else
    {
        return $false
    }
}
#endregion

#region Test-SiteServer
function Test-SiteServer
{
   return (Get-Service -Name 'SMS_EXECUTIVE' -ErrorAction SilentlyContinue) -and (Get-Service -Name 'SMS_SITE_COMPONENT_MANAGER' -ErrorAction SilentlyContinue) -and ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\SMS\Identification' -Name 'Site Type' -ErrorAction SilentlyContinue).'Site Type' -ne 2)
}
#endregion

#region Test-SecondarySite
function Test-SecondarySite 
{
   return (Get-Service -Name 'SMS_EXECUTIVE' -ErrorAction SilentlyContinue) -and (Get-Service -Name 'SMS_SITE_COMPONENT_MANAGER' -ErrorAction SilentlyContinue) -and ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\SMS\Identification' -Name 'Site Type' -ErrorAction SilentlyContinue).'Site Type' -eq 2)
}
#endregion

#region Test-SiteRole 
function Test-SiteRole 
{
    if (Get-Service -Name 'SMS_EXECUTIVE' -ErrorAction SilentlyContinue)
    {
        return $true
    }
}
#endregion

#region Test-ReportingServicePoint 
function Test-ReportingServicePoint 
{
    return (Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\SMS\Components\SMS_EXECUTIVE\Threads\SMS_SRS_REPORTING_POINT')
}
#endregion

#region Test-SoftwareUpdatePointAndWSUS
function Test-SoftwareUpdatePointAndWSUS
{
  return (Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\SMS\COMPONENTS\SMS_EXECUTIVE\Threads\SMS_WSUS_CONTROL_MANAGER') -and (Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup')
}
#endregion

#region Get-SQLServerConnectionString 
<#
.Synopsis
   Get-SQLServerConnectionString 
.DESCRIPTION
   Get SQL Server Name from specified Role to use in a SQL Server connection string
.EXAMPLE
   Get-SQLServerConnectionString -RoleType SiteServer
#>
function Get-SQLServerConnectionString 
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [ValidateSet("SiteServer", "WSUS", "SSRS", "SecondarySite")]
        [string]$RoleType
    )

    $commandName = $MyInvocation.MyCommand.Name
    Write-Verbose "$commandName`: "
    switch ($RoleType) 
    {
        'SiteServer' 
        { 
            $regPath = "HKLM:\SOFTWARE\Microsoft\SMS\SQL Server"
            $SiteServerEntries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            #DatabaseName can be INST\DB or just DB
            if ($SiteServerEntries.'Database Name'.ToCharArray() -contains "\") 
            {
                $SQLInstance = $SiteServerEntries.'Database Name'.Split("\")
                $ConnectionString = $SiteServerEntries.Server + "\" + $SQLInstance[0]
            }
            else 
            {
                $ConnectionString = $SiteServerEntries.Server
            }
            Write-Verbose "$commandName`: SiteServer SQL is: `"$ConnectionString`""
            return $ConnectionString
        }
        'WSUS' 
        {
            $regPathWSUS = "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup"
            $regPathWID = "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup\Installed Role Services"
            $WSUSServerEntries = Get-ItemProperty -Path $regPathWSUS -ErrorAction SilentlyContinue
            $WIDEntries = Get-ItemProperty -Path $regPathWID -ErrorAction SilentlyContinue
            #Check if WID is used
            if ($WIDEntries.'UpdateServices-Database' -eq 2) 
            {
                Write-Verbose "$commandName`: WSUS SQL is: `"$WSUSServerEntries.SqlServerName`""
                return $WSUSServerEntries.SqlServerName
            }
            else 
            {
                #If WID is installed we don´t need to check the version
                Write-Verbose "$commandName`: WSUS WID found - no need to check SQL Version"
                return $false
            }
        }
        'SecondarySite' 
        {
            $regPath = "HKLM:\SOFTWARE\Microsoft\SMS\SQL Server"
            $SiteServerEntries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            #DatabaseName can be INST\DB or just DB
            if ($SiteServerEntries.'Database Name'.ToCharArray() -contains "\") 
            {
                $SQLInstance = $SiteServerEntries.'Database Name'.Split("\")
                $ConnectionString = $SiteServerEntries.Server + "\" + $SQLInstance[0]
            }
            else 
            {
                $ConnectionString = $SiteServerEntries.Server
            }
            Write-Verbose "$commandName`: Secondary Site SQL is: `"$ConnectionString`""
            return $ConnectionString
        }
        'SSRS' 
        {
            try
            {
                [array]$reportServerList = Get-WmiObject -Namespace "ROOT\Microsoft\SqlServer\ReportServer" -Class "__NAMESPACE" -ErrorAction Stop
                foreach ($reportServerName in $reportServerList.Name) 
                {
                    [array]$reportServerVersionList = Get-WmiObject -Namespace "ROOT\Microsoft\SqlServer\ReportServer\$reportServerName" -Class "__NAMESPACE" -ErrorAction Stop      
        
                    foreach ($reportServerVersion in $reportServerVersionList.Name) 
                    {
                        $query = "SELECT * FROM MSReportServer_ConfigurationSetting"
                        # continue on error in case PowerBI Report server has been installed and an old SSRS entry causes any problems
                        $reportServerConfiguration = Get-WmiObject -Namespace "ROOT\Microsoft\SqlServer\ReportServer\$reportServerName\$reportServerVersion\Admin" -Query $query  -ErrorAction SilentlyContinue
                        if ($reportServerConfiguration) 
                        {
                            Write-Verbose "$commandName`: SSRS SQL is: `"$($reportServerConfiguration.DatabaseServerName)`""
                            Return $reportServerConfiguration.DatabaseServerName
                        }
                    }
                }
            }
            catch
            {
                    Write-Warning "$commandName Not able to read SSRS config: $_"
            } 
        } 
    }
}
#endregion

#region MAIN SCRIPT
$propertiesList = @(
    'OverallTestStatus',
    'OSName', 
    'OSVersion',
    'OSType',
    'IsSiteServer',
    'IsSiteRole',
    'IsReportingServicePoint',
    'IsSUPAndWSUS',
    'IsSecondarySite',
    'TestCMGSettings',
    'TestSQLServerVersionOfSite',
    'TestSQLServerVersionOfWSUS',
    'TestSQLServerVersionOfSSRS',
    'TestSQLServerVersionOfSecSite',
    'TestSQLClientVersion',
    'TestWSUSVersion',
    'TestSCHANNELSettings',
    'TestSCHANNELKeyExchangeAlgorithms',
    'TestSCHANNELHashes',
    'TestSCHANNELCiphers',
    'TestCipherSuites',
    'TestNetFrameworkVersion',
    'TestNetFrameworkSettings' 
    )

$statusObj = New-Object -TypeName psobject | Select-Object -Property $propertiesList


$osInfo = Get-OSTypeInfo

$statusObj.OSName = $osInfo.Caption
$statusObj.OSVersion = $osInfo.Version
$statusObj.OSType = $osInfo.ProductTypeName
$statusObj.IsSiteServer = Test-SiteServer
$statusObj.IsSiteRole = Test-SiteRole
$statusObj.IsReportingServicePoint = Test-ReportingServicePoint
$statusObj.IsSUPAndWSUS = Test-SoftwareUpdatePointAndWSUS
$statusObj.IsSecondarySite = Test-SecondarySite


# different tests based on what type of system we detected 
[bool]$configMgrSystemDetected = $false
if ($statusObj.IsSiteServer)
{
    $configMgrSystemDetected = $true
    Write-Verbose "$commandName`: DETECTED: Site Server"
    $SQLServerConnectionString = Get-SQLServerConnectionString -RoleType SiteServer
    $statusObj.TestSQLServerVersionOfSite = Test-SQLServerVersion -SQLServerName $SQLServerConnectionString
    $statusObj.TestCMGSettings = Test-CMGSettings 
    $statusObj.TestSQLClientVersion = Test-SQLClientVersion
    
}

if ($statusObj.IsSiteRole)
{
    $configMgrSystemDetected = $true
    Write-Verbose "$commandName`: DETECTED: Site role"
    $statusObj.TestSQLClientVersion = Test-SQLClientVersion
}

if ($statusObj.IsSecondarySite)
{
    $configMgrSystemDetected = $true
    Write-Verbose "$commandName`: DETECTED: Secondary Site"
    $SQLServerConnectionString = Get-SQLServerConnectionString -RoleType SecondarySite
    $statusObj.TestSQLServerVersionOfSecSite = Test-SQLServerVersion -SQLServerName $SQLServerConnectionString
    $statusObj.TestSQLClientVersion = Test-SQLClientVersion
}

if ($statusObj.IsSUPAndWSUS)
{
    $configMgrSystemDetected = $true
    Write-Verbose "$commandName`: DETECTED: Software Update Point and WSUS"
    $statusObj.TestWSUSVersion = Test-WSUSVersion 
    $SQLServerConnectionString = Get-SQLServerConnectionString -RoleType WSUS
    if ($SQLServerConnectionString) # only if SQL Server and not WID
    {
        $statusObj.TestSQLServerVersionOfWSUS = Test-SQLServerVersion -SQLServerName $SQLServerConnectionString
    }
}

if ($statusObj.isReportingServicePoint)
{
    $configMgrSystemDetected = $true
    Write-Verbose "$commandName`: DETECTED: Reporting Service Point"
    $SQLServerConnectionString = Get-SQLServerConnectionString -RoleType SSRS
    $statusObj.TestSQLServerVersionOfSSRS = Test-SQLServerVersion -SQLServerName $SQLServerConnectionString
}

# validate tests for all types
if ($statusObj.isSiteServer -or $statusObj.isSiteRole -or $statusObj.isSUPAndWSUS -or $statusObj.isReportingServicePoint -or $statusObj.isSecondarySite -or $statusObj.isServerOS)
{
    $configMgrSystemDetected = $true
    $statusObj.TestSCHANNELSettings = Test-SCHANNELSettings
    $statusObj.TestNetFrameworkVersion = Test-NetFrameworkVersion
    $statusObj.TestNetFrameworkSettings = Test-NetFrameworkSettings
    if ($CipherChecks)
    {
        if(([version]$osInfo.Version).Build -eq 14393)
        {
            $statusObj.TestSCHANNELKeyExchangeAlgorithms = Test-SCHANNELKeyExchangeAlgorithms
            $statusObj.TestSCHANNELHashes = Test-SCHANNELHashes
            $statusObj.TestSCHANNELCiphers = Test-SCHANNELCiphers
            $statusObj.TestCipherSuites = Test-CipherSuites -OSVersion $statusObj.OSVersion
        }
        else
        {
            if ($InfoMode){Write-Warning "$commandName`: Currently -CipherChecks is only working on Windows 10 1607 and Windows Server 2016!"}
        }
    }
}

if ($osInfo.ProductType -eq 1)
{
    # workstation detected
    Write-Verbose "$commandName`: Client detected"
    #Test-WinHTTPSettings
}

# set tests not needed to "true" for the overall check to be passed
$resultTestSCHANNELKeyExchangeAlgorithms = if([string]::IsNullOrEmpty($statusObj.TestSCHANNELKeyExchangeAlgorithms)){$true}else{$statusObj.TestSCHANNELKeyExchangeAlgorithms}
$resultTestSCHANNELHashes = if([string]::IsNullOrEmpty($statusObj.TestSCHANNELHashes)){$true}else{$statusObj.TestSCHANNELHashes}
$resultTestSCHANNELCiphers = if([string]::IsNullOrEmpty($statusObj.TestSCHANNELCiphers)){$true}else{$statusObj.TestSCHANNELCiphers}
$resultTestCipherSuites = if([string]::IsNullOrEmpty($statusObj.TestCipherSuites)){$true}else{$statusObj.TestCipherSuites}
$resultTestSQLServerVersionOfSite = if([string]::IsNullOrEmpty($statusObj.TestSQLServerVersionOfSite.TestResult)){$true}else{$statusObj.TestSQLServerVersionOfSite.TestResult}
$resultTestSQLServerVersionOfSSRS = if([string]::IsNullOrEmpty($statusObj.TestSQLServerVersionOfSSRS.TestResult)){$true}else{$statusObj.TestSQLServerVersionOfSSRS.TestResult}
$resultTestSQLServerVersionOfSecSite = if([string]::IsNullOrEmpty($statusObj.TestSQLServerVersionOfSecSite.TestResult)){$true}else{$statusObj.TestSQLServerVersionOfSecSite.TestResult}
$resultTestSQLClientVersion = if([string]::IsNullOrEmpty($statusObj.TestSQLClientVersion.TestResult)){$true}else{$statusObj.TestSQLClientVersion.TestResult}
$resultTestWSUSVersion = if([string]::IsNullOrEmpty($statusObj.TestWSUSVersion.TestResult)){$true}else{$statusObj.TestWSUSVersion.TestResult}
$resultTestNetFrameworkVersion = if([string]::IsNullOrEmpty($statusObj.TestNetFrameworkVersion.TestResult)){$true}else{$statusObj.TestNetFrameworkVersion.TestResult}
$resultTestNetFrameworkSettings = if([string]::IsNullOrEmpty($statusObj.TestNetFrameworkSettings)){$true}else{$statusObj.TestNetFrameworkSettings}
$resultTestSCHANNELSettings = if([string]::IsNullOrEmpty($statusObj.TestSCHANNELSettings)){$true}else{$statusObj.TestSCHANNELSettings}

# checking overall test state
if ($resultTestSQLServerVersionOfSite `
    -and $resultTestSQLServerVersionOfSSRS `
    -and $resultTestSQLServerVersionOfSecSite `
    -and $resultTestSQLClientVersion `
    -and $resultTestWSUSVersion `
    -and $resultTestNetFrameworkVersion `
    -and $resultTestNetFrameworkSettings `
    -and $resultTestSCHANNELSettings `
    -and $resultTestSCHANNELKeyExchangeAlgorithms `
    -and $resultTestSCHANNELHashes `
    -and $resultTestSCHANNELCiphers `
    -and $resultTestCipherSuites
    )
{
    $statusObj.OverallTestStatus = "Passed"
}
else
{
    $statusObj.OverallTestStatus = "Failed"
}

# override status in case no configMgr system was detected
if (-NOT ($configMgrSystemDetected))
{
    $statusObj.OverallTestStatus = "No ConfigMgr system detected. No tests performed."
}

# show additional information more readable
if ($InfoMode)
{
    Write-Host " "
    if ($osInfo.ProductType -eq 2)
    {
        Write-Warning "Domain Controller detected! Be careful when changing SCHANNEL settings on Domain Controllers!"
    }

    Write-Host "For more information use the -Verbose switch: `"$commandName -InfoMode -Verbose`""
    Write-Host "Or just: `"$commandName -Verbose`""
    Write-Host "Verbose will also output links to each each test to help remediate any wrong configurations"
    Write-Host "For additional Cipher checks use the `"-CipherChecks`" switchS"
    Write-Host " "
    Write-Host "----- OS Type Info -----"
    $statusObj | Select-Object -Property OSName, OSType, OSVersion | Format-List
    Write-Host "----- ConfigMgr Site Info -----"
    Write-Host "This section shows what type of ConfigMgr server was detected if the script was run on a server OS"
    $statusObj | Select-Object -Property IsSiteServer, IsSiteRole, IsReportingServicePoint, IsSUPAndWSUS, IsSecondarySite | Format-List
    Write-Host "----- Testresults -----"
    Write-Host "No entry means the test was not neccesary"
    Write-Host "Each test is based on the following article: https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/security/enable-tls-1-2"
    Write-Host "If you are unsure about Cipher Suite settings talk to your Active Directory and Security department to find the best settings for your environment"
    $statusObj | Select-Object -Property OverallTestStatus,
                                TestCMGSettings,
                                TestSQLServerVersionOfSite,
                                TestSQLServerVersionOfWSUS,
                                TestSQLServerVersionOfSSRS,
                                TestSQLServerVersionOfSecSite,
                                TestSQLClientVersion,
                                TestWSUSVersion,
                                TestSCHANNELSettings,
                                TestSCHANNELKeyExchangeAlgorithms,
                                TestSCHANNELHashes,
                                TestSCHANNELCiphers,
                                TestCipherSuites,
                                TestNetFrameworkVersion,
                                TestNetFrameworkSettings
    
}
else
{
    # output plain object
    $statusObj | Select-Object -Property OverallTestStatus,
                                OSName, 
                                OSVersion,
                                OSType,
                                IsSiteServer, 
                                IsSiteRole, 
                                IsReportingServicePoint, 
                                IsSUPAndWSUS, 
                                IsSecondarySite,
                                TestCMGSettings,
                                @{Name = "TestSQLServerVersionOfSite";Expression = {$_.TestSQLServerVersionOfSite.TestResult}},
                                @{Name = "TestSQLServerVersionOfWSUS";Expression = {$_.TestSQLServerVersionOfWSUS.TestResult}},
                                @{Name = "TestSQLServerVersionOfSSRS";Expression = {$_.TestSQLServerVersionOfSSRS.TestResult}},
                                @{Name = "TestSQLServerVersionOfSecSite";Expression = {$_.TestSQLServerVersionOfSecSite.TestResult}},
                                @{Name = "TestSQLClientVersion";Expression = {$_.TestSQLClientVersion.TestResult}},
                                @{Name = "TestWSUSVersion";Expression = {$_.TestWSUSVersion.TestResult}},
                                TestSCHANNELSettings,
                                TestSCHANNELKeyExchangeAlgorithms,
                                TestSCHANNELHashes,
                                TestSCHANNELCiphers,
                                TestCipherSuites,
                                @{Name = "TestNetFrameworkVersion";Expression = {$_.TestNetFrameworkVersion.TestResult}},
                                TestNetFrameworkSettings
}
#endregion