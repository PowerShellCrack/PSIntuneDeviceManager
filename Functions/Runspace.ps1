
Function Get-RunspaceIntuneDevices{

    <#
    .SYNOPSIS
    This function is used to get Intune Managed Devices from the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets any Intune Managed Device
    .EXAMPLE
    Get-RunspaceIntuneDevices
    Returns all managed devices but excludes EAS devices registered within the Intune Service
    .EXAMPLE
    Get-RunspaceIntuneDevices -IncludeEAS
    Returns all managed devices including EAS devices registered within the Intune Service
    .NOTES
    NAME: Get-RunspaceIntuneDevices
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

    Update-UIProgress -Runspace $Runspace -StatusMsg ("Retrieving Device list...") -Indeterminate

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/managedDevices"

    $filterQuery=$null

    if($IncludeEAS.IsPresent){ $Count_Params++ }
    if($ExcludeMDM.IsPresent){ $Count_Params++ }

    if($Count_Params -gt 1){
        write-warning "Multiple parameters set, specify a single parameter -IncludeEAS, -ExcludeMDM or no parameter against the function"
    }

    $Query = @()
    if($IncludeEAS){
        #include all queries by leaving filter empty
    }
    Elseif($ExcludeMDM){
        $Query += "managementAgent eq 'eas'"
        $Query += "managementAgent eq 'easIntuneClient'"
        $Query += "managementAgent eq 'configurationManagerClientEas'"
    }
    Else{
        $Query += "managementAgent eq 'mdm'"
        $Query += "managementAgent eq 'easMdm'"
        $Query += "managementAgent eq 'intuneClient'"
        $Query += "managementAgent eq 'configurationManagerClient'"
        $Query += "managementAgent eq 'configurationManagerClientMdm'"
    }

    If($PSBoundParameters.ContainsKey('Filter')){
        #TEST $Filter = 'admg02'
        $Query += "contains(deviceName,'$($Filter)')"
    }

    If($PSBoundParameters.ContainsKey('Platform')){
        $Query += "operatingSystem eq '$($Platform)'"
    }

    #build query filter if exists
    If($Query.count -ge 1){
        $filterQuery = "`?`$filter=" + ($Query -join ' and ')
    }

    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource" + $filterQuery

    Write-UIOutput -UIObject $ParentRunspace.Logging -Message ("Retrieving data from URI: {0}" -f $uri) -Type Info

    $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
        try {
            #$runspace = $syncHash
            #Using -Passthru with Invoke-IDMGraphRequests will out graph data including next link and context. Value contains devices. No Passthru will out value only
            #$Runspace.GraphData.MDMDevices = Invoke-IDMGraphRequests -Uri $uri -Headers $AuthToken -Passthru -ErrorAction Stop
            $Runspace.GraphData.MDMDevices = Invoke-IDMGraphRequests -Uri $uri -Headers $AuthToken -ErrorAction Stop
        }
        catch {
            Update-UIProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Response content: {0}" -f $_.Exception.Response.StatusCode) -Color Red
            Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Response content: {0}" -f $_.Exception.Response.StatusCode) -Type Error
        }
    })

    If($Expand)
    {
        $i=0
        $Devices = @()
        #Populate AAD devices using splat for filter and platform to minimize seach field
        # this is becuse if results are more than gropah will show, the results coudl be skewed.

        $AzureDeviceParam = @{
            Runspace=$Runspace
            ParentRunspace=$Runspace
            AuthToken=$AuthToken
        }
        If($PSBoundParameters.ContainsKey('Filter')){
            $AzureDeviceParam += @{Filter = $Filter}
        }
        If($PSBoundParameters.ContainsKey('Platform')){
            $AzureDeviceParam += @{Platform = $Platform}
        }
        Get-RunspaceAzureDevices @AzureDeviceParam

        #collect stale objects
        $StaleDate = (Get-Date).AddDays(-90)
        $StaleObj = $AADObjects | Where {$_.approximateLastSignInDateTime -le $StaleDate}

        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{

            $Runspace.Data.IntuneDevices = @()

            #TEST $Resource = $Response | Where deviceName -eq 'DTOLAB-46VEYL1'
            Foreach($Resource in $Runspace.GraphData.MDMDevices)
            {
                $i++
                If($PSBoundParameters.ContainsKey('ListObject'))
                {
                    Update-UIProgress -Runspace $Runspace -PercentComplete ($i/$Runspace.GraphData.MDMDevices.count * 100) -StatusMsg ("[{0} of {1}] :: Adding [{2}] to list..." -f $i,$Runspace.GraphData.MDMDevices.count,$Resource.deviceName)
                    Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Adding item to [{1}]: {0}" -f $Resource.deviceName,$ListObject.Name) -Type Info
                    $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                        $ListObject.Items.Add($Resource.deviceName) | Out-Null
                    })
                }

                $OutputItem = New-Object PSObject
                #first add all properties of Intune device
                Foreach($p in $Resource | Get-Member -MemberType NoteProperty){
                    $OutputItem | Add-Member NoteProperty $p.name -Value $Resource.($p.name)
                }

                #TEST $LinkedIntuneDevice = $Runspace.GraphData.AADDevices | Where displayName -eq 'DTOLAB-46VEYL1'
                If($LinkedIntuneDevice = $Runspace.GraphData.AADDevices | Where deviceId -eq $Resource.azureADDeviceId){

                    Foreach($p in $LinkedIntuneDevice | Get-Member -MemberType NoteProperty){
                        switch($p.name){
                            'id' {$OutputItem | Add-Member NoteProperty "azureADObjectId" -Value $LinkedIntuneDevice.($p.name) -Force}
                            'deviceMetadata' {<#For internal use only.#>}
                            'alternativeSecurityIds' {<#For internal use only.#>}
                            default {$OutputItem | Add-Member NoteProperty $p.name -Value $LinkedIntuneDevice.($p.name) -Force}
                        }
                    }
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
                Update-UIProgress -Runspace $Runspace -PercentComplete ($i/$Devices.count * 100) -StatusMsg ("[{0} of {1}] :: Adding [{2}] to list..." -f $i,$Devices.count,$Device.deviceName)
                Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Adding item to [{1}]: {0}" -f $Device.deviceName,$ListObject.Name) -Type Info
                $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                    $ListObject.Items.Add($Device.deviceName) | Out-Null
                })
            }

        }
        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
            $Runspace.Data.IntuneDevices = @()
            $Runspace.Data.IntuneDevices = $Runspace.GraphData.MDMDevices
        })
    }

    #Update-UIProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Added {0} items to list" -f $Devices.count) -Color Green
    Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Found {0} devices" -f $Devices.count) -Type Info

    #return $Devices.Where({ $null -ne $_ })
    #$Runspace.Data.IntuneDevices = @()
    #$Runspace.Data.IntuneDevices += $Devices.Where({ $null -ne $_ })
}



