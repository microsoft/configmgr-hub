# The following sample shows how to request Azure AD user token using client app and a resource (server app).

# Install MSAL.NET or download the package at https://www.nuget.org/packages/Microsoft.Identity.Client/ and copy the binaries to the current folder
Import-Module Microsoft.Identity.Client.dll

# Define variables
$clientId = "Application (client) ID" # Navigate to client app in Azure Portal and select Overview section to find application client id
$tenantId = "tenant id" # Tenant or organization id is available on the same Overview page
$redirectUri = "msalfclientApp://auth" # Under Authentication section of the client app, check one of the redirect URIs, save the app, and paste here 
$resource = "api://tenantId/serverApp" # Navigate to server app and copy  Application ID URI from the Overview page

# Derive variables
$authority = "https://login.windows.net/"+$tenantid
$scopes =  New-Object System.Collections.Generic.List[string]
$scopes.Add($resource+"/.default")

# Build MSAL application
$app = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($clientId).WithAuthority($authority).WithRedirectUri($redirectUri).Build()
$request = $app.AcquireTokenInteractive($scopes).WithPrompt([Microsoft.Identity.Client.Prompt]::ForceLogin)

# Request the token and prompt the user for credentials
$tokenResult = $request.ExecuteAsync().Result
$token = $tokenResult.AccessToken

# Invoke admin service
$adminService = "https://Provider_FQDN/AdminService_TokenAuth/"
$api = "v1.0/Device"

$url = $adminService + $api
$headers = @{ 
   "Authorization"="Bearer $token" 
   "Content-Type"="application/json" 
} 
Invoke-RestMethod -Uri $url -Headers $headers
