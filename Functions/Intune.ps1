Function Get-IDMDevice{

    <#
    .SYNOPSIS
    This function is used to get Intune Managed Devices from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any Intune Managed Device
    .EXAMPLE
    Get-IDMDevice
    Returns all managed devices but excludes EAS devices registered within the Intune Service
    .EXAMPLE
    Get-IDMDevice -IncludeEAS
    Returns all managed devices including EAS devices registered within the Intune Service
    .NOTES
    NAME: Get-IDMDevice
    #>

    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$false)]
        [ValidateSet('Windows','Android','MacOS','iOS')]
        [string]$Platform,

        [Parameter(Mandatory=$false)]
        [string]$Filter,

        [Parameter(Mandatory=$false)]
        [switch]$IncludeEAS,

        [Parameter(Mandatory=$false)]
        [switch]$ExcludeMDM,

        [Parameter(Mandatory=$false)]
        [switch]$Expand,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/managedDevices"

    $Query = @()
    $Count_maParams = 0
    if($IncludeEAS.IsPresent){$Count_maParams++}

    if($ExcludeMDM.IsPresent){
        $Count_maParams++
        $Query += "managementAgent eq 'eas'"
    }

    if($IncludeEAS -eq $false -and $ExcludeMDM -eq $false){
        $Query += "managementAgent eq 'easmdm'"
        $Query += "managementAgent eq 'mdm'"
        Write-Warning "EAS Devices are excluded by default, please use -IncludeEAS if you want to include those devices"
    }

    If($PSBoundParameters.ContainsKey('Filter')){
        $Query += "contains(deviceName,'$($Filter)')"
    }

    If($PSBoundParameters.ContainsKey('Platform')){
        $Query += "operatingSystem eq '$($Platform)'"
    }

    $filterQuery = "`?`$filter=" + ($Query -join ' and ')

    if($Count_maParams -gt 1){
        write-error "Multiple parameters set, specify a single parameter -IncludeEAS, -ExcludeMDM or no parameter against the function"
    }
    else {
        $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource" + $filterQuery
    }

    try {
        Write-Verbose "Get $uri"
        $Response = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
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
    }


    If($Expand)
    {
        $Devices = @()
        $AADObjects = Get-IDMAzureDevices -AuthToken $AuthToken
        #TEST $Item = $Response.Value | Where deviceName -eq 'DTOLAB-46VEYL1'
        Foreach($Item in $Response.Value)
        {
            $OutputItem = New-Object PSObject
            Foreach($p in $Item | Get-Member -MemberType NoteProperty){
                $OutputItem | Add-Member NoteProperty $p.name -Value $Item.($p.name)
            }
            #$AADObjects | Where displayName -eq 'DTOLAB-46VEYL1'
            If($FilteredObj = $AADObjects | Where deviceId -eq $Item.azureADDeviceId){
                # Create a new object to store this information
                $OutputItem | Add-Member NoteProperty "azureADObjectId" -Value $FilteredObj.id -Force
                $OutputItem | Add-Member NoteProperty "accountEnabled" -Value $FilteredObj.accountEnabled -Force
                $OutputItem | Add-Member NoteProperty "deviceVersion" -Value $FilteredObj.deviceVersion -Force
                $OutputItem | Add-Member NoteProperty "enrollmentProfileName" -Value $FilteredObj.enrollmentProfileName -Force
                $OutputItem | Add-Member NoteProperty "enrollmentType" -Value $FilteredObj.enrollmentType -Force
                $OutputItem | Add-Member NoteProperty "isCompliant" -Value $FilteredObj.isCompliant -Force
                $OutputItem | Add-Member NoteProperty "mdmAppId" -Value $FilteredObj.mdmAppId -Force
                $OutputItem | Add-Member NoteProperty "physicalIds" -Value $FilteredObj.physicalIds -Force
                $OutputItem | Add-Member NoteProperty "extensionAttributes " -Value $FilteredObj.extensionAttributes -Force
                # Add the object to our array of output objects
            }
            $Devices += $OutputItem
        }
    }
    Else{
        $Devices = $Response.Value
    }

    return $Devices
}


Function Get-IDMAzureDevices{
<#
    .SYNOPSIS
    This function is used to get Azure Devices from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any Azure Device

    #>

    [cmdletbinding()]
    param
    (

        [Parameter(Mandatory=$false)]
        [ValidateSet('DisplayName','StartWithDisplayName','NOTStartWithDisplayName')]
        [string]$FilterBy,

        [Parameter(Mandatory=$false)]
        [string]$Filter,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )
    Begin{
        # Defining Variables
        $graphApiVersion = "beta"

        If($FilterBy -and $Filter){
            switch($FilterBy){
                'DisplayName' {$uri = "https://graph.microsoft.com/beta/devices?`$filter=displayName eq '$Filter'"}

                'StartWithDisplayName' {$uri = "https://graph.microsoft.com/beta/devices?`$filter=startswith(displayName, '$Filter')"}

                'NOTStartWithDisplayName'{ $uri = "https://graph.microsoft.com/beta/devices?`$filter=NOT startsWith(displayName, '$Filter')"}
            }

        }Else{
            $uri = "https://graph.microsoft.com/$graphApiVersion/devices"
        }

    }
    Process{
        try {
            Write-Verbose "Get $uri"
            $Response = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
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
        }
    }
    End{
        return $Response.Value
    }

}


