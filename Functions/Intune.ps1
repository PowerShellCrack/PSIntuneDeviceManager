Function Connect-MSGraphApp {
    <#TEST
    $ApplicationId ="21d133d2-75eb-4241-9247-febde41f4463"
    $AppTenantId = "2ec9dcf0-b109-434a-8bcd-238a3bf0c6b2"
    $AppId = $ApplicationId
    $TenantID = $AppTenantId
    $Global:AppSecret = "5.V7Q~RHqawIkS3nNaCTg.Opwwm~RNTxxg2D."
    $AppSecret = $Global:AppSecret
    #>
    #https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal#create-a-new-application-secret
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        $AppId,
        [Parameter(Mandatory=$true)]
        $TenantID,
        [Parameter(Mandatory=$true)]
        $AppSecret
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

        #Attempt to connect to Azure Ad using token
        #Connect-AzureAD -AadAccessToken $aadToken -AccountId $context.Account.Id -TenantId $context.tenant.id | Out-Null

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

function Get-AuthToken{

    <#
    .SYNOPSIS
    This function is used to authenticate with the Graph API REST interface
    .DESCRIPTION
    The function authenticate with the Graph API Interface with the tenant name
    .EXAMPLE
    Get-AuthToken
    Authenticates you with the Graph API interface
    .NOTES
    NAME: Get-AuthToken
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
function Refresh-AccessToken{
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
        [String]
        $Token,
        [parameter(Mandatory = $true)]
        [String]
        $tenantID,
        [parameter(Mandatory = $true)]
        [String]
        $ClientID,
        [parameter(Mandatory = $false)]
        [String]
        $Scope = "Group.ReadWrite.All,User.ReadWrite.All",
        [parameter(Mandatory = $true)]
        [String]
        $Secret
    )

$ScopeFixup = $Scope.replace(',','%20')
$apiUri = "https://login.microsoftonline.com/$tenantID/oauth2/v2.0/token"
$body = "client_id=$ClientID&scope=$ScopeFixup&refresh_token=$Token&redirect_uri=http%3A%2F%2Flocalhost%2F&grant_type=refresh_token&client_secret=$Secret"
write-verbose $body -Verbose
$Refreshedtoken = (Invoke-RestMethod -Uri $apiUri -Method Post -ContentType 'application/x-www-form-urlencoded' -body $body  )

return $Refreshedtoken

}

Function Get-ManagedDevices{

    <#
    .SYNOPSIS
    This function is used to get Intune Managed Devices from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any Intune Managed Device
    .EXAMPLE
    Get-ManagedDevices
    Returns all managed devices but excludes EAS devices registered within the Intune Service
    .EXAMPLE
    Get-ManagedDevices -IncludeEAS
    Returns all managed devices including EAS devices registered within the Intune Service
    .NOTES
    NAME: Get-ManagedDevices
    #>

    [cmdletbinding()]

    param
    (
        $AuthToken,
        [switch]$IncludeEAS,
        [switch]$ExcludeMDM,
        [ValidateSet('Windows','Android','MacOS','iOS')]
        [string]$FilterOS
    )

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/managedDevices"

    try {
        $Count_Params = 0

        if($IncludeEAS.IsPresent){ $Count_Params++ }
        if($ExcludeMDM.IsPresent){ $Count_Params++ }

        if($Count_Params -gt 1){
            write-warning "Multiple parameters set, specify a single parameter -IncludeEAS, -ExcludeMDM or no parameter against the function"
            Write-Host
            break
        }
        elseif($IncludeEAS){
            $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"
        }

        elseif($ExcludeMDM){
            $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource`?`$filter=managementAgent eq 'eas'"
        }

        else {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource`?`$filter=managementAgent eq 'mdm' and managementAgent eq 'easmdm'"
            Write-Warning "EAS Devices are excluded by default, please use -IncludeEAS if you want to include those devices"
            Write-Host
        }
        $devices = (Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get).Value

        If($PSBoundParameters.ContainsKey('FilterOS')){
        }
            return $devices | Where{ $_.operatingSystem -eq $FilterOS}
        Else{
            return $devices
        }
    }
    catch {
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        write-host
        break
    }

}


Function Get-ManagedDevicePendingActions{

    <#
    .SYNOPSIS
    This function is used to get a Managed Device pending Actions
    .DESCRIPTION
    The function connects to the Graph API Interface and gets a managed device pending actions
    .EXAMPLE
    Get-ManagedDeviceUser -DeviceID $DeviceID
    Returns a managed device user registered in Intune
    .NOTES
    NAME: Get-ManagedDeviceUser
    #>

    [cmdletbinding()]

    param
    (
        $AuthToken,
        [Parameter(Mandatory=$true,HelpMessage="DeviceID (guid) for the device on must be specified:")]
        $DeviceID
    )

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/manageddevices/$DeviceID"

    try {
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
        Write-Verbose $uri
        (Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get).deviceActionResults
    }
    catch {
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        write-host
        break
    }
}

Function Get-ManagedDeviceUser{

    <#
    .SYNOPSIS
    This function is used to get a Managed Device username from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets a managed device users registered with Intune MDM
    .EXAMPLE
    Get-ManagedDeviceUser -DeviceID $DeviceID
    Returns a managed device user registered in Intune
    .NOTES
    NAME: Get-ManagedDeviceUser
    #>

    [cmdletbinding()]

    param
    (
        $AuthToken,
        [Parameter(Mandatory=$true,HelpMessage="DeviceID (guid) for the device on must be specified:")]
        $DeviceID
    )

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/manageddevices('$DeviceID')?`$select=userId"

    try {
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
        Write-Verbose "Get $uri"
        (Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get).userId
    }
    catch {
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        write-host
        break
    }
}

#region
Function Get-AADUser{

    <#
    .SYNOPSIS
    This function is used to get AAD Users from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any users registered with AAD
    .EXAMPLE
    Get-AADUser
    Returns all users registered with Azure AD
    .EXAMPLE
    Get-AADUser -userPrincipleName user@domain.com
    Returns specific user by UserPrincipalName registered with Azure AD
    .NOTES
    NAME: Get-AADUser
    #>

    [cmdletbinding()]

    param
    (
        $AuthToken,
        [Alias('User')]
        [System.Net.Mail.MailAddress]$UPN,
        [ValidateSet('id','userPrincipalName','surname','officeLocation','mail','displayName','givenName')]
        [String]$Property
    )

    # Defining Variables
    $graphApiVersion = "v1.0"
    $User_resource = "users"

    try {
        if($UPN -eq "" -or $UPN -eq $null)
        {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)"
            (Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get).Value
        }
        else {
            if($Property -eq "" -or $Property -eq $null){
                $uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)/$UPN"
                Write-Verbose $uri
                Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get
            }
            else {
                $uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)/$UPN/$Property"
                Write-Verbose $uri
                (Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get).Value
            }
        }
    }

    catch {
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        write-host
        break
    }
}



Function Invoke-DeviceAction{
    <#
    .SYNOPSIS
    This function is used to set a generic intune resources from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and sets a generic Intune Resource
    .EXAMPLE
    Invoke-DeviceAction -DeviceID $DeviceID -remoteLock
    Resets a managed device passcode
    .NOTES
    NAME: Invoke-DeviceAction
    #>

    [cmdletbinding()]

    param
    (
        $AuthToken,
        [Parameter(Mandatory=$true,HelpMessage="DeviceId (guid) for the Device you want to take action on must be specified:")]
        $DeviceID,
        [Parameter(Mandatory=$true)]
        [ValidateSet('RemoteLock','ResetPasscode','Wipe','Retire','Delete','Sync','Rename')]
        $Action,
        $Force,
        $NewDeviceName,
        [switch]$WhatIf
    )

    $graphApiVersion = "Beta"

    try {
        switch($Action){

            'RemoteLock'
            {
                $Resource = "deviceManagement/managedDevices/$DeviceID/remoteLock"
                $uri = "https://graph.microsoft.com/$graphApiVersion/$($resource)"
                write-verbose $uri
                Write-Verbose "Sending remoteLock command to $DeviceID"
                Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Post
            }

            'ResetPasscode'
            {
                if($WhatIf){
                    Write-Host "Reset of the Passcode for the device $DeviceID was cancelled..."
                }
                else {
                    write-host "Reseting the Passcode this device..."
                    $Resource = "deviceManagement/managedDevices/$DeviceID/resetPasscode"
                    $uri = "https://graph.microsoft.com/$graphApiVersion/$($resource)"
                    write-verbose $uri
                    Write-Verbose "Sending remotePasscode command to $DeviceID"
                    Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Post
                }
            }

            'Wipe'
            {

                if($WhatIf){
                    Write-Host "Wipe of the device $DeviceID was cancelled..."
                }
                else {
                    write-host "Wiping this device..."
                    $Resource = "deviceManagement/managedDevices/$DeviceID/wipe"
                    $uri = "https://graph.microsoft.com/$graphApiVersion/$($resource)"
                    write-verbose $uri
                    Write-Verbose "Sending wipe command to $DeviceID"
                    Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Post
                }
            }

            'Retire'
            {
                if($WhatIf){
                    Write-Host "Retire of the device $DeviceID was cancelled..."
                }
                else {
                    write-host "Retiring this device..."
                    $Resource = "deviceManagement/managedDevices/$DeviceID/retire"
                    $uri = "https://graph.microsoft.com/$graphApiVersion/$($resource)"
                    write-verbose $uri
                    Write-Verbose "Sending retire command to $DeviceID"
                    Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Post
                }
            }

            'Delete'
            {
                Write-Warning "A deletion of a device will only work if the device has already had a retire or wipe request sent to the device..."

                if($WhatIf){
                    Write-Host "Deletion of the device $DeviceID was cancelled..."
                }
                else {
                    write-host "Deleting this device..."
                    $Resource = "deviceManagement/managedDevices('$DeviceID')"
                    $uri = "https://graph.microsoft.com/$graphApiVersion/$($resource)"
                    write-verbose $uri
                    Write-Verbose "Sending delete command to $DeviceID"
                    Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Delete

                }
            }

            'Sync'
            {

                if($WhatIf){
                    Write-Host "Sync of the device $DeviceID was cancelled..."
                }
                else {
                    $Resource = "deviceManagement/managedDevices('$DeviceID')/syncDevice"
                    $uri = "https://graph.microsoft.com/$graphApiVersion/$($resource)"
                    write-verbose $uri
                    Write-Verbose "Sending sync command to $DeviceID"
                    Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Post
                }
            }

            'Rename'
            {
                if($WhatIf){
                    Write-Host "Rename of the device $DeviceID was cancelled..."
                }
                else {
                    If($Null -eq $NewDeviceName){Break}

                    $JSON = @"
                    {
                        deviceName:"$($NewDeviceName)"
                    }
"@
                    $Resource = "deviceManagement/managedDevices('$DeviceID')/setDeviceName"
                    $uri = "https://graph.microsoft.com/$graphApiVersion/$($resource)"
                    write-verbose $uri
                    Write-Verbose "Sending rename command to $DeviceID"
                    Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Post -Body $Json -ContentType "application/json"
                }
            }

            default {
                write-host "No parameter set, specify -RemoteLock -ResetPasscode -Wipe -Delete -Sync or -rename against the function" -f Red
            }
        }
    }
    catch {
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        write-host
        break
    }
}




Function Set-ManagedDevice{

    <#
    .SYNOPSIS
    This function is used to set Managed Device property from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and sets a Managed Device property
    .EXAMPLE
    Set-ManagedDevice -id $id -ownerType company
    Returns Managed Devices configured in Intune
    .NOTES
    NAME: Set-ManagedDevice
    #>

    [cmdletbinding()]

    param
    (
        $id,
        $ownertype
    )

    $graphApiVersion = "Beta"
    $Resource = "deviceManagement/managedDevices"

    try {
        if($id -eq "" -or $id -eq $null){
            write-host "No Device id specified, please provide a device id..." -f Red
            break
        }

        if($ownerType -eq "" -or $ownerType -eq $null){
            write-host "No ownerType parameter specified, please provide an ownerType. Supported value personal or company..." -f Red
            Write-Host
            break
        }
        elseif($ownerType -eq "company"){

            $JSON = @"
            {
                ownerType:"company"
            }
"@
            write-host
            write-host "Are you sure you want to change the device ownership to 'company' on this device? Y or N?"
            $Confirm = read-host

            if($Confirm -eq "y" -or $Confirm -eq "Y"){
                # Send Patch command to Graph to change the ownertype
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$ID')"
                Invoke-RestMethod -Uri $uri -Headers $authToken -Method Patch -Body $Json -ContentType "application/json"
            }
            else {
                Write-Host "Change of Device Ownership for the device $ID was cancelled..." -ForegroundColor Yellow
                Write-Host
            }
        }
        elseif($ownerType -eq "personal"){
            $JSON = @"
            {
                ownerType:"personal"
            }
"@
            write-host
            write-host "Are you sure you want to change the device ownership to 'personal' on this device? Y or N?"
            $Confirm = read-host

            if($Confirm -eq "y" -or $Confirm -eq "Y"){
                # Send Patch command to Graph to change the ownertype
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$ID')"
                Invoke-RestMethod -Uri $uri -Headers $authToken -Method Patch -Body $Json -ContentType "application/json"
            }
            else {
                Write-Host "Change of Device Ownership for the device $ID was cancelled..." -ForegroundColor Yellow
                Write-Host
            }
        }
    }
    catch {
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        write-host
        break
    }
}


Function Get-IntuneAutopilotDevice{
    <#
    .SYNOPSIS
    Gets devices currently registered with Windows Autopilot.
     
    .DESCRIPTION
    The Get-AutopilotDevice cmdlet retrieves either the full list of devices registered with Windows Autopilot for the current Azure AD tenant, or a specific device if the ID of the device is specified.
     
    .PARAMETER id
    Optionally specifies the ID (GUID) for a specific Windows Autopilot device (which is typically returned after importing a new device)
     
    .PARAMETER serial
    Optionally specifies the serial number of the specific Windows Autopilot device to retrieve
    
    .PARAMETER expand
    Expand the properties of the device to include the Autopilot profile information

    .EXAMPLE
    Get a list of all devices registered with Windows Autopilot
     
    Get-AutopilotDevice
    #>
        [cmdletbinding()]
        param
        (
            [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$True)] $id,
            [Parameter(Mandatory=$false)] $serial,
            [Parameter(Mandatory=$false)] [Switch]$expand = $false
        )
    
        Process {
    
            # Defining Variables
            $graphApiVersion = "beta"
            $Resource = "deviceManagement/windowsAutopilotDeviceIdentities"
        
            if ($id -and $expand) {
                $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)/$($id)?`$expand=deploymentProfile,intendedDeploymentProfile"
            }
            elseif ($id) {
                $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)/$id"
            }
            elseif ($serial) {
                $encoded = [uri]::EscapeDataString($serial)
                $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$filter=contains(serialNumber,'$encoded')"
            }
            else {
                $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
            }
    
            Write-Verbose "GET $uri"
    
            try {
                $response = Invoke-RestMethod -Uri $uri -Headers $header -Method Get -ContentType "application/json"
                $response = Invoke-MSGraphRequest -Url $uri -HttpMethod Get
                if ($id) {
                    $response
                }
                else {
                    $devices = $response.value
                    $devicesNextLink = $response."@odata.nextLink"
        
                    while ($devicesNextLink -ne $null){
                        $devicesResponse = (Invoke-MSGraphRequest -Url $devicesNextLink -HttpMethod Get)
                        $devicesNextLink = $devicesResponse."@odata.nextLink"
                        $devices += $devicesResponse.value
                    }
        
                    if ($expand) {
                        $devices | Get-AutopilotDevice -Expand
                    }
                    else
                    {
                        $devices
                    }
                }
            }
            catch {
                Write-Error $_.Exception 
                break
            }
        }
    }

