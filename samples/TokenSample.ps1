#Generate AAD Token using below script  

$clientId = "Application (client) ID" 

$resource = "App ID URI-api://{tenantId}/{string}, for example, api://5e97358c-d99c-4558-af0c-de7774091dda/ConfigMgrService" 

$tenantId = "Tenant ID GUID value" 

$adminService = "https://<ProviderFQDN>/AdminService_TokenAuth/"

$adalPath = "Microsoft.IdentityModel.Clients.ActiveDirectory DLL Path" 

$username = "<user@domain.com>" (AAD cloud UPN) 

$password = "password"  

$authority = 'https://login.microsoftonline.us/'+$tenantId 

$adal = Join-Path $adalPath "Microsoft.IdentityModel.Clients.ActiveDirectory.dll" 

[System.Reflection.Assembly]::LoadFrom($adal) | Out-Null 

  

$userCredential = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.UserPasswordCredential -ArgumentList ($username, $password) 

$authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority 

$authResult = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContextIntegratedAuthExtensions]::AcquireTokenAsync($authContext,$resource,$clientId,$userCredential).Result 

$token = $authResult.AccessToken 

Set-Clipboard $token 

  

# Call admin service via powershell, can also do via Postman/Fiddler for same 

$headers = @{ 

"Authorization"="Bearer $token" 

"Content-Type"="application/json" 

} 

$getcoll = $adminService + "<wmi or v1.0>/<Entity>" 

Invoke-RestMethod -Uri $getcoll -Headers $headers 
 
# Or use Postman as below To call Admin Service 
 