Function Get-IDMDevicePendingActions{

    <#
    .SYNOPSIS
    This function is used to get a Managed Device pending Actions
    .DESCRIPTION
    The function connects to the Graph API Interface and gets a managed device pending actions
    .EXAMPLE

    Returns a managed device user registered in Intune
    .NOTES
    NAME:
    #>

    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,HelpMessage="DeviceID (guid) for the device on must be specified:")]
        $DeviceID,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )
    Begin{
        # Defining Variables
        $graphApiVersion = "beta"
    }
    Process{
        $Resource = "deviceManagement/manageddevices/$DeviceID"

        try {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
            Write-Verbose "Get $uri"
            $response = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
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
        }
    }
    End{
        return $response.deviceActionResults
    }
}

Function Get-IDMDeviceAssignedUser{

    <#
    .SYNOPSIS
    This function is used to get a Managed Device username from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets a managed device users registered with Intune MDM
    .EXAMPLE
    Get-IDMDeviceAssignedUser -DeviceID $DeviceID
    Returns a managed device user registered in Intune
    .NOTES
    NAME: Get-IDMDeviceAssignedUser
    #>

    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true)]
        [Parameter(HelpMessage="DeviceID (guid) for the device on must be specified:")]
        $DeviceID,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )
    Begin{
        # Defining Variables
        $graphApiVersion = "beta"
    }
    Process{
        $Resource = "deviceManagement/manageddevices('$DeviceID')?`$select=userId"

        try {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
            Write-Verbose "Get $uri"
            $response = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
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
        }
    }
    End{
        return $response.userId
    }
}


#region
Function Get-IDMDeviceAADUser{

    <#
    .SYNOPSIS
    This function is used to get AAD Users from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any users registered with AAD
    .EXAMPLE
    Get-IDMDeviceAADUser
    Returns all users registered with Azure AD
    .EXAMPLE
    Get-IDMDeviceAADUser -userPrincipleName user@domain.com
    Returns specific user by UserPrincipalName registered with Azure AD
    .NOTES
    NAME: Get-IDMDeviceAADUser
    https://docs.microsoft.com/en-us/graph/api/user-get?view=graph-rest-1.0&tabs=http
    #>

    [CmdletBinding(DefaultParameterSetName='ID')]
    Param
    (
        [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,ParameterSetName='ID')]
        [string]$Id,

        [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,ParameterSetName='UPN')]
        [Alias('User','EMail')]
        [System.Net.Mail.MailAddress]$UPN,

        [Parameter(Mandatory=$false)]
        [ValidateSet('id','userPrincipalName','surname','officeLocation','mail','displayName','givenName')]
        [String]$Property,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )
    Begin{
        # Defining Variables
        $graphApiVersion = "beta"
        $User_resource = "users"
    }
    Process{
        If ($PSCmdlet.ParameterSetName -eq "ID"){
            $QueryBy = $Id
        }
        If ($PSCmdlet.ParameterSetName -eq "UPN"){
            $QueryBy = $UPN
        }
        try {
            #Grab All directory syncd users
            #$uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)/?`$filter=onPremisesSyncEnabled+eq+true"
            #$DirUsers = (Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get).Value

            if([string]::IsNullOrEmpty($QueryBy))
            {
                $uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)"
                Write-Verbose $uri
                $Response = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
            }
            else {
                if([string]::IsNullOrEmpty($Property)){
                    $uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)/$QueryBy"
                    Write-Verbose $uri
                    $Response = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
                }
                else {
                    $uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)/$QueryBy/$Property"
                    Write-Verbose $uri
                    $Response = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
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
        }
    }
    End{
        return $response
    }
}


Function Get-IDMDeviceCategory{
    <#
    .SYNOPSIS
    Gets Device Category details.

    .DESCRIPTION
    The Get-IDMDeviceCategory cmdlet returns either a list of all categories for the current Azure AD tenant, or information for the specific profile specified by its ID.

   .EXAMPLE
    Get a list of all Device Categories.

    Get-IDMDeviceCategory
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/deviceCategories"

    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"

    try {
        Write-Verbose "GET $uri"
        $response = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get
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
    }
    Finally{
        $response.Value
    }
}


