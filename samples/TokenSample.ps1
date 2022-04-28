# The following sample shows how to request Azure AD user token using client app and a resource (server app).
# Note: for testing purposes only to provide an example of requesting a user token. Do not include passwords in the automation scripts. 
$clientId = "Application (client) ID" 
$resource = "App ID URI-api://{tenantId}/{string}, for example, api://5e97358c-d99c-4558-af0c-de7774091dda/ConfigMgrService" 
$tenantId = "Tenant ID GUID value" 
$adminService = "https://<ProviderFQDN>/AdminService_TokenAuth/"
$adalPath = "Microsoft.IdentityModel.Clients.ActiveDirectory DLL Path" 
$username = "<user@domain.com>" (AAD cloud UPN, must match on-premises UPN of the admin account) 
$password = "password"  
$authority = 'https://login.windows.net/'+$tenantId 
$adal = Join-Path $adalPath "Microsoft.IdentityModel.Clients.ActiveDirectory.dll" 
[System.Reflection.Assembly]::LoadFrom($adal) | Out-Null 
$userCredential = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.UserPasswordCredential -ArgumentList ($username, $password) 
$authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority 
$authResult = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContextIntegratedAuthExtensions]::AcquireTokenAsync($authContext,$resource,$clientId,$userCredential).Result 
$token = $authResult.AccessToken 

# Call admin service via powershell, can also do via Postman/Fiddler for same 
$headers = @{ 
   "Authorization"="Bearer $token" 
   "Content-Type"="application/json" 
} 
$getcoll = $adminService + "<wmi or v1.0>/<Entity>" 
Invoke-RestMethod -Uri $getcoll -Headers $headers