Function Get-RunspaceAzureDevices{
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
        [string]$FilterBy = 'StartWithDisplayName',

        [Parameter(Mandatory=$false)]
        [string]$Filter,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Windows','Android','MacOS','iOS')]
        [string]$Platform,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken,

        [switch]$Passthru
    )
    Begin{
        # Defining Variables
        $graphApiVersion = "beta"
        $Resource = "devices"

        If($FilterBy -eq 'SearchDisplayName' -and -NOT($AuthToken['ConsistencyLevel'])){
            $AuthToken += @{ConsistencyLevel = 'eventual'}
        }

        $filterQuery=$null
    }
    Process{
        $Query = @()

        If($PSBoundParameters.ContainsKey('Platform')){
            $Query += "operatingSystem eq '$($Platform)'"
        }

        If($PSBoundParameters.ContainsKey('Filter')){
             switch($FilterBy){
                'DisplayName' {$Query += "displayName eq '$Filter'";$Operator='filter'}
                'StartWithDisplayName' {$Query += "startswith(displayName, '$Filter')";$Operator='filter'}
                'NOTStartWithDisplayName' {$Query += "NOT startsWith(displayName, '$Filter')";$Operator='filter'}
                'SearchDisplayName' {$Query += "`"displayName:$Filter`"";$Operator='search'}
            }
        }

        #build query filter if exists
        If($Query.count -ge 1){
            $filterQuery = "`?`$$Operator=" + ($Query -join ' and ')
        }

        $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource" + $filterQuery

        Write-UIOutput -UIObject $ParentRunspace.Logging -Message ("Retrieving data from URI: {0}" -f $uri) -Type Info

        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
            try {
                #Using -Passthru with Invoke-IDMGraphRequests will out graph data including next link and context. Value contains devices. No Passthru will out value only
                #$Runspace.GraphData.MDMDevices = Invoke-IDMGraphRequests -Uri $uri -Headers $AuthToken -Passthru -ErrorAction Stop
                $Runspace.GraphData.AADDevices = Invoke-IDMGraphRequests -Uri $uri -Headers $AuthToken -ErrorAction Stop
            }
            catch {
                Update-UIProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Response content: {0}" -f $_.Exception.Response.StatusCode) -Color Red
                Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Response content: {0}" -f $_.Exception.Response.StatusCode) -Type Error
            }
        })
    }
    End{
        If($Passthru){
            return $Runspace.GraphData.AADDevices
        }
    }
}


Function Get-RunspaceIntuneAssignments{
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$false)]
        [hashtable]$Runspace,

        [Parameter(Mandatory=$false)]
        [hashtable]$ParentRunspace,

        [Parameter(Mandatory=$true,ParameterSetName='TargetArea')]
        [ValidateSet('Devices','Users')]
        [string]$Target,

        [Parameter(Mandatory=$true,ParameterSetName='TargetArea')]
        [string]$TargetId,

        [Parameter(Mandatory=$true,ParameterSetName='TargetSet')]
        [hashtable]$TargetSet,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Windows','Android','MacOS','iOS')]
        [string]$Platform = 'Windows',

        [Parameter(Mandatory=$false)]
        $ListObject,

        [Parameter(Mandatory=$false)]
        [switch]$IncludePolicySetInherits,

        [Parameter(Mandatory=$false)]
        $AuthToken = $Global:AuthToken,

        [Parameter(Mandatory=$false)]
        [switch]$Passthru
    )

    If($PSBoundParameters.ContainsKey('Runspace')){
        Update-UIProgress -Runspace $Runspace -StatusMsg ("Retrieving assignments...") -Indeterminate
    }

    $graphApiVersion = "beta"

    #First get all Azure AD groups this device is a member of.
    $UriResources = @()
    #TEST $TargetSet = @{devices=$syncHash.Data.SelectedDevice.azureADObjectId;users=$syncHash.Data.AssignedUser.id}
    If($TargetSet)
    {
        $UriResources += $TargetSet.GetEnumerator() | %{"https://graph.microsoft.com/$graphApiVersion/$($_.Name)/$($_.Value)/memberOf"}
    }
    Else{
        $UriResources += "https://graph.microsoft.com/$graphApiVersion/$($Target.ToLower())/memberOf"
    }

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

                $PlatformComponents = @(
                    'deviceManagement/windowsAutopilotDeploymentProfiles'
                    'deviceManagement/deviceCompliancePolicies'
                    'deviceManagement/deviceComplianceScripts'
                    'deviceManagement/deviceConfigurations'
                    'deviceManagement/deviceEnrollmentConfigurations'
                    'deviceManagement/deviceHealthScripts'
                    'deviceManagement/deviceManagementScripts'
                    'deviceManagement/roleScopeTags'
                    'deviceManagement/windowsQualityUpdateProfiles'
                    'deviceManagement/windowsFeatureUpdateProfiles'
                    'deviceAppManagement/windowsInformationProtectionPolicies'
                    'deviceAppManagement/mdmWindowsInformationProtectionPolicies'
                    'deviceAppManagement/mobileApps'
                    'deviceAppManagement/policysets'
                )
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

    #Add component URIs
    $UriResources += $PlatformComponents | %{ "https://graph.microsoft.com/$graphApiVersion/$($_)"}

    #Using -Passthru with Invoke-IDMGraphRequests will out graph data including next link and context. Value contains devices. No Passthru will out value only
    #$Runspace.GraphData.MDMDevices = Invoke-IDMGraphRequests -Uri $uri -Headers $AuthToken -Passthru -ErrorAction Stop
    $GraphRequests = $UriResources | Invoke-IDMGraphRequests -Headers $AuthToken -Threads $UriResources.Count

    If($PSBoundParameters.ContainsKey('ParentRunspace')){
        $ParentRunspace.Window.Dispatcher.Invoke("Normal",[action]{
            $ParentRunspace.GraphData.PlatformResources = $GraphRequests
        })
    }

    $DeviceGroups = ($GraphRequests | Where {$_.uri -like '*/devices/*/memberOf'})
    $UserGroups = ($GraphRequests | Where {$_.uri -like '*/users/*/memberOf'})

    If($PSBoundParameters.ContainsKey('ParentRunspace')){
        $ParentRunspace.Window.Dispatcher.Invoke("Normal",[action]{
            $ParentRunspace.Data.DeviceGroups = $DeviceGroups | Select id, displayName,@{N='GroupType';E={If('DynamicMembership' -in $_.groupTypes){return 'Dynamic'}Else{return 'Static'} }}
            $ParentRunspace.Data.UserGroups = $UserGroups | Select id, displayName,@{N='GroupType';E={If('DynamicMembership' -in $_.groupTypes){return 'Dynamic'}Else{return 'Static'} }}
        })
    }

    $DeviceGroupMembers = $DeviceGroups | Select id, displayName,@{N='GroupType';E={If('DynamicMembership' -in $_.groupTypes){return 'Dynamic'}Else{return 'Static'} }},@{N='Target';E={'Devices'}}
    $UserGroupMembers = $UserGroups | Select id, displayName,@{N='GroupType';E={If('DynamicMembership' -in $_.groupTypes){return 'Dynamic'}Else{return 'Static'} }},@{N='Target';E={'Users'}}

    #combine device and users memberships
    $AllGroupMembers = @()
    $AllGroupMembers = $DeviceGroupMembers + $UserGroupMembers

    <#
    $GraphRequests.'@odata.type' | Select -unique
    $GraphRequests.type | Select -unique
    ($GraphRequests.Value | Where '@odata.type' -eq '#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration')
    ($GraphRequests.Value | Where '@odata.type' -eq '#microsoft.graph.deviceEnrollmentLimitConfiguration')
    ($GraphRequests.Value | Where '@odata.type' -eq '#microsoft.graph.deviceEnrollmentWindowsHelloForBusinessConfiguration')
    ($GraphRequests.Value | Where '@odata.type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration')
    #>
    $PlatformResources = ($GraphRequests | Where {$_.'@odata.type' -match ($PlatformType -join '|')}) |
                                            Select id,uri,
                                                @{N='type';E={Set-IDMResourceFriendlyType -Category (split-path $_.uri -leaf) -ODataType $_.'@odata.type'}},
                                                @{N='name';E={Set-IDMResourceFriendlyName -Name $_.displayName -LicenseType $_.licenseType -ODataType $_.'@odata.type'}},
                                                @{N='Assigned';E={If('isAssigned' -in ($_ | Get-Member -MemberType NoteProperty).Name){[boolean]$_.isAssigned}}}

    <#
    $PlatformResources[35]
    $PlatformResources[418]
    $PlatformResources = $GraphRequests| Select id,@{N='type';E={Set-IDMResourceFriendlyType -Category (split-path $_.uri -leaf) -ODataType $_.'@odata.type'}}, @{N='name';E={If($_.licenseType){$_.displayName + ' (' + $_.licenseType + ')'}Else{$_.displayName}}},@{N='Assigned';E={If('isAssigned' -in ($_ | Get-Member -MemberType NoteProperty).Name){[boolean]$_.isAssigned}}} | ft
    $PlatformResources = $GraphRequests| Select id,uri,@{N='type';E={Set-IDMResourceFriendlyType -Category (split-path $_.uri -leaf) -ODataType $_.'@odata.type'}}, @{N='name';E={If($_.licenseType){$_.displayName + ' (' + $_.licenseType + ')'}Else{$_.displayName}}},'@odata.type',@{N='Assigned';E={If('isAssigned' -in ($_ | Get-Member -MemberType NoteProperty).Name){[boolean]$_.isAssigned}}} | ft
    $PlatformResources.type | Select -unique
    $PlatformResources | Where type -eq 'Policy Set'
    $PlatformResources.type
    #>
    #get Assignments of all resource suing multithreading
    $ResourceAssignments = $PlatformResources | %{ $_.uri + '/' + $_.id + '/assignments'} | Invoke-IDMGraphRequests -Headers $AuthToken
    #$ResourceAssignments.count


    $AssignmentList= @()

    If($PSBoundParameters.ContainsKey('ParentRunspace')){
        $ParentRunspace.Window.Dispatcher.Invoke("Normal",[action]{
                $ParentRunspace.Data.DeviceAssignments = @()
                $ParentRunspace.Data.UserAssignments = @()
        })
    }
    #TEST $Assignment = $ResourceAssignments[0]
    #TEST $Assignment = ($ResourceAssignments | Where Source -eq 'policySets')[0]
    $i=0
    Foreach($Assignment in $ResourceAssignments)
    {
        $ReferenceResource = $PlatformResources | Where { $Assignment.uri -eq ($_.uri + '/' + $_.id + '/assignments')}
        $AssignmentGroup = '' | Select Id,Name,Type,Mode,Target,Platform,Group,GroupType,GroupId,Assigned
        $AssignmentGroup.Id = $Assignment.id
        $AssignmentGroup.Name = $ReferenceResource.name
        $AssignmentGroup.Type = $ReferenceResource.Type
        #$AssignmentGroup.Target = $Assignment.target
        $AssignmentGroup.Platform = $Platform
        $AssignmentGroup.Assigned = $ReferenceResource.Assigned

        If($Assignment.intent){
            $AssignmentGroup.Mode = (Get-Culture).TextInfo.ToTitleCase($Assignment.intent)
        }Else{
            $AssignmentGroup.Mode = 'Assigned'
        }

        #Grab Policyset info
        If($Assignment.source -eq 'policySets' -and $IncludePolicySetInherits){
            $PolicySet = $True
            $PolicySetDetails = $PlatformResources | Where id -eq $Assignment.sourceId
            If(!$PolicySetDetails){
                $PolicySet = $False
            }
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
                $AssignmentGroup.Target = 'Users'
            }

            '#microsoft.graph.allDevicesAssignmentTarget' {
                $AddToGroup = $true
                $AssignmentGroup.Group = 'All Devices'
                $AssignmentGroup.GroupType = 'Built-In'
                $AssignmentGroup.Target = 'Devices'
            }

            '#microsoft.graph.exclusionGroupAssignmentTarget' {
                $AssignmentGroup.Mode = 'Excluded'
                $TargetAssignments = $Assignment.target | Where '@odata.type' -eq '#microsoft.graph.exclusionGroupAssignmentTarget'
                #$Group = $TargetAssignments.GroupId[-1]
                Foreach($Group in $TargetAssignments.GroupId)
                {
                    If($Group -in $AllGroupMembers.id){
                        $GroupDetails = ($AllGroupMembers | Where id -eq $Group)
                        $AddToGroup = $true
                        $AssignmentGroup.GroupId = $GroupDetails.id
                        $AssignmentGroup.Group = $GroupDetails.displayName
                        $AssignmentGroup.GroupType = $GroupDetails.GroupType
                        $AssignmentGroup.Target = $GroupDetails.Target
                    }Else{
                        $AddToGroup = $false
                    }
                }
            }

            '#microsoft.graph.groupAssignmentTarget' {
                $TargetAssignments = $Assignment.target | Where '@odata.type' -eq '#microsoft.graph.groupAssignmentTarget'
                Foreach($Group in $TargetAssignments.GroupId)
                {
                    If($Group -in $AllGroupMembers.id){
                        $GroupDetails = ($AllGroupMembers | Where id -eq $Group)
                        $AddToGroup = $true
                        $AssignmentGroup.GroupId = $GroupDetails.id
                        $AssignmentGroup.Group = $GroupDetails.displayName
                        $AssignmentGroup.GroupType = $GroupDetails.GroupType
                        $AssignmentGroup.Target = $GroupDetails.Target
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
                $AssignmentGroup.GroupType = ('PolicySet: ' + $PolicySetDetails.name)
            }

            If($PSBoundParameters.ContainsKey('ParentRunspace')){
                $ParentRunspace.Window.Dispatcher.Invoke("Normal",[action]{
                    If($AssignmentGroup.Target -eq 'Devices'){
                        $ParentRunspace.Data.DeviceAssignments += $AssignmentGroup
                    }
                    If($AssignmentGroup.Target -eq 'Users'){
                        $ParentRunspace.Data.UserAssignments += $AssignmentGroup
                    }
                })

                Write-UIOutput -Runspace $ParentRunspace -UIObject $ParentRunspace.Logging -Message ("Adding item to [{1}]: {0}" -f $Device.deviceName,$ListObject.Name) -Type Info
            }

            If($PSBoundParameters.ContainsKey('ListObject'))
            {
                $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                    $ListObject.Items.Add($AssignmentGroup) | Out-Null
                })
            }

            If($PSBoundParameters.ContainsKey('Runspace')){
                Update-UIProgress -Runspace $Runspace -PercentComplete ($i/$ResourceAssignments.count * 100) -StatusMsg ("[{0} of {1}] :: Adding assignment to list: {2}" -f $i,$ResourceAssignments.count,$Assignment.Name)
            }

            $AssignmentList += $AssignmentGroup
        }
        $i++

    }#end assignment loop

    If($Passthru){
        #$AssignmentList | ft
        Return $AssignmentList
    }
}
