
Function Get-IDMDeviceInRunspace{

    <#
    .SYNOPSIS
    This function is used to get Intune Managed Devices from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any Intune Managed Device
    .EXAMPLE
    Get-IDMDeviceInRunspace
    Returns all managed devices but excludes EAS devices registered within the Intune Service
    .EXAMPLE
    Get-IDMDeviceInRunspace -IncludeEAS
    Returns all managed devices including EAS devices registered within the Intune Service
    .NOTES
    NAME: Get-IDMDeviceInRunspace
    #>

    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [hashtable]$Runspace,

        [Parameter(Mandatory=$true)]
        [hashtable]$ParentRunspace,

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
        $ListObject,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken
    )

    Update-IDMProgress -Runspace $Runspace -StatusMsg ("Retrieving Device list...") -Indeterminate

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

    Write-UIOutput -UIObject $ParentRunspace.Logging -Message ("Retrieving data from URI: {0}" -f $uri) -Type Info

    $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
        try {
            $Runspace.GraphData.MDMDevices = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
        }
        catch {
            $ex = $_.Exception
            $errorResponse = $ex.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorResponse)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $responseBody = $reader.ReadToEnd();
            $message = ("Request to {0} failed with HTTP Status {1} {2}" -f $uri,$ex.Response.StatusCode,$ex.Response.StatusDescription)

            Update-IDMProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Response content: {0}" -f $responseBody) -Color Red

            Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message $message -Type Error
        }
    })

    If($Expand)
    {
        $i=0
        $Devices = @()
        #Populate AAD devices
        Get-IDMAzureDevicesInRunspace -Runspace $Runspace -ParentRunspace $Runspace -AuthToken $AuthToken

        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{

            $Runspace.Data.IntuneDevices = @()

            #TEST $Resource = $Response.Value | Where deviceName -eq 'DTOLAB-46VEYL1'
            Foreach($Resource in $Runspace.GraphData.MDMDevices.Value)
            {
                $i++
                If($PSBoundParameters.ContainsKey('ListObject'))
                {
                    Update-IDMProgress -Runspace $Runspace -PercentComplete ($i/$Runspace.GraphData.MDMDevices.Value.count * 100) -StatusMsg ("[{0} of {1}] :: Adding [{2}] to list..." -f $i,$Runspace.GraphData.MDMDevices.Value.count,$Resource.deviceName)
                    Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Adding item to [{1}]: {0}" -f $Resource.deviceName,$ListObject.Name) -Type Info
                    $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                        $ListObject.Items.Add($Resource.deviceName) | Out-Null
                    })
                }

                #Add additional Properties to devices
                $OutputItem = New-Object PSObject
                Foreach($p in $Resource | Get-Member -MemberType NoteProperty){
                    $OutputItem | Add-Member NoteProperty $p.name -Value $Resource.($p.name)
                }
                #$AADObjects | Where displayName -eq 'DTOLAB-46VEYL1'
                If($FilteredObj = $Runspace.GraphData.AADDevices.value | Where deviceId -eq $Resource.azureADDeviceId){
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

                $Runspace.Data.IntuneDevices += $OutputItem
            }
        })
    }
    Else{
        If($PSBoundParameters.ContainsKey('ListObject'))
        {

            $i=0
            Foreach($Device in $Devices.Where({ $null -ne $_ }))
            {
                $i++
                Update-IDMProgress -Runspace $Runspace -PercentComplete ($i/$Devices.count * 100) -StatusMsg ("[{0} of {1}] :: Adding [{2}] to list..." -f $i,$Devices.count,$Device.deviceName)
                Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Adding item to [{1}]: {0}" -f $Device.deviceName,$ListObject.Name) -Type Info
                $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                    $ListObject.Items.Add($Device.deviceName) | Out-Null
                })
            }

        }
        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
            $Runspace.Data.IntuneDevices = @()
            $Runspace.Data.IntuneDevices = $Runspace.GraphData.MDMDevices.Value
        })
    }

    #Update-IDMProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Added {0} items to list" -f $Devices.count) -Color Green
    Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Found {0} devices" -f $Devices.count) -Type Info

    #return $Devices.Where({ $null -ne $_ })
    #$Runspace.Data.IntuneDevices = @()
    #$Runspace.Data.IntuneDevices += $Devices.Where({ $null -ne $_ })
}