<#
$windowsAutopilotDeviceIdentityId='3fc09939-ccb9-448f-b28a-ed768c8c16e0'
$windowsAutopilotDeploymentProfileAssignmentId=
    $Resource = "deviceManagement/windowsAutopilotDeviceIdentities"
    $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$windowsAutopilotDeviceIdentityId"

    $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$windowsAutopilotDeviceIdentityId/deploymentProfile/assignments/$windowsAutopilotDeploymentProfileAssignmentId"

    Invoke-RestMethod -Uri $uri -Headers $global:AuthToken -Method Get -ContentType "application/json"


# https://byteben.com/bb/using-powershell-with-intune-graph-to-query-devices/

# TESTS
$IntuneConnection = Connect-MSGraph -AdminConsent
$TenantID = $IntuneConnection.TenantId
$global:AuthToken = Get-AuthToken -User $IntuneConnection.UPN
$DeviceID = '4eff0579-a80f-4c84-85db-d3c64a27849b'

$Resource = "deviceManagement/managedDevices/$DeviceID"
$Resource = "deviceManagement/manageddevices('$DeviceID')?`$select=userId"
$uri = "https://graph.microsoft.com/Beta/$($resource)"

$Resource = "deviceManagement/managedDevices"
$uri = "https://graph.microsoft.com/Beta/$($resource)"

Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get


#>