Function Set-IDMDeviceCategory{
    <#
    .SYNOPSIS
    Sets Device Category

    .DESCRIPTION
    The Set-IDMDeviceCategory cmdlet sets the category of device ID

    .EXAMPLE
    Set-IDMDeviceCategory -DeviceID '08d06b3b-8513-417b-80ee-9dc8a3beb377' -Category 'Standard Device'

    .LINK
    Get-IDMDeviceCategory
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        $DeviceID,

        [Parameter(Mandatory=$true)]
        $Category,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/managedDevices"

    $Categories = Get-IDMDeviceCategory -AuthToken $AuthToken
    $CategoryId = ($Categories | Where displayName -eq $Category).id

    #$requestBody = @{ "@odata.id" = "https://graph.microsoft.com/$graphApiVersion/deviceManagement/deviceCategories/3137f37d-ff7c-48ec-af57-d4404faf844e" }
    $requestBody = @{ "@odata.id" = "https://graph.microsoft.com/$graphApiVersion/deviceManagement/deviceCategories/$CategoryId" }
    $BodyJson = $requestBody | ConvertTo-Json

    #$uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/08d06b3b-8513-417b-80ee-9dc8a3beb377/deviceCategory/`$ref"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource/$DeviceID/deviceCategory/`$ref"

    try {
        Write-Verbose "GET $uri"
        $null = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Body $BodyJson -Method PUT
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
    }
}


