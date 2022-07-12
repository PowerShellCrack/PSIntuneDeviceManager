Function Connect-MSGraphAsAnApp {
    <#
    .SYNOPSIS
    Authenticates to the Graph API via the Microsoft.Graph.Intune module using app-based authentication.

    .DESCRIPTION
    The Connect-MSGraphAsAnApp cmdlet is a wrapper cmdlet that helps authenticate to the Graph API using the Microsoft.Graph.Intune module.
    It leverages an Azure AD app ID and app secret for authentication. See https://oofhours.com/2019/11/29/app-based-authentication-with-intune/ for more information.
    https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal#create-a-new-application-secret

    .PARAMETER Tenant
    Specifies the tenant (e.g. contoso.onmicrosoft.com) to which to authenticate.

    .PARAMETER AppId
    Specifies the Azure AD app ID (GUID) for the application that will be used to authenticate.

    .PARAMETER AppSecret
    Specifies the Azure AD app secret corresponding to the app ID that will be used to authenticate.

    .EXAMPLE
    Connect-MSGraphAsAnApp -TenantId $TenantID -AppId $app -AppSecret $secret


    #>

    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [Alias('ClientId')]
        [String]$AppId,

        [Parameter(Mandatory=$true)]
        [Alias('Tenant')]
        [String]$TenantID,

        [Parameter(Mandatory=$true)]
        [Alias('ClientSecret')]
        [String]$AppSecret
    )
    try {
        #convert secret into creds
        $azurePassword = ConvertTo-SecureString $AppSecret -AsPlainText -Force
        $psCred = New-Object System.Management.Automation.PSCredential($AppId , $azurePassword)

        #connect to Azure using App service principal
        Connect-AzAccount -Credential $psCred -TenantId $TenantID -ServicePrincipal | Out-Null

        #Grab the Azure context which will include Azure Token
        $context = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext
        $aadToken = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, `
                                                $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, `
                                                $null, "https://graph.windows.net").AccessToken

        $Body = @{
            Grant_Type    = "client_credentials"
            Scope         = "https://graph.microsoft.com/.default"
            client_Id     = $AppId
            Client_Secret = $AppSecret
        }
        $ConnectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token" -Method POST -Body $Body
        $token = $ConnectGraph.access_token
        #format the date correctly
        $ExpiresOnMinutes = $ConnectGraph.expires_in / 60
        $ExpiresOn = (Get-Date).AddMinutes($ExpiresOnMinutes).ToString("M/d/yyyy hh:mm tt +00:00")

        # Creating header for Authorization token
        $authHeader = @{
            'Content-Type'='application/json'
            'Authorization'="Bearer " + $token
            'ExpiresOn'=$ExpiresOn
        }
        return $authHeader
    }
    Catch{
        write-host $_.Exception.Message -f Red
        write-host $_.Exception.ItemName -f Red
        write-host
        break
    }
}

function Get-MSGraphAuthToken{

    <#
    .SYNOPSIS
    This function is used to authenticate with the Graph API REST interface
    .DESCRIPTION
    The function authenticate with the Graph API Interface with the tenant name
    .EXAMPLE
    Get-MSGraphAuthToken
    Authenticates you with the Graph API interface
    .NOTES
    NAME: Get-MSGraphAuthToken
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [System.Net.Mail.MailAddress]$User
    )

    $userUpn = New-Object "System.Net.Mail.MailAddress" -ArgumentList $User
    $tenant = $userUpn.Host

    Write-Host "Checking for AzureAD module..."
    $AadModule = Get-Module -Name "AzureAD" -ListAvailable

    if ($AadModule -eq $null) {
        write-host
        write-host "AzureAD Powershell module not installed..." -f Red
        write-host "Install by running 'Install-Module AzureAD' from an elevated PowerShell prompt" -f Yellow
        write-host "Script can't continue..." -f Red
        write-host
        exit
    }

    # Getting path to ActiveDirectory Assemblies
    # If the module count is greater than 1 find the latest version
    if($AadModule.count -gt 1)
    {
        $Latest_Version = ($AadModule | select version | Sort-Object)[-1]
        $aadModule = $AadModule | ? { $_.version -eq $Latest_Version.version }
        # Checking if there are multiple versions of the same module found
        if($AadModule.count -gt 1){
            $aadModule = $AadModule | select -Unique
        }
        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    }

    else {
        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    }

    #$adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
    #$adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"

    [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null
    $clientId = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547"
    $redirectUri = "urn:ietf:wg:oauth:2.0:oob"
    $resourceAppIdURI = "https://graph.microsoft.com"
    $authority = "https://login.microsoftonline.com/$Tenant"

    try {
        $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority

        # https://msdn.microsoft.com/en-us/library/azure/microsoft.identitymodel.clients.activedirectory.promptbehavior.aspx
        # Change the prompt behavior to force credentials each time: Auto, Always, Never, RefreshSession
        $platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "Auto"
        $userId = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($User, "OptionalDisplayableId")
        $authResult = $authContext.AcquireTokenAsync($resourceAppIdURI,$clientId,$redirectUri,$platformParameters,$userId).Result

        # If the accesstoken is valid then create the authentication header
        if($authResult.AccessToken){

            # Creating header for Authorization token
            $authHeader = @{
                'Content-Type'='application/json'
                'Authorization'="Bearer " + $authResult.AccessToken
                'ExpiresOn'=$authResult.ExpiresOn
            }
            return $authHeader
        }
        else {
            Write-Host
            Write-Host "Authorization Access Token is null, please re-run authentication..." -ForegroundColor Red
            Write-Host
            break
        }
    }

    catch {
        write-host $_.Exception.Message -f Red
        write-host $_.Exception.ItemName -f Red
        write-host
        break
    }
}

#https://github.com/smcavinue/AdminSeanMc/blob/master/Graph%20Scripts/graph-RefreshAccessToken.ps1
function Refresh-MSGraphAccessToken{
    <#
    .SYNOPSIS
    Refreshes an access token based on refresh token
    .RETURNS
        Returns a refreshed access token
    .PARAMETER Token
        -Token is the existing refresh token
    .PARAMETER tenantID
        -This is the tenant ID eg. domain.onmicrosoft.com
    .PARAMETER ClientID
        -This is the app reg client ID
    .PARAMETER Secret
        -This is the client secret
    .PARAMETER Scope
        -A comma delimited list of access scope, default is: "Group.ReadWrite.All,User.ReadWrite.All"

    #>
    Param(
        [parameter(Mandatory = $true)]
        [String]$Token,

        [parameter(Mandatory = $true)]
        [String]$TenantID,

        [parameter(Mandatory = $true)]
        [String]$ClientID,

        [parameter(Mandatory = $false)]
        [String]$Scope = "Group.ReadWrite.All,User.ReadWrite.All",

        [parameter(Mandatory = $true)]
        [String]$Secret
    )

$ScopeFixup = $Scope.replace(',','%20')
$apiUri = "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token"
$body = "client_id=$ClientID&scope=$ScopeFixup&refresh_token=$Token&redirect_uri=http%3A%2F%2Flocalhost%2F&grant_type=refresh_token&client_secret=$Secret"
write-verbose $body -Verbose
$Refreshedtoken = (Invoke-RestMethod -Uri $apiUri -Method Post -ContentType 'application/x-www-form-urlencoded' -body $body  )

return $Refreshedtoken

}
