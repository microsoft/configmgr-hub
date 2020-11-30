#region FUNCTIONS

#region FUNCTION Get-RebootHistory
FUNCTION Get-RebootHistory {
  <#
      .SYNOPSIS
      Retrieves historical information about shutdown/restart events from one or more remote computers.
	
      .DESCRIPTION
      The Get-RebootHistory function uses Common Information Model (CIM) to retrieve information about all shutdown events from a remote computer.
		
      Using this function, you can analyze shutdown events across a large number of computers to determine how frequently shutdown/restarts are occurring, whether unexpected shutdowns are occurring and quickly identify the source of the last clean shutdown/restart.
		
      Data returned includes date/time information for all available boot history events (e.g. restarts, shutdowns, unexpected shutdowns, etc.), date/time information for unexpected reboots and detailed information about the last clean shutdown including date/time, type, initiating user, initiating process and reason.
		
      Because Get-RebootHistory uses CIM to obtain shutdown event history from the system event log, it is fully supported against both legacy and current versions of Windows including legacy versions that do not support filtering of event logs through standard methods. Requires Windows PowerShell 3.0 or higher 
	
      .PARAMETER ComputerName
      Accepts a single computer name or an array of computer names separated by commas (e.g. "prod-web01","prod-web02").
		
      This is an optional parameter, the default value is the local computer ($Env:ComputerName).
	
      .PARAMETER Credential
      Accepts a standard credential object.
		
      This is an optional parameter and is only necessary when the running user does not have access to the remote computer(s).
	
      .EXAMPLE
      .\Get-RebootHistory -ComputerName prod-web01,prod-web02 -Credential (Get-Credential)
		
      Get boot history for multiple remote computers with alternate credentials.
	
      .EXAMPLE
      .\Get-RebootHistory -ComputerName prod-web01,prod-web02 -Credential (Get-Credential) | ? { $_.PercentDirty -ge 30 }
		
      Get a list of computers experiencing a high percentage of unexpected shutdown events.
	
      .EXAMPLE
      .\Get-RebootHistory -ComputerName prod-web01,prod-web02 -Credential (Get-Credential) | ? { $_.RecentShutdowns -ge 3 }
		
      Return information about servers that have been experiencing frequent shutdown/reboot events over the last 30 days.
	
      .OUTPUTS
      System.Management.Automation.PSCustomObject
		
      Return object includes the following properties:
		
      Computer
      BootHistory                : Array of System.DateTime objects for all recorded instances of the system booting (clean or otherwise).
      RecentShutdowns            : The number of shutdown/restart events in the last 30 days.
      UnexpectedShutdowns        : Array of System.DateTime objects for all recorded unexpected shutdown events.
      RecentUnexpected        : The number of unexpected shutdown events in the last 30 days.
      PercentDirty            : The percentage of shutdown events that were unexpected (UnexpectedShutdowns/BootHistory).
      LastShutdown            : System.DateTime object of the last clean shutdown event.
      LastShutdownType        : Type of the last clean shutdown event (Restart | Shutdown).
      LastShutdownUser        : The user who initiated the last clean shutdown event.
      LastShutdownProcess        : The process that initiated the last clean shutdown event.
      LastShutdownReason        : If available, the reason code and comments for the last clean shutdown event.
	
      .NOTES
      Author          : Eric Westfall
      Email           : eawestfall@gmail.com
      Script Version  : 1.1
      Revision Date   : 11/26/2014
      Revision Author : Nic Wendlowsky (https://github.com/hkystar35)
      Revision Date   : 8/25/2020
		
      Release notes:
      8/25/2020 - Converted WMI commands to CIM | modified SWITCH statement and Splat to use new CIM properties | Added Get-UserFromRegistry function to translate LastShutdownUser value
  #>
	
	PARAM
	(
		[Parameter(Mandatory = $false,
				   ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 0)][Alias('CN', 'Computer')][Array]$ComputerName = $Env:ComputerName,
		[Parameter(Mandatory = $false,
				   ValueFromPipeline = $false,
				   Position = 1)][ValidateNotNull()][Alias('Cred')][System.Management.Automation.PSCredential]$Credential = [System.Management.Automation.PSCredential]::Empty
	)
	
	BEGIN {
		$i = 0
		$RecentShutdowns = 0
		$RecentUnexpected = 0
		
		$BootHistory = @()
		$ShutdownDetail = @()
		$UnexpectedShutdowns = @()
		
		# Store original credential, if we attempt to make a local connection we need to  
		# temporarily empty out the credential object. 
		$Original_Credential = $Credential
		
		# Select properties defined to ensure proper display order. 
		$BootInformation = @(
			"Computer"
			"BootHistory"
			"RecentShutdowns"
			"UnexpectedShutdowns"
			"RecentUnexpected"
			"PercentDirty"
			"LastShutdown"
			"LastShutdownType"
			"LastShutdownUser"
			"LastShutdownProcess"
			"LastShutdownReason"
		)
		
		# Arguments to be passed to our CIM call. 
		$Params = @{
			ErrorAction	    = 'Stop'
			ComputerName    = $Computer
			Credential	    = $Credential
			FilterHashtable = @{Logname = 'System'; ID = "1074", "6008", "6009"}
		}
	}
	
	PROCESS {
		FOREACH ($Computer IN $ComputerName) {
			$Params.ComputerName = $Computer
			
			# You can't use credentials when connecting to the local machine so temporarily empty out the credential object. 
			IF ($Computer -eq $Env:ComputerName) {
				$Params.Credential = [System.Management.Automation.PSCredential]::Empty
			}
			
			IF ($ComputerName.Count -gt 1) {
				Write-Progress -Id 1 -Activity "Retrieving boot history." -Status ("Percent Complete: {0:N0}" -f $($i / $($ComputerName.Count) * 100)) -PercentComplete (($i / $ComputerName.Count) * 100); $i++
			}
			ELSE {
				Write-Progress -Id 1 -Activity "Retrieving boot history."
			}
			
			TRY {
				$d = 0
				$Events = Get-WinEvent @Params
				
				FOREACH ($Event IN $Events) {
					Write-Progress -Id 2 -ParentId 1 -Activity "Processing reboot history." -PercentComplete (($d / $Events.Count) * 100); $d++
					
					# Record the relevant details for the shutdown event. 
					SWITCH ($Event.Id) {
						6009 {
							$BootHistory += $Event.TimeCreated | Get-Date -Format g
						}
						6008 {
							$UnexpectedShutdowns += ('{0} {1}' -f ($Event.Properties[1].Value, $Event.Properties[0].Value))
						}
						1074 {
							$ShutdownDetail += $Event
						}
					}
				}
				
				# We explicitly ignore exceptions originating from this process since some versions of Windows may store dates in invalid formats (e.g. ?11/?16/?2014) in the event log after an unexpected shutdown causing this calculation to fail. 
				TRY {
					$RecentUnexpected = ($UnexpectedShutdowns | Where-Object {((Get-Date) - (Get-Date $_)).TotalDays -le 30}).Count
				}
				CATCH {
					$RecentUnexpected = "Unable to calculate."
				}
				
				# Grab details about the last clean shutdown and generate our return object. 
				$ShutdownDetail | Select-Object -First 1 | ForEach-Object {
					New-Object -TypeName PSObject -Property @{
						Computer = $_.MachineName
						BootHistory = $BootHistory
						RecentUnexpected = $RecentUnexpected
						LastShutdownUser = (Get-UserFromRegistry -SID $_.UserId).User
						UnexpectedShutdowns = $UnexpectedShutdowns
						LastShutdownProcess = $_.Properties[0].Value
						PercentDirty = '{0:P0}' -f (($UnexpectedShutdowns.Count/$BootHistory.Count))
						LastShutdownType = (Get-Culture).TextInfo.ToTitleCase($_.Properties[4].Value)
						LastShutdown = ($_.TimeCreated | Get-Date -Format g)
						RecentShutdowns = ($BootHistory | Where-Object {((Get-Date) - (Get-Date $_)).TotalDays -le 30}).Count
						LastShutdownReason = 'Reason Code: {0}, Reason: {1}' -f ($_.Properties[3].Value, $_.Properties[2].Value)
					} | Select-Object $BootInformation
				}
			}
			CATCH [System.Exception] {
				# We explicitly ignore exceptions originating from Get-Date since some versions of Windows may store dates in invalid formats in the event log after an unexpected shutdown. 
				IF ($_.CategoryInfo.Activity -ne 'Get-Date') {
					Write-Warning ("Unable to retrieve boot history for {0}. `nError Details: {1}" -f ($Computer, $_))
				}
			}
			
			# Reset credential object since we may have temporarily overwrote it to deal with local connections. 
			$Params.Credential = $Original_Credential
		}
	}
}
#endregion FUNCTION Get-RebootHistory

#region FUNCTION Get-UserFromRegistry
FUNCTION Get-UserFromRegistry {
	PARAM (
		$SID
	)
	$ProfileList = Get-CimInstance -ClassName win32_userprofile | Select-Object @{
		L							   = "User"; E = {
			($_.localpath -split '\\')[-1]
		}
	}, *
	TRY {
		$ProfileList | Where-Object {
			$_.SID -eq $SID
		} | Select-Object User, SID, LocalPath
	}
	CATCH {
		"Error was $_"
		$line = $_.InvocationInfo.ScriptLineNumber
		"Error was in Line $line"
	}
}
#endregion FUNCTION Get-UserFromRegistry

#endregion FUNCTIONS

Get-RebootHistory