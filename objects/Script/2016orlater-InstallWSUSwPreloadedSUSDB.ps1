## This script is for lab use and not meant for production environments.
## For use with Windows Server 2016 or later. Windows Server 2012 & 2012R2 or later requires a slightly different script. 
## This script takes a preloaded SUSDB mdf and ldf, attaches it to the local SQl install (default instance).
## Then it installs WSUS and runs a postinstall using c:\wsus as the content dir. 
## Lastly it changes the WSUS Server ID (SUSID in the tbConfigurationA table).
## More info: 
## This script assumes you are using SQL locally with the default instance. Change -ServerInstance to Server1\Instance1 if you're not using the default. 
## This script wasn't written or tested for WID. Here's some general guidance on modifying it:  
## In order to use it for WID, you'd need to install the WID server feature first Install-WindowsFeature Windows-Internal-Database
## Then use the named pipe for WID with SQLCMD to attach the SUSDB you want to use conneciton string: \\.\pipe\MICROSOFT##WID\tsql\query
## You'll also need to modify both the WSUS install and postinsall by dropping the UpdateServices-DB option and SQL_INSTANCE_NAME respectively.

## Nuget prereq. NOTE: You may want to remove this module later if you don't use it normally.
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
## instal sql server module 
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name SqlServer -AllowClobber

## attach a preloaded mdf and ldf files from c:\wsus\susdb\ 
$attachSQLCMD = @"
USE [master]
GO
CREATE DATABASE [SUSDB] ON (FILENAME = 'c:\wsus\susdb\susdb.mdf'),(FILENAME = 'c:\wsus\susdb\susdb_log.ldf') for ATTACH
GO
"@ 
    Invoke-Sqlcmd $attachSQLCMD -QueryTimeout 3600 -ServerInstance "$env:COMPUTERNAME"

## Install WSUS
Install-WindowsFeature –Name UpdateServices-Services, UpdateServices-DB -IncludeManagementTools

## Run wsus post install pointing to local machine's default sql instance and c:\wsus as contentdir

set-location 'c:\program files\update services\tools'
.\wsusutil.exe postinstall SQL_INSTANCE_NAME=”$env:COMPUTERNAME" CONTENT_DIR=”C:\WSUS”

## Change SUSID for SUSDB
[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")

$updateServer = get-wsusserver
$config = $updateServer.GetConfiguration()
$config.ServerId = [System.Guid]::NewGuid()
$config.Save()