Function Get-IDMAzureDevicesInRunspace{
    <#
    .SYNOPSIS
    This function is used to get Azure Devices from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any Azure Device

    #>

    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [hashtable]$Runspace,

        [Parameter(Mandatory=$true)]
        [hashtable]$ParentRunspace,

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
        $Resource = "devices"
        If($FilterBy -and $Filter){
            switch($FilterBy){
                'DisplayName' {$uri = "https://graph.microsoft.com/beta/devices?`$filter=displayName eq '$Filter'"}

                'StartWithDisplayName' {$uri = "https://graph.microsoft.com/beta/devices?`$filter=startswith(displayName, '$Filter')"}

                'NOTStartWithDisplayName'{ $uri = "https://graph.microsoft.com/beta/devices?`$filter=NOT startsWith(displayName, '$Filter')"}
            }

        }Else{
            $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"
        }
    }
    Process{
        Write-UIOutput -UIObject $ParentRunspace.Logging -Message ("Retrieving data from URI: {0}" -f $uri) -Type Info

        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
            try {
                $Runspace.GraphData.AADDevices = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
            }
            catch {
                $ex = $_.Exception
                $errorResponse = $ex.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorResponse)
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                $responseBody = $reader.ReadToEnd();
                $message = ("Request to {0} failed with HTTP Status {1} {2}" -f $uri,$ex.Response.StatusCode,$ex.Response.StatusDescription)

                Update-IDMProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Response content: {0}" -f $responseBody) -Color Red

                Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message $message -Type Error
            }
        })
    }
    End{

    }

}


