<# 
DISCLAIMER: 
These sample scripts are not supported under any Lenovo standard support   
program or service. The sample scripts are provided AS IS without warranty   
of any kind. Lenovo further disclaims all implied warranties including,   
without limitation, any implied warranties of merchantability or of fitness for   
a particular purpose. The entire risk arising out of the use or performance of   
the sample scripts and documentation remains with you. In no event shall   
Lenovo, its authors, or anyone else involved in the creation, production, or   
delivery of the scripts be liable for any damages whatsoever (including,   
without limitation, damages for loss of business profits, business interruption,   
loss of business information, or other pecuniary loss) arising out of the use   
of or inability to use the sample scripts or documentation, even if Lenovo   
has been advised of the possibility of such damages.  
#> 

<# 
.SYNOPSIS 
 This script reads the raw SMBIOS table data from WMI and derives the set of 
 Odometer metrics.  These are then stored in the root\Lenovo:Lenovo_Odometer 
 class in WMI which can be inventoried more easily. 
 
.DESCRIPTION 
 Odometer data is updated at each reboot. This script can be executed by 
 scheduled task to run after each boot to collect the current metrics. The
 Odometer metrics include:
    - CPU Uptime - amount of time cpu has been active in seconds
    - Shock events - based on detections from accellarometer
    - Thermal events - registered high-temp conditions where cpu was throttled
    - Battery cycles - number of charge cycles performed on battery
    - SSD Read/Writes - number of reads and writes on one or more internal SSDs
 
.NOTES
+---------------------------------------------------------------------------------------------+ 
|   DATE        : 2020.06.12 
|   AUTHOR      : Lenovo Commercial Deployment Readiness Team 
|   DESCRIPTION : Version 1.0 
+---------------------------------------------------------------------------------------------+ 
 
#> 

<# 
    Create the root\Lenovo:Lenovo_Odometer class in WMI if it doesn't exist 
#>
function CreateClass {
    $ns = [wmiclass]'root:__NAMESPACE'
    $sc = $ns.CreateInstance()
    $sc.Name = 'Lenovo'
    $sc.Put()

    $class = New-Object System.Management.ManagementClass ("root\Lenovo", [string]::Empty, $null)
    $class["__CLASS"] = "Lenovo_Odometer"
    $class.Qualifiers.Add("SMS_Report", $true)
    $class.Qualifiers.Add("SMS_Group_Name", "Lenovo_Odometer")
    $class.Qualifiers.Add("SMS_Class_Id", "Lenovo_Odometer")

    $class.Properties.Add("SystemID", [System.Management.CimType]::String, $false)
    $class.Properties.Add("CPU_Uptime", [System.Management.CimType]::String, $false)
    $class.Properties.Add("Shock_events", [System.Management.CimType]::String, $false)
    $class.Properties.Add("Thermal_events", [System.Management.CimType]::String, $false)
    $class.Properties.Add("Battery_cycles", [System.Management.CimType]::String, $false)
    $class.Properties.Add("SSD_Read_Write_count", [System.Management.CimType]::String, $false)

    $class.Properties["SystemID"].Qualifiers.Add("Key", $true)
    $class.Properties["SystemID"].Qualifiers.Add("SMS_Report", $true)
    $class.Properties["CPU_Uptime"].Qualifiers.Add("SMS_Report", $true)
    $class.Properties["Shock_events"].Qualifiers.Add("SMS_Report", $true)
    $class.Properties["Thermal_events"].Qualifiers.Add("SMS_Report", $true)
    $class.Properties["Battery_cycles"].Qualifiers.Add("SMS_Report", $true)
    $class.Properties["SSD_Read_Write_count"].Qualifiers.Add("SMS_Report", $true)

    $class.Put()
}

<#  Add the current metric values to the :Lenovo_Odometer class  #>
function AddValues {

    param (
        [parameter (Mandatory=$true, position=0, ParameterSetName='OdValues')]
        [string]$system,
        [parameter (Mandatory = $true, position = 1, ParameterSetName = 'OdValues')]
        [string]$cpu_uptime,
        [parameter (Mandatory = $true, position = 2, ParameterSetName = 'OdValues')]
        [string]$shock,
        [parameter (Mandatory = $true, position = 3, ParameterSetName = 'OdValues')]
        [string]$thermal,
        [parameter (Mandatory = $true, position = 4, ParameterSetName = 'OdValues')]
        [string]$battery,
        [parameter (Mandatory = $true, position = 5, ParameterSetName = 'OdValues')]
        [string]$ssd
    )

        try {
            $thissystem = Get-WmiObject -Namespace root\Lenovo -Class Lenovo_Odometer -Filter "SystemID = '$system'"
            if ($thissystem.SystemID -eq $system) {
                $thissystem.CPU_Uptime = $cpu_uptime
                $thissystem.Shock_events = $shock
                $thissystem.Thermal_events = $thermal
                $thissystem.Battery_cycles = $battery
                $thissystem.SSD_Read_Write_count = $ssd 
                $thissystem.Put()
            } else {  
               Set-WmiInstance -Path '\\.\root\Lenovo:Lenovo_Odometer' -PutType CreateOnly -Arguments @{SystemID = $system; CPU_Uptime = $cpu_uptime; Shock_events = $shock; Thermal_events = $thermal;  Battery_cycles = $battery; SSD_Read_Write_count = $ssd}               
            }
        }
        catch {
            "Did not add: " + $system
        }      
}


