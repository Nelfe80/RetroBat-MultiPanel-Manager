# Auto-fix Joystick OEMName from the *global* USB composite device name
# Windows 11 + CircuitPython composite: we use the "USB\VID_...&PID_....\SERIAL" instance (no &MI_)
# Writes per-user (HKCU).
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
$VID = "239A"
$PID_PREFIX = "9"  # matches PID_9xxx
$regBase = "HKCU:\System\CurrentControlSet\Control\MediaProperties\PrivateProperties\Joystick\OEM"

# 1) Find global composite devices for our VID/PID range (exclude MI_ interfaces)
$globalUsbIds = Get-CimInstance Win32_PnPEntity |
    Where-Object {
        $_.DeviceID -like "USB\VID_$VID&PID_${PID_PREFIX}*" -and
        $_.DeviceID -notlike "*&MI_*"
    } |
    Select-Object -ExpandProperty DeviceID

if (-not $globalUsbIds) {
    Write-Host "No matching *global* composite panels found (USB\VID_$VID&PID_${PID_PREFIX}xxx\SERIAL)."
    return
}

foreach ($id in $globalUsbIds) {

    # 2) Read true USB-reported product string
    $p = Get-PnpDeviceProperty -InstanceId $id -KeyName "DEVPKEY_Device_BusReportedDeviceDesc" -ErrorAction SilentlyContinue
    $productName = $p.Data

    if ([string]::IsNullOrWhiteSpace($productName)) {
        Write-Host "Skipping (no BusReportedDeviceDesc): $id"
        continue
    }

	# 3) Extract PID (4 hex digits)
	if ($id -notmatch "VID_$VID&PID_([0-9A-Fa-f]{4})") {
		Write-Host "Skipping (cannot parse PID): $id"
		continue
	}
	$pidHex = $matches[1].ToUpper()

	# 4) Write OEMName for joy.cpl
	$keyPath = Join-Path $regBase "VID_${VID}&PID_${pidHex}"
	New-Item -Path $keyPath -Force | Out-Null

	$current = (Get-ItemProperty -Path $keyPath -Name "OEMName" -ErrorAction SilentlyContinue).OEMName

	if ($current -ne $productName) {
		New-ItemProperty -Path $keyPath -Name "OEMName" -Value $productName -PropertyType String -Force | Out-Null
		Write-Host "Updated OEMName VID_$VID&PID_$pidHex -> '$productName'"
	} else {
		Write-Host "OK OEMName VID_$VID&PID_$pidHex -> '$productName'"
	}
}

Write-Host "`nDone. Close and re-open joy.cpl (or unplug/replug) to refresh."