Function Get-IDMIntuneAssignmentsInRunspace{
    Param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Runspace,

        [Parameter(Mandatory=$true)]
        [hashtable]$ParentRunspace,

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

    Update-IDMProgress -Runspace $Runspace -StatusMsg ("Retrieving assignments...") -Indeterminate

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
    $totalcnt = $Resources.count
    Foreach($Resource in $Resources)
    {
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)/$TargetId/memberOf"
        Write-UIOutput -UIObject $ParentRunspace.Logging -Message ("Retrieving data from URI: {0}" -f $uri) -Type Info

        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
            try {
                $Runspace.GraphData.DeviceGroups = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
                $Runspace.Data.MemberOfGroups = $DeviceGroups.Value | Select id, displayName,@{N='GroupType';E={If('DynamicMembership' -in $_.groupTypes){return 'Dynamic'}Else{return 'Static'} }}
            }
            catch {
                $ex = $_.Exception
                $errorResponse = $ex.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorResponse)
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                $responseBody = $reader.ReadToEnd();
                $message = ("Request to {0} failed with HTTP Status {1} {2}" -f $uri,$ex.Response.StatusCode,$ex.Response.StatusDescription)

                Update-IDMProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Response content: {0}" -f $responseBody) -Color Red

                Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message $message -Type Error
            }
        })

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

                    $PlatformComponents = @{
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

        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
            $Runspace.Data.DeviceAssignments = @()
            $Runspace.Data.UserAssignments = @()
        })


        
        #iterate through each resource based on platform
        Foreach($Component in $PlatformComponents.GetEnumerator())
        {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Component.Value)"
            Write-UIOutput -UIObject $ParentRunspace.Logging -Message ("Retrieving data from URI: {0}" -f $uri) -Type Info

            $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                try {
                    $Runspace.GraphData.PlatformResources = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
                    If($Runspace.GraphData.PlatformResources.'@odata.type'){
                        $Runspace.Data.PlatformResources = ($Runspace.GraphData.PlatformResources | Where '@odata.type' -match ($PlatformType -join '|'))
                    }
                }
                catch {
                    $ex = $_.Exception
                    $errorResponse = $ex.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($errorResponse)
                    $reader.BaseStream.Position = 0
                    $reader.DiscardBufferedData()
                    $responseBody = $reader.ReadToEnd();
                    $message = ("Request to {0} failed with HTTP Status {1} {2}" -f $uri,$ex.Response.StatusCode,$ex.Response.StatusDescription)

                    Update-IDMProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Response content: {0}" -f $responseBody) -Color Red

                    Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message $message -Type Error
                }
            })


            Foreach($Resource in $Runspace.Data.Resources)
            {

                #Determine specifics of each item type
                Switch($Resource.'@odata.type'){
                    '#microsoft.graph.windowsUpdateForBusinessConfiguration' {$ResourceType = 'Windows Update for Business'}
                    '#microsoft.graph.windows10CustomConfiguration' {$ResourceType = ($Component.Key + ' (Custom)')}
                    '#microsoft.graph.windowsDomainJoinConfiguration' {$ResourceType = ($Component.Key + ' (Hybrid Domain Join)')}
                    '#microsoft.graph.windowsKioskConfiguration' {$ResourceType = ($Component.Key + ' (Kiosk)')}
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
                    default {$ResourceType = $Component.Key}
                }

                $uri = "https://graph.microsoft.com/$graphApiVersion/$($Component.Value)/$($Resource.id)/assignments"
                Write-UIOutput -UIObject $ParentRunspace.Logging -Message ("Retrieving data from URI: {0}" -f $uri) -Type Info

                $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                    try {
                        $Runspace.GraphData.Assignments = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
                    }
                    Catch{
                        $ex = $_.Exception
                        $errorResponse = $ex.Response.GetResponseStream()
                        $reader = New-Object System.IO.StreamReader($errorResponse)
                        $reader.BaseStream.Position = 0
                        $reader.DiscardBufferedData()
                        $responseBody = $reader.ReadToEnd();
                        $message = ("Request to {0} failed with HTTP Status {1} {2}" -f $uri,$ex.Response.StatusCode,$ex.Response.StatusDescription)

                        Update-IDMProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Response content: {0}" -f $responseBody) -Color Red

                        Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message $message -Type Error
                    }
                })

                $i=0
                #TEST  $Assignment = $Assignments[0]
                Foreach($Assignment in $Runspace.GraphData.Assignments.value)
                {
                    $AssignmentGroup = '' | Select Name,Type,Mode,Target,Platform,Group,GroupType
                    $AssignmentGroup.Name = $Resource.displayName
                    $AssignmentGroup.Type = $ResourceType
                    $AssignmentGroup.Target = $Target
                    $AssignmentGroup.Platform = $Platform

                    If($Assignment.intent){
                        $AssignmentGroup.Mode = (Get-Culture).TextInfo.ToTitleCase($Assignment.intent)
                    }Else{
                        $AssignmentGroup.Mode = 'Assigned'
                    }

                    #Grab Policyset info
                    If($Assignment.source -eq 'policySets' -and $IncludePolicySetInherits){
                        $PolicySet = $True
                        $Uri = "https://graph.microsoft.com/beta/deviceAppManagement/policysets/$($Assignment.sourceId)"
                        Write-UIOutput -UIObject $ParentRunspace.Logging -Message ("Retrieving data from URI: {0}" -f $uri) -Type Info

                        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                            try {
                                $Runspace.GraphData.PolicySet = Invoke-RestMethod -Uri $uri -Headers $AuthToken -Method Get -ErrorAction Stop
                            }
                            Catch{
                                $ex = $_.Exception
                                $errorResponse = $ex.Response.GetResponseStream()
                                $reader = New-Object System.IO.StreamReader($errorResponse)
                                $reader.BaseStream.Position = 0
                                $reader.DiscardBufferedData()
                                $responseBody = $reader.ReadToEnd();
                                $message = ("Request to {0} failed with HTTP Status {1} {2}" -f $uri,$ex.Response.StatusCode,$ex.Response.StatusDescription)

                                Update-IDMProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Response content: {0}" -f $responseBody) -Color Red

                                Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message $message -Type Error
                            }
                        })
                    }
                    Else{
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
                                If($Group -in $Runspace.Data.MemberOfGroups.id){
                                    $AddToGroup = $true
                                    $AssignmentGroup.Group = ($Runspace.Data.MemberOfGroups | Where id -eq $Group).displayName
                                    $AssignmentGroup.GroupType = ($Runspace.Data.MemberOfGroups | Where id -eq $Group).GroupType
                                }Else{
                                    $AddToGroup = $false
                                }
                            }
                        }

                        '#microsoft.graph.groupAssignmentTarget' {
                            $TargetAssignments = $Assignment.target | Where '@odata.type' -eq '#microsoft.graph.groupAssignmentTarget'
                            Foreach($Group in $TargetAssignments.GroupId)
                            {
                                If($Group -in $Runspace.Data.MemberOfGroups.id){
                                    $AddToGroup = $true
                                    $AssignmentGroup.Group = ($Runspace.Data.MemberOfGroups | Where id -eq $Group).displayName
                                    $AssignmentGroup.GroupType = ($Runspace.Data.MemberOfGroups | Where id -eq $Group).GroupType
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
                            $AssignmentGroup.GroupType = ('PolicySet: ' + $Runspace.GraphData.PolicySet.value.displayName)
                        }

                        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                            If($AssignmentGroup.Target -eq 'devices'){
                                $Runspace.Data.DeviceAssignments += $AssignmentGroup
                            }
                            If($AssignmentGroup.Target -eq 'users'){
                                $Runspace.Data.UserAssignments += $AssignmentGroup
                            }
                        })
                    }
                    $i++
                    Update-IDMProgress -Runspace $Runspace -PercentComplete ($i/$Runspace.GraphData.Assignments.value.count * 100) -StatusMsg ("[{0} of {1}] :: Adding assignment to list: {2}" -f $i,$Runspace.GraphData.Assignments.value.count,$Assignment.Name)
                }#end assignment groups

            } #end Resource assignments

        } #end resources
    }#end resrouceitem loop (device and users)
}
