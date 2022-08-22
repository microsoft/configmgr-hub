<#
 # This script reads the EDID information stored in the registry for the currently connected monitors
 # and outputs the info to the console
 # Based on https://exar.ch/collecting-monitor-serial-numbers-with-sccm/
 #>

# Reads the 4 bytes following $index from $array then returns them as an integer interpreted in little endian
function Get-LittleEndianInt($array, $index) {
    # Create a new temporary array to reverse the endianness in
    $temp = @(0) * 4
    [Array]::Copy($array, $index, $temp, 0, 4)
    [Array]::Reverse($temp)
    
    # Then convert the byte data to an integer
    [System.BitConverter]::ToInt32($temp, 0)
}

# Iterate through the monitors in Device Manager
$monitorInfo = @()
gwmi Win32_PnPEntity -Filter "Service='monitor'" | % { $k=0 } {
    $mi = @{}
    $mi.Caption = $_.Caption
    $mi.DeviceID = $_.DeviceID
    # Then look up its data in the registry
    $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $_.DeviceID + "\Device Parameters"
    $edid = (Get-ItemProperty $path EDID -ErrorAction SilentlyContinue).EDID

    # Some monitors, especially those attached to VMs either don't have a Device Parameters key or an EDID value. Skip these
    if ($edid -ne $null) {
        # Collect the information from the EDID array in a hashtable
        $mi.Manufacturer += [char](64 + [Int32]($edid[8] / 4))
        $mi.Manufacturer += [char](64 + [Int32]($edid[8] % 4) * 8 + [Int32]($edid[9] / 32))
        $mi.Manufacturer += [char](64 + [Int32]($edid[9] % 32))
        $mi.ManufacturingWeek = $edid[16]
        $mi.ManufacturingYear = $edid[17] + 1990
        $mi.HorizontalSize = $edid[21]
        $mi.VerticalSize = $edid[22]
        $mi.DiagonalSize = [Math]::Round([Math]::Sqrt($mi.HorizontalSize*$mi.HorizontalSize + $mi.VerticalSize*$mi.VerticalSize) / 2.54)

        # Walk through the four descriptor fields
        for ($i = 54; $i -lt 109; $i += 18) {
            # Check if one of the descriptor fields is either the serial number or the monitor name
            # If yes, extract the 13 bytes that contain the text and append them into a string
            if ((Get-LittleEndianInt $edid $i) -eq 0xff) {
                for ($j = $i+5; $edid[$j] -ne 10 -and $j -lt $i+18; $j++) { $mi.SerialNumber += [char]$edid[$j] }
            }
            if ((Get-LittleEndianInt $edid $i) -eq 0xfc) {
                for ($j = $i+5; $edid[$j] -ne 10 -and $j -lt $i+18; $j++) { $mi.Name += [char]$edid[$j] }
            }
        }
        
        # If the horizontal size of this monitor is zero, it's a purely virtual one (i.e. RDP only) and shouldn't be stored
        if ($mi.HorizontalSize -ne 0) {
            $monitorInfo += $mi
        }
    }
    
}
$monitorInfo