## Main ##

# // Create the Lenovo WMI Namespace // #
[void](Get-WmiObject -Namespace root\Lenovo -Class Lenovo_Odometer -ErrorAction SilentlyContinue -ErrorVariable wmiclasserror)

if ($wmiclasserror) {
    try {
        Write-Output "================================="
        Write-Output "Creating the Lenovo WMI Namespace"
        Write-Output "================================="
        CreateClass
    }
    catch {
        Write-Warning -Message "Could not create WMI class" ; Exit 1
    }
}

#Get a system ID made from MTM - Serial#
[string]$systemID = (Get-WmiObject -Class Win32_ComputerSystemProduct | Select-Object -ExpandProperty Name) + " - " + (Get-WmiObject -Class Win32_ComputerSystemProduct | Select-Object -ExpandProperty IdentifyingNumber)

#Get Raw SMBIOS Table data
$objWMI = get-wmiobject -namespace root\WMI -computername localhost -Query "Select * from MSSmBios_RawSMBiosTables"

foreach ($obj in $objWmi)
{
    $raw = $obj.SMBiosData
}

$cpu_uptime = "No CPU Uptime data found."
$shock = "No Shock data found."
$thermal = "No Thermal data found."
$battery = ""
$ssd = ""

for ($i=0; $i -lt $raw.Count; $i++) {
    if ($raw[$i] -eq 141) { 
        $sigindex = $i + 4
        $sig = [char]$raw[$sigindex] + [char]$raw[($sigindex + 1)] + [char]$raw[($sigindex + 2)] + [char]$raw[($sigindex + 3)]
        if ($sig -eq 'THNK') {
            #verified Odometer item
            
            #length of structure
            $tablelength = $raw[$i + 1]
            
            #location of metric identifier
            $metricindex = $i + 10
            
            #start location of data
            $datastart = $i + 14

            #metric identifier consists of 4 bytes
            $metrictype = $raw[$metricindex] + $raw[($metricindex + 1)] + $raw[($metricindex + 2)] + $raw[($metricindex + 3)]

            #convert metric identifier to name using combined four bytes using the decimal values from raw table data
            # and get data value

            ##initialize strings with default values##
            [string]$metricname = ""


            Switch ($metrictype)
            {
                0   { 
                        $metricname = "CPU Uptime" 
                        [array]$data = ($raw[$datastart], $raw[$datastart + 1], $raw[$datastart + 2], $raw[$datastart + 3])
                        $cpu_uptime = [bitconverter]::ToInt32($data,0)
                    }
                16  { 
                        $metricname = "Vibration Shock"
                        [array]$data = ($raw[$datastart], $raw[$datastart + 1], $raw[$datastart + 2], $raw[$datastart + 3])
                        $shock = [bitconverter]::ToInt32($data,0)
                    }
                48  { 
                        $metricname = "Thermal Throttling Events" 
                        [array]$data = ($raw[$datastart], $raw[$datastart + 1], $raw[$datastart + 2], $raw[$datastart + 3])
                        $thermal = [bitconverter]::ToInt32($data,0)
                    }
                64  { 
                        # Battery Cycles:  some systems may have two batteries
                        $metricname = "Battery Cycles" 
                        $data = $null
                        #determine number of data sets
                        [int]$battcount = ($tablelength - 14)/4
                        for ([int]$batt=0; $batt -lt $battcount; $batt++) {
                            for ([int]$n=0; $n -lt 4; $n++) {
                                $data = $data + $raw[$datastart + $n]
                            }
                            if ($battery -eq "") {
                                $battery = "Battery " + $batt + ": " + [bitconverter]::ToInt32($data,0)
                            } else {
                                $battery += "; Battery " + $batt + ": " + [bitconverter]::ToInt32($data,0)
                            }
                            $data = $null
                            $datastart = $datastart + 4
                        }
                    }
                80  { 
                        # SSD Reads/Writes:  covers internal SSD and NVME drives
                        $metricname = "SSD Read_Write Counts"
                        $data = $null
                        #determine number of data sets
                        [int]$drivecount = ($tablelength - 14)/16
                        for ([int]$drive=0; $drive -lt $drivecount; $drive++) {
                            for ([int]$n=0; $n -lt 8; $n++) {
                                $data = $data + $raw[$datastart + $n]
                            } 
                            $read = [bitconverter]::ToInt32($data,0)
                            if ($ssd -eq "") {
                                $ssd = "Drive " + $drive + ": " + $read
                            } else {
                                $ssd += "; Drive " + $drive + ": " + $read
                            }
                            
                            $data = $null
                            $datastart = $datastart + 8  
                            for ($n=0; $n -lt 8; $n++) {
                                $data = $data + $raw[$datastart + $n]
                            } 
                            $write = [bitconverter]::ToInt32($data,0)
                            $ssd += "/" + $write
                            $datastart = $datastart + 8
                            $data = $null
                        }
                        
                     
                    }
                Default { $metricname = "Unknown Metric" }
            }

        }
    }
}
if ($battery -eq "") {
    $battery = "No battery data found"
    }
if ($ssd -eq "") {
    $ssd = "No SSD data found"
    }

AddValues $systemID $cpu_uptime $shock $thermal $battery $ssd