
Function Get-IDMAutopilotProfile{
    <#
    .SYNOPSIS
    Gets Windows Autopilot profile details.

    .DESCRIPTION
    The Get-AutopilotProfile cmdlet returns either a list of all Windows Autopilot profiles for the current Azure AD tenant, or information for the specific profile specified by its ID.

    .PARAMETER id
    Optionally, the ID (GUID) of the profile to be retrieved.

    .EXAMPLE
    Get a list of all Windows Autopilot profiles.

    Get-AutopilotProfile
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$false)]
        $id,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/windowsAutopilotDeploymentProfiles"

    if ($id) {
        $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource/$id"
    }
    else {
        $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"
    }

    Write-Verbose "GET $uri"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get
        if ($id) {
            $response
        }
        else {
            $devices = $response.value

            $devicesNextLink = $response."@odata.nextLink"

            while ($devicesNextLink -ne $null){
                $devicesResponse = (Invoke-RestMethod -Uri $devicesNextLink -Headers $AuthToken -Method Get)
                $devicesNextLink = $devicesResponse."@odata.nextLink"
                $devices += $devicesResponse.value
            }

            $devices
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
        break
    }
}




Function Get-IDMAutopilotDevice{
    <#
    .SYNOPSIS
    Gets devices currently registered with Windows Autopilot.

    .DESCRIPTION
    The Get-IDMAutopilotDevice cmdlet retrieves either the full list of devices registered with Windows Autopilot for the current Azure AD tenant, or a specific device if the ID of the device is specified.

    .PARAMETER id
    Optionally specifies the ID (GUID) for a specific Windows Autopilot device (which is typically returned after importing a new device)

    .PARAMETER serial
    Optionally specifies the serial number of the specific Windows Autopilot device to retrieve

    .PARAMETER expand
    Expand the properties of the device to include the Autopilot profile information

    .EXAMPLE
    Get a list of all devices registered with Windows Autopilot

    Get-IDMAutopilotDevice
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$True)]
        $id,

        [Parameter(Mandatory=$false)]
        $serial,

        [Parameter(Mandatory=$false)]
        [Switch]$expand,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
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
            $response = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get
            if ($id) {
                $response
            }
            else {
                $devices = $response.value
                $devicesNextLink = $response."@odata.nextLink"

                while ($devicesNextLink -ne $null){
                    $devicesResponse = (Invoke-RestMethod -Uri $devicesNextLink -Headers $AuthToken -Method Get)
                    $devicesNextLink = $devicesResponse."@odata.nextLink"
                    $devices += $devicesResponse.value
                }

                if ($expand) {
                    $devices | Get-IDMAutopilotDevice -Expand
                }
                else
                {
                    $devices
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
            break
        }
    }
}


Function Set-IDMAutopilotDeviceTag{
    <#
    .SYNOPSIS
    Updates grouptag for Autopilot device.

    .DESCRIPTION
    The Set-IDMAutopilotDeviceTag cmdlet can be used to change the updatable properties on a Windows Autopilot device object.

    .PARAMETER id
    The Windows Autopilot device id (mandatory).

    .PARAMETER userPrincipalName
    The user principal name.

    .PARAMETER addressibleUserName
    The name to display during Windows Autopilot enrollment. If specified, the userPrincipalName must also be specified.

    .PARAMETER displayName
    The name (computer name) to be assigned to the device when it is deployed via Windows Autopilot. This is presently only supported with Azure AD Join scenarios. Note that names should not exceed 15 characters. After setting the
    name, you need to initiate a sync (Invoke-AutopilotSync) in order to see the name in the Intune object.

    .PARAMETER groupTag
    The group tag value to set for the device.

    .EXAMPLE
    Assign a user and a name to display during enrollment to a Windows Autopilot device.

    Set-IDMAutopilotProfileTag -AutopilotID $id -GroupTag "Testing"
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$True)]
        $AutopilotID,

        [Parameter(Mandatory=$false)]
        $GroupTag = $null,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )
    Begin{
         # Defining Variables
         $graphApiVersion = "beta"
         $Resource = "deviceManagement/windowsAutopilotDeviceIdentities"
    }
    Process {
        #TEST $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/c50d642a-e8d7-4f84-9dc2-3540303b1acf/UpdateDeviceProperties"
        $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource/$AutopilotID/UpdateDeviceProperties"

        $requestBody = @{ groupTag = $groupTag }
        $BodyJson = $requestBody | ConvertTo-Json

        <#
        $BodyJson = "{"
        $BodyJson += " groupTag: `"$groupTag`""
        $BodyJson += " }"
        #>

        try {
            Write-Verbose "GET $uri"
            $null = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Body $BodyJson -Method POST
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