Function Invoke-IDMDeviceAction{
    <#
    .SYNOPSIS
    This function is used to set a generic intune resources from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and sets a generic Intune Resource
    .EXAMPLE
    Invoke-IDMDeviceAction -DeviceID $DeviceID -remoteLock
    Resets a managed device passcode
    .NOTES
    NAME: Invoke-IDMDeviceAction
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param
    (
        [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,HelpMessage="DeviceId (guid) for the Device you want to take action on must be specified:")]
        $DeviceID,

        [Parameter(Mandatory=$true)]
        [ValidateSet('RemoteLock','ResetPasscode','Wipe','Retire','Delete','Sync','Rename')]
        $Action,

        [switch]$Force,

        $NewDeviceName,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

        if (-not $PSBoundParameters.ContainsKey('Verbose')) {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }

        if (-not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ConfirmPreference')
        }

        if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue('WhatIfPreference')
        }
        $graphApiVersion = "Beta"
    }
    Process{
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
                    If($WhatIfPreference)
                    {
                        Write-Host "Reset of the Passcode for the device $DeviceID was cancelled..."
                    }
                    else {
                        write-host "Resetting the Passcode this device..."
                        $Resource = "deviceManagement/managedDevices/$DeviceID/resetPasscode"
                        $uri = "https://graph.microsoft.com/$graphApiVersion/$($resource)"
                        write-verbose $uri
                        Write-Verbose "Sending remotePasscode command to $DeviceID"
                        Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Post
                    }
                }

                'Wipe'
                {

                    If($WhatIfPreference)
                    {
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
                    If($WhatIfPreference)
                    {
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

                    If($WhatIfPreference)
                    {
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

                    If($WhatIfPreference)
                    {
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
                    If($WhatIfPreference)
                    {
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
        }
    }


}




Function Set-IDMManagedDevice{

    <#
    .SYNOPSIS
    This function is used to set Managed Device property from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and sets a Managed Device property
    .EXAMPLE
    Set-IDMManagedDevice -id $Id -ownerType company
    Returns Managed Devices configured in Intune
    .NOTES
    NAME: Set-IDMManagedDevice
    #>

    [cmdletbinding()]

    param
    (
        [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true)]
        $Id,

        [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true)]
        [ValidateSet('Personal','Company')]
        $OwnerType,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken,

        [Parameter(Mandatory=$false)]
        $Force
    )
    Begin{
        $graphApiVersion = "Beta"
        $Resource = "deviceManagement/managedDevices"
        $JSON = @"
        {
            ownerType:"$($OwnerType)"
        }
"@
    }
    Process{
        If(!$Force)
        {
            write-host ("Are you sure you want to change the device ownership to '{0}' on this device? [Y or N]" -f $OwnerType)
            $Confirm = read-host

            if($Confirm -ne "y" -and $Confirm -ne "Y"){
                Write-Host ("Change of Device Ownership for the device {0} was cancelled..." -f $Id) -ForegroundColor Yellow
                Continue
            }
        }

        try {
            # Send Patch command to Graph to change the ownertype
            $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$Id')"
            Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Patch -Body $Json -ContentType "application/json"
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
        }
    }
}



Function Remove-IDMDeviceRecords{
    [CmdletBinding(DefaultParameterSetName='All')]
    Param
    (
        [Parameter(ParameterSetName='All',Mandatory=$true,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Individual',Mandatory=$true,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true)]
        $ComputerName,
        [Parameter(ParameterSetName='All')]
        [switch]$All,
        [Parameter(ParameterSetName='Individual')]
        [switch]$AD,
        [Parameter(ParameterSetName='Individual')]
        [switch]$AAD,
        [Parameter(ParameterSetName='Individual')]
        [switch]$Intune,
        [Parameter(ParameterSetName='Individual')]
        [switch]$Autopilot,
        [Parameter(ParameterSetName='Individual')]
        [switch]$ConfigMgr,
        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )

    Set-Location $env:SystemDrive

    # Load required modules
    If ($PSBoundParameters.ContainsKey("AAD") -or $PSBoundParameters.ContainsKey("Intune") -or $PSBoundParameters.ContainsKey("Autopilot") -or $PSBoundParameters.ContainsKey("ConfigMgr") -or $PSBoundParameters.ContainsKey("All"))
    {
        Try
        {
            Write-host "Importing modules…" -NoNewline
            If ($PSBoundParameters.ContainsKey("AAD") -or $PSBoundParameters.ContainsKey("Intune") -or $PSBoundParameters.ContainsKey("Autopilot") -or $PSBoundParameters.ContainsKey("All"))
            {
                Import-Module Microsoft.Graph.Intune -ErrorAction Stop
            }
            If ($PSBoundParameters.ContainsKey("AAD") -or $PSBoundParameters.ContainsKey("All"))
            {
                Import-Module AzureAD -ErrorAction Stop
            }
            If ($PSBoundParameters.ContainsKey("ConfigMgr") -or $PSBoundParameters.ContainsKey("All"))
            {
                Import-Module $env:SMS_ADMIN_UI_PATH.Replace('i386','ConfigurationManager.psd1') -ErrorAction Stop
            }
            Write-host "Success" -ForegroundColor Green
        }
        Catch
        {
            Write-host "$($_.Exception.Message)" -ForegroundColor Red
            Return
        }
    }

    Write-host "$($ComputerName.ToUpper())" -ForegroundColor Yellow
    Write-Host "===============" -ForegroundColor Yellow

    # Delete from AD
    If ($PSBoundParameters.ContainsKey("AD") -or $PSBoundParameters.ContainsKey("All"))
    {
        Try
        {
            Write-host "Retrieving " -NoNewline
            Write-host "Active Directory " -ForegroundColor Yellow -NoNewline
            Write-host "computer account…" -NoNewline
            $Searcher = [ADSISearcher]::new()
            $Searcher.Filter = "(sAMAccountName=$ComputerName`$)"
            [void]$Searcher.PropertiesToLoad.Add("distinguishedName")
            $ComputerAccount = $Searcher.FindOne()
            If ($ComputerAccount)
            {
                Write-host "Success" -ForegroundColor Green
                Write-Host "   Deleting computer account…" -NoNewline
                $DirectoryEntry = $ComputerAccount.GetDirectoryEntry()
                $Result = $DirectoryEntry.DeleteTree()
                Write-Host "Success" -ForegroundColor Green
            }
            Else
            {
                Write-host "Not found!" -ForegroundColor Red
            }
        }
        Catch
        {
            Write-host "Error!" -ForegroundColor Red
            $_
        }
    }

    # Delete from Azure AD
    If ($PSBoundParameters.ContainsKey("AAD") -or $PSBoundParameters.ContainsKey("All"))
    {
        Try
        {
            Write-host "Retrieving " -NoNewline
            Write-host "Azure AD " -ForegroundColor Yellow -NoNewline
            Write-host "device record/s…" -NoNewline
            [array]$AzureADDevices = Get-IDMAzureDevices -Filter $ComputerName -AuthToken $AuthToken -ErrorAction Stop
            If ($AzureADDevices.Count -ge 1)
            {
                Write-Host "Success" -ForegroundColor Green
                Foreach ($AzureADDevice in $AzureADDevices)
                {
                    Write-host "   Deleting DisplayName: $($AzureADDevice.DisplayName)  |  ObjectId: $($AzureADDevice.ObjectId)  |  DeviceId: $($AzureADDevice.DeviceId) …" -NoNewline
                    Remove-IDMAzureDevices -ObjectId $AzureADDevice.ObjectId -ErrorAction Stop
                    Write-host "Success" -ForegroundColor Green
                }
            }
            Else
            {
                Write-host "Not found!" -ForegroundColor Red
            }
        }
        Catch
        {
            Write-host "Error!" -ForegroundColor Red
            $_
        }
    }

    # Delete from Intune
    If ($PSBoundParameters.ContainsKey("Intune") -or $PSBoundParameters.ContainsKey("Autopilot") -or $PSBoundParameters.ContainsKey("All"))
    {
        Try
        {
            Write-host "Retrieving " -NoNewline
            Write-host "Intune " -ForegroundColor Yellow -NoNewline
            Write-host "managed device record/s…" -NoNewline
            [array]$IntuneDevices = Get-IntuneManagedDevice -Filter "deviceName eq '$ComputerName'" -ErrorAction Stop
            If ($IntuneDevices.Count -ge 1)
            {
                Write-Host "Success" -ForegroundColor Green
                If ($PSBoundParameters.ContainsKey("Intune") -or $PSBoundParameters.ContainsKey("All"))
                {
                    foreach ($IntuneDevice in $IntuneDevices)
                    {
                        Write-host "   Deleting DeviceName: $($IntuneDevice.deviceName)  |  Id: $($IntuneDevice.Id)  |  AzureADDeviceId: $($IntuneDevice.azureADDeviceId)  |  SerialNumber: $($IntuneDevice.serialNumber) …" -NoNewline
                        Remove-IntuneManagedDevice -managedDeviceId $IntuneDevice.Id -Verbose -ErrorAction Stop
                        Write-host "Success" -ForegroundColor Green
                    }
                }
            }
            Else
            {
                Write-host "Not found!" -ForegroundColor Red
            }
        }
        Catch
        {
            Write-host "Error!" -ForegroundColor Red
            $_
        }
    }

    # Delete Autopilot device
    If ($PSBoundParameters.ContainsKey("Autopilot") -or $PSBoundParameters.ContainsKey("All"))
    {
        If ($IntuneDevices.Count -ge 1)
        {
            Try
            {
                Write-host "Retrieving " -NoNewline
                Write-host "Autopilot " -ForegroundColor Yellow -NoNewline
                Write-host "device registration…" -NoNewline
                $AutopilotDevices = New-Object System.Collections.ArrayList
                foreach ($IntuneDevice in $IntuneDevices)
                {
                    $URI = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$($IntuneDevice.serialNumber)')"
                    $AutopilotDevice = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
                    [void]$AutopilotDevices.Add($AutopilotDevice)
                }
                Write-Host "Success" -ForegroundColor Green

                foreach ($device in $AutopilotDevices)
                {
                    Write-host "   Deleting SerialNumber: $($Device.value.serialNumber)  |  Model: $($Device.value.model)  |  Id: $($Device.value.id)  |  GroupTag: $($Device.value.groupTag)  |  ManagedDeviceId: $($device.value.managedDeviceId) …" -NoNewline
                    $URI = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($device.value.Id)"
                    $AutopilotDevice = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Delete -ErrorAction Stop
                    Write-Host "Success" -ForegroundColor Green
                }
            }
            Catch
            {
                Write-host "Error!" -ForegroundColor Red
                $_
            }
        }
    }

    # Delete from ConfigMgr
    If ($PSBoundParameters.ContainsKey("ConfigMgr") -or $PSBoundParameters.ContainsKey("All"))
    {
        Try
        {
            Write-host "Retrieving " -NoNewline
            Write-host "ConfigMgr " -ForegroundColor Yellow -NoNewline
            Write-host "device record/s…" -NoNewline
            $SiteCode = (Get-PSDrive -PSProvider CMSITE -ErrorAction Stop).Name
            Set-Location ("$SiteCode" + ":") -ErrorAction Stop
            [array]$ConfigMgrDevices = Get-CMDevice -Name $ComputerName -Fast -ErrorAction Stop
            Write-Host "Success" -ForegroundColor Green
            foreach ($ConfigMgrDevice in $ConfigMgrDevices)
            {
                Write-host "   Deleting Name: $($ConfigMgrDevice.Name)  |  ResourceID: $($ConfigMgrDevice.ResourceID)  |  SMSID: $($ConfigMgrDevice.SMSID)  |  UserDomainName: $($ConfigMgrDevice.UserDomainName) …" -NoNewline
                Remove-CMDevice -InputObject $ConfigMgrDevice -Force -ErrorAction Stop
                Write-Host "Success" -ForegroundColor Green
            }
        }
        Catch
        {
            Write-host "Error!" -ForegroundColor Red
            $_
        }
    }

}


Function Get-IDMIntuneAssignments{
    Param(

        [Parameter(Mandatory=$true)]
        [string]$TargetId,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Devices','Users','Both')]
        [string]$Target = 'Both',

        [Parameter(Mandatory=$false)]
        [ValidateSet('Windows','Android','MacOS','iOS')]
        [string]$Platform = 'Windows',

        [Parameter(Mandatory=$false)]
        [switch]$IncludePolicySetInherits,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )

    <#SAMPLE
    $AuthToken = $synchash.data.AuthToken
    $TargetId = '6e8d5d00-6fff-46df-8d61-337399a3c123'
    $TargetId = 'b215decf-4188-4d19-9e22-fb2e89ae0fec'
    $TargetId = 'b215decf-4188-4d19-9e22-fb2e89ae0fec'
    #>
    $graphApiVersion = "beta"

    #First get all Azure AD groups this device is a member of.
    $Resources = @()
    If($Target -eq 'Both')
    {
        $Resources += 'devices'
        $Resources += 'users'
    }
    Else{
        $Resources += $Target.ToLower()
    }

    #loop though each resource
    #TEST $Resource = 'devices'
    Foreach($Resource in $Resources)
    {
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)/$TargetId/memberOf"
        $DeviceGroups = (Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get).value
        $MemberOfGroups = $DeviceGroups | Select id, displayName,@{N='GroupType';E={If('DynamicMembership' -in $_.groupTypes){return 'Dynamic'}Else{return 'Static'} }}

        #loop through each Intune Component, then get assignments for each
        Switch($Platform){
            'Windows' {
                    $PlatformType = @('microsoftStore',
                                    'win32LobApp',
                                    'windows',
                                    'officeSuiteApp',
                                    'sharedPC',
                                    'editionUpgrade',
                                    'webApp'
                    )

                    $Resources = @{
                        'Compliance Policy' = 'deviceManagement/deviceCompliancePolicies'
                        'Compliance Scripts' = 'deviceManagement/deviceComplianceScripts'
                        'Configuration Profile' = 'deviceManagement/deviceConfigurations'
                        'Enrollment Configuration' = 'deviceManagement/deviceEnrollmentConfigurations'
                        'Proactive Remediation' = 'deviceManagement/deviceHealthScripts'
                        'Powershell Scripts' = 'deviceManagement/deviceManagementScripts'
                        'Scope Tag' = 'deviceManagement/roleScopeTags'
                        'Quality Updates' = 'deviceManagement/windowsQualityUpdateProfiles'
                        'Feature Updates' = 'deviceManagement/windowsFeatureUpdateProfiles'
                        'WIP Policies' = 'deviceAppManagement/windowsInformationProtectionPolicies'
                        'MDM WIP Policies' = 'deviceAppManagement/mdmWindowsInformationProtectionPolicies'
                        'Apps' = 'deviceAppManagement/mobileApps'
                        'PolicySet' = 'deviceAppManagement/policysets'
                    }
            }

            'Android' {$PlatformType = @('android',
                                        'webApp',
                                        'aosp'
                                        )
            }

            'MacOS'   {$PlatformType = @('IOS',
                                        'macOS',
                                        'webApp'
                                        )
            }

            'iOS'     {$PlatformType = @('ios',
                                        'webApp'
                                        )
            }
        }





        $ResourceAssignments = @()
        #TEST $Resources =  @{'Apps' = 'deviceAppManagement/mobileApps'}
        #TEST $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"
        #TEST $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies"
        #TEST $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"
        #TEST $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdateProfiles"
        Foreach($ResourceItem in $Resources.GetEnumerator())
        {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($ResourceItem.Value)"
            $ResourceResult = (Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get).value
            #$ResourceResult | Select displayname, applicableDeviceType,'@odata.type' -Unique
            #Filter on Platform if it exists
            If($ResourceResult.'@odata.type'){
                $ResourceResult = ($ResourceResult | Where '@odata.type' -match ($PlatformType -join '|'))
            }



            #TEST $Item = $ResourceResult[-1]
            #TEST $Item = $ResourceResult | Where id -eq 'ca8b2b92-87fe-4a83-b0d5-1f970bae7ea4'
            #TEST $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/ca8b2b92-87fe-4a83-b0d5-1f970bae7ea4/assignments"
            #TEST $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/ae3e6923-b240-4914-ab09-76222bc926f7/assignments"
            #TEST $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts/d9954a7f-e264-4de7-af9c-28ce77c3fed6/assignments"
            #TEST $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/df48f9ac-3bdb-457e-a8f9-a9e686c6e444/assignments"
            Foreach($Item in $ResourceResult)
            {
                #Determine specifics of each item type
                Switch($Item.'@odata.type'){
                    '#microsoft.graph.windowsUpdateForBusinessConfiguration' {$ItemType = 'Windows Update for Business'}
                    '#microsoft.graph.windows10CustomConfiguration' {$ItemType = ($ResourceItem.Key + ' (Custom)')}
                    '#microsoft.graph.windowsDomainJoinConfiguration' {$ItemType = ($ResourceItem.Key + ' (Hybrid Domain Join)')}
                    '#microsoft.graph.windowsKioskConfiguration' {$ItemType = ($ResourceItem.Key + ' (Kiosk)')}
                    #microsoft.graph.windows10EndpointProtectionConfiguration
                    #microsoft.graph.windows10GeneralConfiguration
                    #microsoft.graph.windowsIdentityProtectionConfiguration
                    #microsoft.graph.windowsDefenderAdvancedThreatProtectionConfiguration
                    #microsoft.graph.windows10NetworkBoundaryConfiguration
                    #microsoft.graph.windows81TrustedRootCertificate
                    #microsoft.graph.windows10DeviceFirmwareConfigurationInterface
                    #microsoft.graph.windowsHealthMonitoringConfiguration
                    #microsoft.graph.windows81SCEPCertificateProfile
                    #microsoft.graph.sharedPCConfiguration
                    #microsoft.graph.editionUpgradeConfiguration
                    default {$ItemType = $ResourceItem.Key}
                }

                $uri = "https://graph.microsoft.com/$graphApiVersion/$($ResourceItem.Value)/$($Item.id)/assignments"
                Try{
                    $Assignments = (Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get).value

                    #TEST  $Assignment = $Assignments[0]
                    Foreach($Assignment in $Assignments)
                    {
                        $AssignmentGroup = '' | Select Name,Type,Mode,Target,Platform,Group,GroupType
                        $AssignmentGroup.Name = $Item.displayName
                        $AssignmentGroup.Type = $ItemType
                        $AssignmentGroup.Target = $Target
                        $AssignmentGroup.Platform = $Platform

                        If($Assignment.intent){
                            $AssignmentGroup.Mode = (Get-Culture).TextInfo.ToTitleCase($Assignment.intent)
                        }Else{
                            $AssignmentGroup.Mode = 'Assigned'
                        }

                        #Grab Policyset info
                        If($Assignment.source -eq 'policySets' -and $IncludePolicySetInherits){
                            $PolicySet = (Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceAppManagement/policysets/$($Assignment.sourceId)" -Headers $AuthToken -Method Get).value
                        }Else{
                            $PolicySet = $False
                        }

                        switch($Assignment.target.'@odata.type'){
                            '#microsoft.graph.allLicensedUsersAssignmentTarget' {
                                $AddToGroup = $true
                                $AssignmentGroup.Group = 'All Users'
                                #$ResourceAssignments += $AssignmentGroup
                                $AssignmentGroup.GroupType = 'Built-In'
                            }

                            '#microsoft.graph.allDevicesAssignmentTarget' {
                                $AddToGroup = $true
                                $AssignmentGroup.Group = 'All Devices'
                                $AssignmentGroup.GroupType = 'Built-In'
                            }

                            '#microsoft.graph.exclusionGroupAssignmentTarget' {
                                $AssignmentGroup.Mode = 'Excluded'
                                $TargetAssignments = $Assignment.target | Where '@odata.type' -eq '#microsoft.graph.exclusionGroupAssignmentTarget'
                                #$Group = $TargetAssignments.GroupId[-1]
                                Foreach($Group in $TargetAssignments.GroupId)
                                {
                                    If($Group -in $MemberOfGroups.id){
                                        $AddToGroup = $true
                                        $AssignmentGroup.Group = ($MemberOfGroups | Where id -eq $Group).displayName
                                        $AssignmentGroup.GroupType = ($MemberOfGroups | Where id -eq $Group).GroupType
                                    }Else{
                                        $AddToGroup = $false
                                    }
                                }
                            }

                            '#microsoft.graph.groupAssignmentTarget' {
                                $TargetAssignments = $Assignment.target | Where '@odata.type' -eq '#microsoft.graph.groupAssignmentTarget'
                                Foreach($Group in $TargetAssignments.GroupId)
                                {
                                    If($Group -in $MemberOfGroups.id){
                                        $AddToGroup = $true
                                        $AssignmentGroup.Group = ($MemberOfGroups | Where id -eq $Group).displayName
                                        $AssignmentGroup.GroupType = ($MemberOfGroups | Where id -eq $Group).GroupType
                                    }Else{
                                        $AddToGroup = $false
                                    }
                                }
                            }
                            default {$AddToGroup = $false}
                        }#end switch

                        If($AddToGroup){
                            #update assignment group columns if policy is set
                            If($PolicySet){
                                $AssignmentGroup.Mode = 'Applied (Inherited)'
                                $AssignmentGroup.Group = ($AssignmentGroup.Group + ' (' + $AssignmentGroup.GroupType + ')')
                                #$AssignmentGroup.Group = ('PolicySet: ' + $PolicySet.displayName)
                                #$AssignmentGroup.GroupType = ($AssignmentGroup.Group + ' (Inherited)')
                                $AssignmentGroup.GroupType = ('PolicySet: ' + $PolicySet.displayName)
                            }
                            $ResourceAssignments += $AssignmentGroup
                        }
                    }#end assignment groups
                }
                Catch{
                    $ex = $_.Exception
                    $errorResponse = $ex.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($errorResponse)
                    $reader.BaseStream.Position = 0
                    $reader.DiscardBufferedData()
                    $responseBody = $reader.ReadToEnd();
                    Write-Host "Response content:`n$responseBody" -f Red
                    Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
                }
            } #end Resource assignments
        } #end resources
    }#end resrouceitem loop (device and users)


    <#

    #SAMPLE DATA
    $Assignments = @()
    $Assignment = "" | Select DeviceName,AssignmentName,Type,Mode,Target,Group,GroupType
    $Assignment.DeviceName = $Device
    $Assignment.AssignmentName = 'Autopilot hybrid Join profile'
    $Assignment.Type = 'Autopilot Deployment Profile'
    $Assignment.Mode = 'Assigned'
    $Assignment.Target = $Target
    $Assignment.Group ='SG-Autopilot-Device'
    $Assignment.GroupType = 'Dynamic'
    $Assignments += $Assignment

    return $Assignments
    #>
    return $ResourceAssignments
}

Function Set-IDMResourceFriendlyName{
    Param(
        $Name,
        [AllowEmptyString()]
        [string]$LicenseType,

        $ODataType
    )

    If($LicenseType){$FriendlyName = $Name + ' (' + (Get-Culture).TextInfo.ToTitleCase($LicenseType) + ')'}Else{ $FriendlyName = $Name}

    Switch($ODataType){
        '#microsoft.graph.deviceEnrollmentWindowsHelloForBusinessConfiguration' {$FriendlyName = ('(WHfB) ' + $Name)}
        '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' {$FriendlyName = ('(ESP) ' + $Name)}
        #'#microsoft.graph.windowsUpdateForBusinessConfiguration' {$FriendlyName = ('(WUfB) ' + $Name)}
        default { $FriendlyName = $Name}
    }

    return $FriendlyName
}

Function Set-IDMResourceFriendlyType{
    Param(
        $Category,
        $ODataType
    )

    Switch($Category){
        'windowsAutopilotDeploymentProfiles' {$FriendlyType = 'Autopilot Deployment Profile'}
        'windowsFeatureUpdateProfiles' {$FriendlyType = 'Feature Updates'}
        'roleScopeTags' {$FriendlyType = 'Role Tags'}
        #'deviceEnrollmentConfigurations' {$FriendlyType = 'deviceEnrollment'}
        'windowsInformationProtectionPolicies' {$FriendlyType = 'Windows Information Protection'}
        'deviceManagementScripts' {$FriendlyType = 'PowerShell Scripts'}
        'mdmWindowsInformationProtectionPolicies' {$FriendlyType = 'Windows Information Protection'}
        'deviceCompliancePolicies' {$FriendlyType = 'Compliance Policy'}
        'deviceHealthScripts' {$FriendlyType = 'Endpoint Analytics (Proactive Remediation)'}
        'windowsQualityUpdateProfiles' {$FriendlyType = 'Quality Updates'}
        'mobileApps' {$FriendlyType = 'Apps'}
        'deviceConfigurations' {$FriendlyType = 'Configuration Profile'}
        'policysets' {$FriendlyType = 'Policy Set'}
        default {$FriendlyType = $Category}

    }

    Switch($ODataType){
        #windows
        '#microsoft.graph.azureADWindowsAutopilotDeploymentProfile' {$FriendlyType = ($FriendlyType + ' (Azure AD)')}
        '#microsoft.graph.activeDirectoryWindowsAutopilotDeploymentProfile' {$FriendlyType = ($FriendlyType + ' (Hybrid Join)')}
        '#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration' {$FriendlyType = 'Device Restrictions'}
        '#microsoft.graph.deviceEnrollmentWindowsHelloForBusinessConfiguration' {$FriendlyType = '(Autopilot) Windows Hello For Business'}
        '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' {$FriendlyType = '(Autopilot) Enrollment Status Page'}
        '#microsoft.graph.deviceComanagementAuthorityConfiguration' {$FriendlyType = '(Autopilot) Co-Management Setting'}
        '#microsoft.graph.deviceEnrollmentLimitConfiguration' {$FriendlyType = 'Device Limitation'}
        '#microsoft.graph.windowsUpdateForBusinessConfiguration' {$FriendlyType = 'Windows Update for Business'}
        '#microsoft.graph.windows10CustomConfiguration' {$FriendlyType = ($FriendlyType + ' (Custom)')}
        '#microsoft.graph.windowsDomainJoinConfiguration' {$FriendlyType = ($FriendlyType + ' (Hybrid Domain Join)')}
        '#microsoft.graph.windows10DeviceFirmwareConfigurationInterface' {$FriendlyType = ($FriendlyType + ' (DFCI)')}
        '#microsoft.graph.windowsKioskConfiguration' {$FriendlyType = ($FriendlyType + ' (Kiosk)')}
        '#microsoft.graph.sharedPCConfiguration' {$FriendlyType = ($FriendlyType + ' (Shared PC)')}
        '#microsoft.graph.editionUpgradeConfiguration' {$FriendlyType = ($FriendlyType + ' (Edition Upgrade)')}
        '#microsoft.graph.webApp' {$FriendlyType = ($FriendlyType + ' (Web Link)')}
        '#microsoft.graph.officeSuiteApp' {$FriendlyType = ($FriendlyType + ' (Office 365)')}
    }

    #Common named OData Types
    Switch -wildcard ($ODataType){
        '*ScepCertificateProfile' {$FriendlyType = ($FriendlyType + ' (SCEP)')}
        '*TrustedRootCertificate' {$FriendlyType = ($FriendlyType + ' (Certificate)')}
        '*PkcsCertificateProfile' {$FriendlyType = ($FriendlyType + ' (PKCS Certificate)')}
        '*MicrosoftEdgeApp'     {$FriendlyType = ($FriendlyType + ' (Microsoft Edge)')}
    }

    return $FriendlyType
}
