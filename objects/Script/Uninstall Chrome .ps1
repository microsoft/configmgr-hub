$app = Get-WmiObject -Class Win32_Product | Where-Object {
$_.Name -match “Google Chrome”}
$app.Uninstall()
$FolderName = "C:\Program Files (x86)\Google"
if (Test-Path $FolderName) {
 
    Write-Host "Folder Exists"
    Remove-Item $FolderName -Recurse -Force
}