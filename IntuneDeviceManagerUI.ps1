<#
.SYNOPSIS
    Connects to Intune and AD to manage devices

.DESCRIPTION

.NOTES
    Author		: Dick Tracy II <richard.tracy@microsoft.com>
    Source	    :
    Version		: 1.4.4

.EXAMPLE
    .\IntuneDeviceManagerUI.ps1 -DevicePrefix 'DTOHAADJ'

.EXAMPLE
    .\IntuneDeviceManagerUI.ps1 -RenameEnablement

.EXAMPLE
    .\IntuneDeviceManagerUI.ps1 -DevicePlatform Android

.EXAMPLE
    .\IntuneDeviceManagerUI.ps1 -AppConnect -ApplicationId 'dd99ec13-a3c5-4703-b95f-794a2b559fb0' -TenantId '2ec9dcf0-b109-434a-8bcd-238a3bf0c6b2'

.LINK
    #modules needed:
        Microsoft.Graph.Intune
        Microsoft.Graph.Authentication
        Microsoft.Graph.DeviceManagement.Administration
        AzureAD
        WindowsAutoPilotIntune
        IDMCmdlets
#>
[cmdletbinding(DefaultParameterSetName='UserConnected')]
param(
    [Parameter(Mandatory=$false,ParameterSetName='UserConnected')]
    [Parameter(Mandatory=$false,ParameterSetName='AppConnected')]
    [ValidateSet('Windows','Android','MacOS','iOS')]
    [string]$DevicePlatform = 'Windows',

    [Parameter(Mandatory=$false,ParameterSetName='UserConnected')]
    [Parameter(Mandatory=$false,ParameterSetName='AppConnected')]
    [string]$DevicePrefix,

    [Parameter(Mandatory=$false,ParameterSetName='UserConnected')]
    [Parameter(Mandatory=$false,ParameterSetName='AppConnected')]
    [switch]$RenameEnablement,

    [Parameter(Mandatory=$false,ParameterSetName='UserConnected')]
    [Parameter(Mandatory=$false,ParameterSetName='AppConnected')]
    [hashtable]$RenameRules = @{RuleRegex1 = '^.{0,3}';RuleRegex2 ='.{0,3}[\s+]'},

    [Parameter(Mandatory=$false,ParameterSetName='UserConnected')]
    [Parameter(Mandatory=$false,ParameterSetName='AppConnected')]
    [ValidateSet('No Abbr','Chassis','Manufacturer','Model')]
    [string]$RenameAbbrType = 'Chassis',

    [Parameter(Mandatory=$false,ParameterSetName='UserConnected')]
    [Parameter(Mandatory=$false,ParameterSetName='AppConnected')]
    [string]$RenameAbbrKey = 'Laptop=A, Notebook=A, Tablet=A, Desktop=W, Tower=W, Virtual Machine=W',

    [Parameter(Mandatory=$false,ParameterSetName='UserConnected')]
    [Parameter(Mandatory=$false,ParameterSetName='AppConnected')]
    [string]$RenamePrefix,

    [Parameter(Mandatory=$false,ParameterSetName='UserConnected')]
    [Parameter(Mandatory=$false,ParameterSetName='AppConnected')]
    [ValidateSet(0,1,2,3,4,5)]
    [int]$RenameAppendDigits = 3,

    [Parameter(Mandatory=$false,ParameterSetName='UserConnected')]
    [Parameter(Mandatory=$false,ParameterSetName='AppConnected')]
    [string]$RenameSearchFilter = '*',

    [Parameter(Mandatory=$false,ParameterSetName='UserConnected')]
    [Parameter(Mandatory=$false,ParameterSetName='AppConnected')]
    [string]$CMSiteCode,

    [Parameter(Mandatory=$false,ParameterSetName='UserConnected')]
    [Parameter(Mandatory=$false,ParameterSetName='AppConnected')]
    [string]$CMSiteServer,

    [Parameter(Mandatory=$false,ParameterSetName='AppConnected')]
    [switch]$AppConnect,

    [Parameter(Mandatory=$true,ParameterSetName='AppConnected')]
    [string]$ApplicationId,

    [Parameter(Mandatory=$true,ParameterSetName='AppConnected')]
    [string]$TenantId
)
#*=============================================
##* Runtime Function - REQUIRED
##*=============================================
#region FUNCTION: Check if running in ISE
Function Test-IsISE {
    # try...catch accounts for:
    # Set-StrictMode -Version latest
    try {
        return ($null -ne $psISE);
    }
    catch {
        return $false;
    }
}
#endregion
#region FUNCTION: Check if running in Visual Studio Code
Function Test-VSCode{
    if($env:TERM_PROGRAM -eq 'vscode') {
        return $true;
    }
    Else{
        return $false;
    }
}
#endregion
#region FUNCTION: Find script path for either ISE or console
Function Get-ScriptPath {
    <#
        .SYNOPSIS
            Finds the current script path even in ISE or VSC
        .LINK
            Test-VSCode
            Test-IsISE
    #>
    param(
        [switch]$Parent
    )
    Begin{}
    Process{
        if ($PSScriptRoot -eq "")
        {
            if (Test-IsISE)
            {
                $ScriptPath = $psISE.CurrentFile.FullPath
            }
            elseif(Test-VSCode){
                $context = $psEditor.GetEditorContext()
                $ScriptPath = $context.CurrentFile.Path
            }Else{
                $ScriptPath = (Get-location).Path
            }
        }
        else
        {
            $ScriptPath = $PSCommandPath
        }
    }
    End{
        If($Parent){
            Split-Path $ScriptPath -Parent
        }Else{
            $ScriptPath
        }
    }
}
#endregion
##*=============================================
##* VARIABLE DECLARATION
##*=============================================
#region VARIABLES: Building paths & values
# Use function to get paths because Powershell ISE & other editors have different results
[string]$scriptPath = Get-ScriptPath
[string]$scriptName = [IO.Path]::GetFileNameWithoutExtension($scriptPath)
[string]$scriptRoot = Split-Path -Path $scriptPath -Parent
[string]$FunctionPath = Join-Path -Path $scriptRoot -ChildPath 'Functions'
[string]$ResourcePath = Join-Path -Path $scriptRoot -ChildPath 'Resources'
[string]$StylePath = Join-Path -Path $ResourcePath -ChildPath 'Styles'
[string]$XAMLFilePath = Join-Path -Path $ResourcePath -ChildPath 'MainWindow2.xaml'
##*=============================================
##* External Functions
##*=============================================
. "$FunctionPath\Environment.ps1"

#parse changelog for version for a more accurate version
$ChangeLogPath = Resolve-ActualPath -FileName 'CHANGELOG.md' -WorkingPath $scriptRoot -ErrorAction SilentlyContinue
If($ChangeLogPath){
    $ChangeLog = Get-Content $ChangeLogPath
    $Changedetails = (($ChangeLog -match '##')[0].TrimStart('##') -split '-').Trim()
    [string]$Version = [version]$Changedetails[0]
    [string]$MenuDate = $Changedetails[1]
}
#check modules
#$ModulesNeeded = @('Microsoft.Graph.Intune','Microsoft.Graph.Authentication','Microsoft.Graph.DeviceManagement.Administration','AzureAD','WindowsAutoPilotIntune','Microsoft.Graph.Identity.DirectoryManagement')
$ModulesNeeded = @('Az.Accounts','Microsoft.Graph.Intune','Microsoft.Graph.Authentication','AzureAD','WindowsAutopilotIntune','IDMCmdlets')

$ParamProps = @{
    Name = $scriptName
    DevicePlatform = $DevicePlatform
    DevicePrefix = $DevicePrefix
    Rules = $RenameRules
    AllowRename = $RenameEnablement
    SearchFilter = $SearchFilter
    AbbrType = $RenameAbbrType
    AbbrKey = $RenameAbbrKey
    Prefix = $RenamePrefix
    AppendDigits = $RenameAppendDigits
    CMSiteCode = $CMSiteCode
    CMSiteServer = $CMSiteServer
    AppConnect = $AppConnect
    ApplicationId = $ApplicationId
    TenantId = $TenantId
    Version = $Version
    MenuDate = $MenuDate
    RequiredModules = $ModulesNeeded
}
##*=============================================
##* UI FUNCTION
##*=============================================
Function Show-IDMWindow
{
    <#
    .SYNOPSIS
        Shows the Intune Device Manager UI
    .DESCRIPTION
        Displays the Intune Device Manager (IDM) UI to managing devices in Intune
    .NOTES
        Author		: Dick Tracy II <richard.tracy@microsoft.com>
        Source	    :
        Version		: 1.1.6
    .PARAMETER XamlFile
    #>
    Param(
        [String]$XamlFile,
        [String]$StylePath,
        [String]$FunctionPath,
        [hashtable]$Properties,
        [switch]$Wait
    )
    <#
    $XamlFile=$XAMLFilePath
    $StylePath=$StylePath
    $FunctionPath=$FunctionPath
    $Properties=$ParamProps
    $Wait=$true
    #>
    #build runspace
    $syncHash = [hashtable]::Synchronized(@{})
    $IDMRunSpace =[runspacefactory]::CreateRunspace()
    $syncHash.Runspace = $IDMRunSpace
    $syncHash.FunctionPath = $FunctionPath
    $syncHash.StylePath = $StylePath
    $syncHash.XamlFile = $XamlFile
    $syncHash.Properties = $Properties
    $syncHash.Data = @{}
    $syncHash.GraphData = @{}
    $IDMRunSpace.ApartmentState = "STA"
    $IDMRunSpace.ThreadOptions = "ReuseThread"
    $IDMRunSpace.Open() | Out-Null
    $IDMRunSpace.SessionStateProxy.SetVariable("syncHash",$syncHash)
    $PowerShellCommand = [PowerShell]::Create().AddScript({
    #$Code{
        #Load assembles to display UI
        [System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework') | out-null
        [System.Reflection.Assembly]::LoadWithPartialName('PresentationCore')      | out-null
        #convert XAML to XML just to grab info using xml dot sourcing (Not used to process form)
        [string]$XAML = (Get-Content $syncHash.XamlFile -ReadCount 0) -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace '^<Win.*', '<Window' -replace 'Click=".*','/>'
        [xml]$XML = $XAML
        #grab the list of merged dictionaries in XML, replace the path with Powershell
        $MergedDictionaries = $XML.Window.'Window.Resources'.ResourceDictionary.'ResourceDictionary.MergedDictionaries'.ResourceDictionary.Source
        #$XML.SelectNodes("//*[@Source]")
        #grab all style files
        $Resources = Get-ChildItem $syncHash.StylePath -Filter *.xaml
        # replace the resource path
        foreach ($Source in $MergedDictionaries)
        {
            $FileName = Split-Path $Source -Leaf
            $ActualPath = $Resources | Where {$_.Name -match $FileName} | Select -ExpandProperty FullName
            $XAML = $XAML.replace($Source,$ActualPath) #  ($ActualPath -replace "\\","/")
        }
        #convert XAML to XML
        [xml]$XAML = $XAML
        $reader=(New-Object System.Xml.XmlNodeReader $xaml)
        $syncHash.Window=[Windows.Markup.XamlReader]::Load( $reader )
        # Store Form Objects In hashtable
        #===========================================================================
        $xaml.SelectNodes("//*[@Name]") | %{ $syncHash."$($_.Name)" = $syncHash.Window.FindName($_.Name)}
        #Return log path (either in task sequence or temp dir)
        #build log name
        [string]$LogFileName = $syncHash.Name +'.log'
        #build global log fullpath
        $Global:LogFilePath = Join-Path $env:temp -ChildPath $LogFileName
        [string]$FunctionPath = $syncHash.FunctionPath
        ##* External Scripts
        ##*=============================================
        . "$FunctionPath\Logging.ps1"
        . "$FunctionPath\Environment.ps1"
        . "$FunctionPath\DeviceInfo.ps1"
        #. "$FunctionPath\MSgraph.ps1"
        #. "$FunctionPath\Intune.ps1"
        #. "$FunctionPath\Autopilot.ps1"
        . "$FunctionPath\Runspace.ps1"
        . "$FunctionPath\UIControls.ps1"
        # INNER  FUNCTIONS
        #=================================
        If(Test-IsISE){
            $Windowcode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
            $asyncWindow = Add-Type -MemberDefinition $Windowcode -name Win32ShowWindowAsync -namespace Win32Functions
            $null = $asyncWindow::ShowWindowAsync((Get-Process -PID $pid).MainWindowHandle, 0)
        }


        #Closes UI objects and exits (within runspace)
        Function Close-IDMWindow
        {
            if ($syncHash.hadCritError) { Write-Host -Message "Background thread had a critical error" -ForegroundColor red }
            #if runspace has not errored Dispose the UI
            if (!($syncHash.isClosing)) { $syncHash.Window.Close() | Out-Null }
        }


        $updateUI = {

            If($syncHash.AssignmentWindow.Window.IsVisible -eq $true){
                Update-UIProgress -Runspace $synchash -StatusMsg ('Found {0} assignment(s) for device [{1}] and user [{2}]' -f $syncHash.AssignmentWindow.AssignmentData.count,$syncHash.Data.SelectedDevice.deviceName,$syncHash.Data.AssignedUser.userPrincipalName) -PercentComplete 100
            }

            If($syncHash.AssignmentWindow.Window){
                $syncHash.btnViewIntuneAssignments.IsEnabled = $syncHash.AssignmentWindow.isClosed
            }
        }

        # Start populating menu content
        #=================================
        $syncHash.txtVersion.Text = $Synchash.Properties.Version
        #TEST $Module = $ModulesNeeded[0]
        $syncHash.Data.MissingModules = @()
        Foreach($Module in $syncHash.Properties.RequiredModules){
            $ModuleInstalled = Get-Module -Name $Module -ListAvailable
            If($null -eq $ModuleInstalled){
                $syncHash.Data.MissingModules += $Module
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Module required: {0}" -f $Module) -Type Error
            }Else{
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Module is installed: {0}" -f $Module) -Type Info
            }
        }
        #if required modules not installed display UI correctly
        If($syncHash.Data.MissingModules.Count -ge 1){
            $syncHash.AppModulePopup.IsOpen = $true
            $syncHash.btnMSGraphConnect.IsEnabled = $false
            $syncHash.txtAzureModules.text = 'No'
        }Else{
            $syncHash.AppModulePopup.IsOpen = $false
            $syncHash.txtAzureModules.text = 'Yes'
            $syncHash.txtAzureModules.Foreground = 'Green'
        }
        $syncHash.btnAppModuleCancel.Add_Click({
            $syncHash.AppModulePopup.IsOpen = $false
        })
        $syncHash.txtAppModuleList.text = ($syncHash.Data.MissingModules -Join ',')


        $syncHash.btnAppModuleInstall.Add_Click({
            $err=0
            #always install nuget if modules missing
            If($syncHash.Data.MissingModules -gt 0){
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
            }

            Foreach($Module in $syncHash.Data.MissingModules){
                $syncHash.lblAppModuleMsg.Content = ("Installing module: {0}..." -f $Module)
                Try{
                    Install-Module -Name $Module -AllowClobber -Force -Confirm:$false
                }Catch{
                    $err++
                    $syncHash.lblAppModuleMsg.Content = ("Failed: {0}..." -f $_.exception.message)
                }
            }
            If($err -eq 0){
                $syncHash.lblAppModuleMsg.Foreground = 'White'
                $syncHash.lblAppModuleMsg.Content = ("Modules installed, You must restart app...")
                $syncHash.btnAppModuleCancel.Content = 'Ok'
            }
            Else{
                $syncHash.btnAppModuleCancel.Content = 'Close'
            }
            $syncHash.btnAppModuleInstall.Visibility = 'Hidden'
            $syncHash.AppSecretPopup.IsOpen = $false
        })

        $syncHash.btnAppSecretSubmit.Add_Click({
            If([string]::IsNullOrEmpty($syncHash.pwdAppSecret.Password) ){
                $syncHash.lblAppSecretMsg.content = "Invalid Secret, please try again or cancel"
            }Else{
                $syncHash.AppSecretPopup.IsOpen = $false
                $syncHash.btnMSGraphConnect.IsEnabled = $true
            }
        })
        # Setup help menu
        #=================================
        $syncHash.tbADSearchHelp.Add_MouseEnter({
            $PopupContexts = @{
                Help = @("Select the AD search field to determine where computer objects are locate."
                        "The filter can be used during OU Search")
            }
            Add-PopupContent -FlowDocumentObject $syncHash.PopupContent -ContextHash $PopupContexts
            $syncHash.HelpPopup.VerticalOffset="50"
            $syncHash.HelpPopup.Placement="Right"
            $syncHash.HelpPopup.IsOpen = $true
        })
        $syncHash.tbADSearchHelp.Add_MouseLeave({
            $syncHash.HelpPopup.IsOpen = $false
            Clear-PopupContent -FlowDocumentObject $syncHash.PopupContent
        })
        $syncHash.tbCMSiteSearchHelp.Add_MouseEnter({
            $PopupContexts = @{
                Help = @("Fill in CM site server and Site code to connect to ConfigMgr")
                Tip = @("Specify the attribute used to determine if device is a match")
            }
            Add-PopupContent -FlowDocumentObject $syncHash.PopupContent -ContextHash $PopupContexts
            $syncHash.HelpPopup.VerticalOffset="240"
            $syncHash.HelpPopup.Placement="Right"
            $syncHash.HelpPopup.IsOpen = $true
        })
        $syncHash.tbCMSiteSearchHelp.Add_MouseLeave({
            $syncHash.HelpPopup.IsOpen = $false
            Clear-PopupContent -FlowDocumentObject $syncHash.PopupContent
        })
        $syncHash.tbMoveOUHelp.Add_MouseEnter({
            $PopupContexts = @{
                Help = @("Select an option on how to move the device to an OU.")
                Tip = @("Specify an OU in LDAP format")
            }
            Add-PopupContent -FlowDocumentObject $syncHash.PopupContent -ContextHash $PopupContexts
            $syncHash.HelpPopup.VerticalOffset="340"
            $syncHash.HelpPopup.Placement="Left"
            $syncHash.HelpPopup.IsOpen = $true
        })
        $syncHash.tbMoveOUHelp.Add_MouseLeave({
            $syncHash.HelpPopup.IsOpen = $false
            Clear-PopupContent -FlowDocumentObject $syncHash.PopupContent
        })
        $syncHash.tbRuleTesterHelp.Add_MouseEnter({
            $PopupContexts = @{
                Help = @("This is a test tool that allow you to test the configurations")
                Note = @("Rule tester ignores AD Search filter and Method options.","Digits are simulated")
            }
            Add-PopupContent -FlowDocumentObject $syncHash.PopupContent -ContextHash $PopupContexts
            $syncHash.HelpPopup.VerticalOffset="380"
            $syncHash.HelpPopup.Placement="Left"
            $syncHash.HelpPopup.IsOpen = $true
        })
        $syncHash.tbRuleTesterHelp.Add_MouseLeave({
            $syncHash.HelpPopup.IsOpen = $false
            Clear-PopupContent -FlowDocumentObject $syncHash.PopupContent
        })
        $syncHash.tbRuleGenHelp.Add_MouseEnter({
            $PopupContexts = @{
                Help = @("Select an attribute to query from to build base for device name"
                        "Use regex rule to further evaluate the value from the method selected; each rule extracts a value then concatenates"
                        "Select Abbreviations type to add a dynamic character(s) to name. This can be controlled by Abbr key rules."
                        "Set Rules. Rules must be in Key=Value pair and each set must be separated by commas."
                        "Select where to place the Abbreviation within the name."
                        "Select how many digits will be added to the name. This is ignored if increment option is enabled"
                        "Select where the digits should be added to the name ")
                Note = @( "Prefix will add characters to front of name","If no rules are set, first three characters of evaluated type will be used.")
            }
            Add-PopupContent -FlowDocumentObject $syncHash.PopupContent -ContextHash $PopupContexts
            $syncHash.HelpPopup.VerticalOffset="50"
            $syncHash.HelpPopup.Placement="Left"
            $syncHash.HelpPopup.IsOpen = $true
        })
        $syncHash.tbRuleGenHelp.Add_MouseLeave({
            $syncHash.HelpPopup.IsOpen = $false
            Clear-PopupContent -FlowDocumentObject $syncHash.PopupContent
        })
        #attempt to auto populate site server info
        If($syncHash.Properties.CMSiteCode){
            $syncHash.txtCMSiteCode.text = $syncHash.Properties.CMSiteCode
        }Else{
            $syncHash.txtCMSiteCode.text = Get-CMSiteCode
        }
        $syncHash.spViewAppSecret.Add_MouseEnter({
            $syncHash.txtAppSecret.text = $syncHash.pwdAppSecret.Password
            $syncHash.pwdAppSecret.Visibility = 'Hidden'
            $syncHash.txtAppSecret.Visibility = 'Visible'
        })
        $syncHash.spViewAppSecret.Add_MouseLeave({
            $syncHash.pwdAppSecret.Visibility = 'Visible'
            $syncHash.txtAppSecret.Visibility = 'Hidden'
            $syncHash.txtAppSecret.text = $null
        })
        # UPDATE DATA IN MENU
        #=================================
        If(Test-IsDomainJoined){
            $syncHash.txtDomainDevice.text = 'Yes'
            $syncHash.txtDomainDevice.Foreground = 'Green'
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Device running this is joined to the domain: {0}" -f (Test-IsDomainJoined -Passthru)) -Type Info
        }Else{
            $syncHash.txtDomainDevice.text = 'No'
            $syncHash.btnADUserSync.IsEnabled = $false
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Device running this script must be joined to the domain to view AD objects") -Type Error
        }
        # check if RSAT PowerShell Module is installed
        If(Test-RSATModule){
            $syncHash.txtRSAT.text = 'Yes';$syncHash.txtRSAT.Foreground = 'Green'
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("RSAT PowerShell module is installed: {0}" -f (Test-RSATModule -Passthru)) -Type Info
            $syncHash.btnADUserSync.IsEnabled = $true
        }
        Else{
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("RSAT PowerShell module must be installed to be able to query AD device names") -Type Error
            $syncHash.txtRSAT.text = 'No'
            $syncHash.btnADUserSync.IsEnabled = $false
        }


        # check if RSAT PowerShell Module is installed
        If(Test-CMModule){
            $syncHash.txtCMModule.text = 'Yes';$syncHash.txtCMModule.Foreground = 'Green'
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Configuration Manager PowerShell module is installed") -Type Info
            $syncHash.btnCMSiteSync.IsEnabled = $true
        }
        Else{
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Configuration Manager PowerShell module must be installed to be able to query CM device names") -Type Error
            $syncHash.txtCMModule.text = 'No'
            $syncHash.btnCMSiteSync.IsEnabled = $False
        }

        # Get PowerShell Version
        [hashtable]$envPSVersionTable = $PSVersionTable
        [version]$envPSVersion = $envPSVersionTable.PSVersion
        $PSVersion = [float]([string]$envPSVersion.Major + '.' + [string]$envPSVersion.Minor)
        $syncHash.txtPSVersion.Text = $PSVersion.ToString()
        IF($envPSVersion.Major -ge 5 -and $envPSVersion.Minor -ge 1){
            $syncHash.txtPSVersion.Foreground = 'Green'
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("PowerShell version is: {0}" -f $PSVersion.ToString()) -Type Info
        }Else{
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("PowerShell must be must be at version 5.1 to work properly") -Type Error
            $syncHash.btnMSGraphConnect.IsEnabled = $false
            $syncHash.btnNewDeviceName.IsEnabled = $false
        }
        #default refresh button to disabled until MSgraph sign in
        $syncHash.btnRefreshList.IsEnabled = $false
        # Populate config tab
        #----------------------
        $syncHash.txtCMSiteCode.text = $syncHash.Properties.CMSiteCode
        $syncHash.txtCMSiteServer.text = $syncHash.Properties.CMSiteServer

        @('User Root OU','Computers Root OU','Computers Default OU','Custom') | %{$syncHash.cmbSearchInOptions.Items.Add($_) | Out-Null}
        $syncHash.cmbSearchInOptions.SelectedItem = 'User Root OU'

        $syncHash.txtSearchFilter.text = $syncHash.Properties.SearchFilter

        @('User OU Name','User Name','User Display Name','Device Name','Device SerialNumber','Device AssetTag','Random') | %{$syncHash.cmbQueryRule.Items.Add($_) | Out-Null}

        $syncHash.cmbQueryRule.SelectedItem = 'User OU Name'
        @('SerialNumber','MacAddress','LastLoggedOnUser','AssetTag') | %{$syncHash.cmbCMSiteAttribute.Items.Add($_) | Out-Null}
        $syncHash.cmbCMSiteAttribute.SelectedItem = 'SerialNumber'
        If(-Not(Test-RSATModule) -or -Not(Test-IsDomainJoined)){
            $syncHash.chkNewDeviceNameMoveOU.Visibility = 'Hidden'
            $syncHash.cmbOUOptions.IsEnabled = $false
            $syncHash.txtOUPath.IsEnabled = $false
        }Else{
            @('Computers Root','Default Computers','Corresponding User OU','Custom') | %{$syncHash.cmbOUOptions.Items.Add($_) | Out-Null}
            $syncHash.cmbOUOptions.SelectedItem = 'Computers Root'
            $MoveToOU = Get-WellKnownOU -KnownOU $syncHash.cmbOUOptions.SelectedItem
            $syncHash.txtOUPath.text = $MoveToOU
        }
        If($null -ne $syncHash.Properties.Rules){
            (Get-UIProperty -HashName $syncHash "txtRuleRegex" -Wildcard) | Set-UIElement -Enable:$true -ErrorAction SilentlyContinue
            $syncHash.chkDoRegex.IsChecked = $true
            $syncHash.txtRuleRegex1.text = $syncHash.Properties.Rules['RuleRegex1']
            $syncHash.txtRuleRegex2.text = $syncHash.Properties.Rules['RuleRegex2']
            $syncHash.txtRuleRegex3.text = $syncHash.Properties.Rules['RuleRegex3']
            $syncHash.txtRuleRegex4.text = $syncHash.Properties.Rules['RuleRegex4']
        }Else{
            $syncHash.chkDoRegex.IsChecked = $false
            (Get-UIProperty -HashName $syncHash "txtRuleRegex" -Wildcard) | Set-UIElement -Enable:$false -ErrorAction SilentlyContinue
        }
        $syncHash.txtRulePrefix.text = $syncHash.Properties.Prefix
        $syncHash.txtRuleAbbrKey.text = $syncHash.Properties.AbbrKey
        $AbbrTypeList = Get-ParameterOption -Command Get-NewDeviceName -Parameter AbbrType
        #$AbbrTypeList | %{$syncHash.cmbRuleAbbrType.Items.Add($_) | Out-Null}
        Add-UIList -ItemsList $AbbrTypeList -DropdownObject $syncHash.cmbRuleAbbrType
        $syncHash.cmbRuleAbbrType.SelectedItem = $syncHash.Properties.AbbrType
        $AbbrPosList = Get-ParameterOption -Command Get-NewDeviceName -Parameter AbbrPos
        #$AbbrPosList | %{$syncHash.cmbRuleAbbrPosition.Items.Add($_) | Out-Null}
        Add-UIList -ItemsList $AbbrPosList -DropdownObject $syncHash.cmbRuleAbbrPosition
        $syncHash.cmbRuleAbbrPosition.SelectedItem = 'After Prefix'
        #$AddDigits = Get-ParameterOption -Command ${CmdletName} -Parameter AppendDigits
        #@('0','1','2','3','4','5') | %{$syncHash.cmbRuleAddDigits.Items.Add($_) | Out-Null}
        Add-UIList -ItemsList @('0','1','2','3','4','5') -DropdownObject $syncHash.cmbRuleAddDigits
        $syncHash.cmbRuleAddDigits.SelectedItem = $syncHash.Properties.AppendDigits.ToString()
        $DigitPosList = Get-ParameterOption -Command Get-NewDeviceName -Parameter DigitPos
        #$DigitPosList | %{$syncHash.cmbRuleDigitPosition.Items.Add($_) | Out-Null}
        Add-UIList -ItemsList $DigitPosList -DropdownObject $syncHash.cmbRuleDigitPosition
        $syncHash.cmbRuleDigitPosition.SelectedItem = 'At End'
        #hide the back button on startup
        $syncHash.btnBack.Visibility = 'hidden'
        # EVENT HANDLERS
        #========================
        $syncHash.menuNavigation.Add_SelectionChanged( {
            $Tabcount = $syncHash.menuNavigation.items.count
            #show the back button if next on first page is displayed
            If ($syncHash.menuNavigation.SelectedIndex -eq 0) {
                $syncHash.btnBack.Visibility = 'hidden'
            }
            Else {
                $syncHash.btnBack.Visibility = 'Visible'
            }
            #change the button text to display begin on the last tab
            If ($syncHash.menuNavigation.SelectedIndex -ne ($Tabcount - 1)) {
                #Use tab on keyboard to navigate mentu forward (only works until last page)
                $syncHash.Window.Add_KeyDown( {
                        if ($_.Key -match 'Tab') {
                            Switch-UITabItem -TabControlObject $syncHash.menuNavigation -increment 1
                        }
                    })
            }
        })

        #PROCESS ON PAGE LOAD
        # -------------------------------------------
        #Grab the text value when cursor leaves (AFTER Typed)
        $syncHash.txtSearchIntuneDevices.AddHandler(
            [System.Windows.Controls.Primitives.TextBoxBase]::GotFocusEvent,
            [System.Windows.RoutedEventHandler]{
                #set a variable if there is text in field BEFORE the new name is typed
                If($syncHash.txtSearchIntuneDevices.Text){
                    $script:SearchText = $syncHash.txtSearchIntuneDevices.Text
                }
            }
        )

        $syncHash.txtSearchIntuneDevices.AddHandler(
            [System.Windows.Controls.Primitives.TextBoxBase]::LostFocusEvent,
            [System.Windows.RoutedEventHandler]{
                #because there is a example text field in the box by default, check for that
                If($syncHash.txtSearchIntuneDevices.Text -eq 'Search...'){
                    $script:SearchText = $syncHash.txtSearchIntuneDevices.Text
                }
                ElseIf([string]::IsNullOrEmpty($syncHash.txtSearchIntuneDevices.Text)){
                    #add example back in light gray font
                    $syncHash.txtSearchIntuneDevices.Foreground = 'Gray'
                    $syncHash.txtSearchIntuneDevices.Text = 'Search...'
                }
                Else{
                }
            }
        )

        #ACTIVATE LIVE SEARCH
        $syncHash.txtSearchIntuneDevices.AddHandler(
            [System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
            [System.Windows.RoutedEventHandler]{
                If(-not([string]::IsNullOrEmpty($syncHash.txtSearchIntuneDevices.Text)) -and ($syncHash.txtSearchIntuneDevices.Text -ne 'Search...')){
                    Search-UIDeviceList -ItemsList $syncHash.Data.IntuneDevices -ListObject $syncHash.listIntuneDevices -Identifier 'deviceName' -filter $syncHash.txtSearchIntuneDevices.Text
                }
            }
        )

        #Textbox placeholder remove default text when textbox is being used
        $syncHash.txtSearchIntuneDevices.Add_GotFocus({
            #if it has an example
            if ($syncHash.txtSearchIntuneDevices.Text -eq 'Search...') {
                #clear value and make it black bold ready for input
                $syncHash.txtSearchIntuneDevices.Text = ''
                $syncHash.txtSearchIntuneDevices.Foreground = 'Black'
                #should be black while typing....
            }
            #if it does not have an example
            Else{
                #ensure test is black and medium
                $syncHash.txtSearchIntuneDevices.Foreground = 'Black'
            }
        })

        #Textbox placeholder grayed out text when textbox empty and not in being used
        $syncHash.txtSearchIntuneDevices.Add_LostFocus({
            #if text is null (after it has been clicked on which cleared by the Gotfocus event)
            if ($syncHash.txtSearchIntuneDevices.Text -eq '') {
                #add example back in light gray font
                $syncHash.txtSearchIntuneDevices.Foreground = 'Gray'
                $syncHash.txtSearchIntuneDevices.Text = 'Search...'
            }
        })

        #set text area to enabled if checked
        $syncHash.chkDoRegex.add_Checked({
            (Get-UIProperty -HashName $syncHash "txtRuleRegex" -Wildcard) | Set-UIElement -Enable:$true -ErrorAction SilentlyContinue
        })

        #set text area to disabled if checked
        $syncHash.chkDoRegex.add_Unchecked({
            (Get-UIProperty -HashName $syncHash "txtRuleRegex" -Wildcard) | Set-UIElement -Enable:$false -ErrorAction SilentlyContinue
            #(Get-UIProperty -HashName $syncHash "txtRuleRegex" -Wildcard) | Set-UIElement -text $null -ErrorAction SilentlyContinue
        })

        $syncHash.cmbOUOptions.Add_SelectionChanged({
            If(Test-RSATModule -and Test-IsDomainJoined){
                switch($syncHash.cmbOUOptions.SelectedItem){
                    'Default Computers' {
                            $MoveToOU = Get-WellKnownOU -KnownOU $syncHash.cmbOUOptions.SelectedItem
                            $syncHash.txtOUPath.IsReadOnly = $true
                    }
                    'Computers Root' {
                            $MoveToOU = Get-WellKnownOU -KnownOU $syncHash.cmbOUOptions.SelectedItem
                            $syncHash.txtOUPath.IsReadOnly = $true
                    }
                    'Corresponding User OU' {$MoveToOU = (($syncHash.Data.ADUser.distinguishedname -split ",",2)[1]).replace('UserAccounts','Laptops')}
                    'Custom' {$syncHash.txtOUPath.IsReadOnly = $false}
                }
            }
            #Set the value of text object
            $syncHash.txtOUPath.Text = $MoveToOU
        })

        $syncHash.cmbQueryRule.Add_SelectionChanged({
            If($syncHash.cmbQueryRule.SelectedItem -eq 'Random'){
                $syncHash.txtSample.Text = Generate-RandomName
            }
        })

        $syncHash.cmbRuleAbbrType.Add_SelectionChanged({
            Switch($syncHash.cmbRuleAbbrType.SelectedItem){
                'No Abbr' {
                    $syncHash.cmbRuleAbbrPosition.SelectedItem = $null
                    $syncHash.cmbRuleAbbrPosition.IsEnabled = $false
                    $syncHash.txtRuleAbbrKey.IsEnabled = $false
                    $syncHash.txtRuleAbbrKey.Text = $null
                    $syncHash.lblAbbrExample.Content = $null
                }
                'Chassis' {
                    $SampleValue = 'Laptop=L, Notebook=N, Tablet=T, Desktop=D, Tower=D'
                    $syncHash.cmbRuleAbbrPosition.IsEnabled = $true
                    $syncHash.txtRuleAbbrKey.IsEnabled = $true
                    $syncHash.lblAbbrExample.Content = "eg. $SampleValue"
                    $syncHash.cmbRuleAbbrPosition.SelectedItem = 'After Prefix'
                }
                'Manufacturer' {
                    $SampleValue = 'Dell Inc.=D, Microsoft Corporation=M, HP=H, Lenovo=L, VMware=V'
                    $syncHash.cmbRuleAbbrPosition.IsEnabled = $true
                    $syncHash.txtRuleAbbrKey.IsEnabled = $true
                    $syncHash.lblAbbrExample.Content = "eg. $SampleValue"
                    $syncHash.cmbRuleAbbrPosition.SelectedItem = 'After Prefix'
                }
                'Model' {
                    $SampleValue = 'E6500=D, SurfaceBook 2=M, HP Prodesk 640 G1=H, Virtual Machine=V'
                    $syncHash.cmbRuleAbbrPosition.IsEnabled = $true
                    $syncHash.txtRuleAbbrKey.IsEnabled = $true
                    $syncHash.lblAbbrExample.Content = "eg. $SampleValue"
                    $syncHash.cmbRuleAbbrPosition.SelectedItem = 'After Prefix'
                }
            }
            #default to parameter setting
            If($syncHash.cmbRuleAbbrType.SelectedItem -eq $syncHash.Properties.AbbrType){
                $syncHash.txtRuleAbbrKey.Text = $syncHash.Properties.AbbrKey
            }Else{
                $syncHash.txtRuleAbbrKey.Text = $SampleValue
            }
        })
        #Open App secret popup in XAML
        #=================================
        If($syncHash.Properties.AppConnect){
            #Open-AppSecretPrompt
            $syncHash.btnMSGraphConnect.IsEnabled = $false
            $syncHash.AppSecretPopup.IsOpen = $true

            $syncHash.btnPasteClipboard.Add_Click({
                $syncHash.pwdAppSecret.Password = Get-Clipboard
            })

            $syncHash.btnAppSecretCancel.Add_Click({
                $syncHash.AppSecretPopup.IsOpen = $false
                $syncHash.Properties.AppConnect = $false
                $syncHash.btnMSGraphConnect.IsEnabled = $false
                Update-UIProgress -Runspace $synchash -StatusMsg ('User cancelled app connection. Close and reopen app to try again') -PercentComplete 100 -Color 'Red'
            })

            $syncHash.btnAppSecretSubmit.Add_Click({
                If([string]::IsNullOrEmpty($syncHash.pwdAppSecret.Password) ){
                    $syncHash.lblAppSecretMsg.content = "Invalid Secret, please try again or cancel"
                }Else{
                    $syncHash.AppSecretPopup.IsOpen = $false
                    $syncHash.btnMSGraphConnect.IsEnabled = $true
                }
            })
        }
        #Collapse all features until connected
        $syncHash.tabDetails.Visibility = 'Collapsed'
        $syncHash.tabRenamer.Visibility = 'Collapsed'
        # BUTTON CONTROLS
        #=================================
        $syncHash.btnBack.Add_Click({
            Switch-UITabItem -TabControlObject $syncHash.menuNavigation -Name 'Devices'
        })

        #get sample text and convert it using the regex rules
        $syncHash.btnTestSample.Add_Click({
            $TestSample = @{Query=$syncHash.txtSample.Text}
            $TestRules=@{}
            if($syncHash.txtRuleRegex1.text){$TestRules.Add('RuleRegex1',$syncHash.txtRuleRegex1.text)}
            if($syncHash.txtRuleRegex2.text){$TestRules.Add('RuleRegex2',$syncHash.txtRuleRegex2.text)}
            if($syncHash.txtRuleRegex3.text){$TestRules.Add('RuleRegex3',$syncHash.txtRuleRegex3.text)}
            if($syncHash.txtRuleRegex4.text){$TestRules.Add('RuleRegex4',$syncHash.txtRuleRegex4.text)}
            If($TestRules.count -gt 0){                     $TestSample += @{RegexRules=$TestRules}}
            If($syncHash.cmbRuleAbbrType.Text -ne 'No Abbr'){     $TestSample += @{AbbrType=$syncHash.cmbRuleAbbrType.text}
                If($syncHash.txtRuleAbbrKey.Text.Length -gt 0){   $TestSample += @{device='localhost';AbbrKey=$syncHash.txtRuleAbbrKey.text}}
            }
            If($syncHash.cmbRuleAbbrPosition.SelectedItem){       $TestSample += @{AbbrPos=$syncHash.cmbRuleAbbrPosition.SelectedItem}}
            If($syncHash.txtRulePrefix.Text.Length -gt 0){        $TestSample += @{Prefix=$syncHash.txtRulePrefix.Text}}
            If($syncHash.cmbRuleAddDigits.SelectedItem){          $TestSample += @{AddDigits=$syncHash.cmbRuleAddDigits.SelectedItem}}
            If($syncHash.cmbRuleDigitPosition.SelectedItem){      $TestSample += @{DigitPos=$syncHash.cmbRuleDigitPosition.SelectedItem}}
            $syncHash.txtResults.Text = (Get-NewDeviceName @TestSample)
        })

        #action for connect button
        $syncHash.btnMSGraphConnect.Add_Click({
            $this.IsEnabled = $false
            Update-UIProgress -Runspace $synchash -StatusMsg "Connecting to Microsoft Graph Api..." -Indeterminate

            If($syncHash.Properties.AppConnect)
            {
                If([string]::IsNullOrEmpty($syncHash.pwdAppSecret.Password) ){
                    Update-UIProgress -Runspace $synchash -StatusMsg "Unable to retrieve app secret." -Indeterminate
                }
                <#
                #using MSAL module
                $AppConnectionDetails = @{
                    'TenantId'     = $syncHash.Properties.TenantId
                    'ClientId'     = $syncHash.Properties.ApplicationId
                    'ClientSecret' = $syncHash.pwdAppSecret.Password | ConvertTo-SecureString -AsPlainText -Force
                }
                $syncHash.Data.AuthToken = Get-MsalToken @AppConnectionDetails
                Connect-MSGraphApp -AppId $syncHash.Properties.ApplicationId
                #>
                $AppConnectionDetails = @{
                    'Tenant'    = $syncHash.Properties.TenantId
                    'AppId'     = $syncHash.Properties.ApplicationId
                    'AppSecret' = $syncHash.pwdAppSecret.Password
                }

                Connect-MSGraphApp @AppConnectionDetails
                $syncHash.Data.AuthToken = Connect-IDMGraphApp @AppConnectionDetails
                $syncHash.Data.ConnectedUPN = $syncHash.Properties.ApplicationId
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Connected to MSGraph using appid: {0}" -f $syncHash.Properties.ApplicationId) -Type Start
            }
            Else{
                #minimize the UI to allow for login
                $syncHash.Window.WindowState = 'Minimized'
                $syncHash.Data.ConnectedUPN = (Connect-MSGraph -AdminConsent).UPN
                $syncHash.Data.AuthToken = (Get-IDMGraphAuthToken -User $syncHash.Data.ConnectedUPN)
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Connected to MSGraph using account: {0}" -f $syncHash.Data.ConnectedUPN) -Type Start
            }

            #globalize token for function usage
            $Global:AuthToken = $syncHash.Data.AuthToken
            $syncHash.txtGraphConnectAs.text = $syncHash.Data.ConnectedUPN
            $syncHash.txtAuthTokenExpireDate.text = $syncHash.Data.AuthToken.ExpiresOn


            If($null -ne $syncHash.Data.ConnectedUPN){
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Successfully connected to Azure AD with Auth Token: {0}" -f ($syncHash.Data.AuthToken.Authorization).replace('Bearer','').Trim()) -Type Start
                $syncHash.txtMSGraphConnected.Text = 'Yes'
                $syncHash.txtMSGraphConnected.Foreground = 'Green'
                $syncHash.btnRefreshList.IsEnabled = $true
            }

            #Put window back to its normal size if minimized
            $syncHash.Window.WindowState = 'Normal'
            $syncHash.Window.Topmost = $true
            If($null -ne $syncHash.Data.AuthToken)
            {
                #Update-UIProgress -Runspace $synchash -StatusMsg ('Searching for managed [{0}] devices...' -f $syncHash.properties.DevicePlatform) -Indeterminate


                #grab all managed devices
                #$syncHash.Window.Dispatcher.Invoke("Normal",[action]{
                    #populate Autopilot profiles
                    Add-UIList -Runspace $syncHash -ItemsList (Get-IDMAutopilotProfile) -DropdownObject $syncHash.cmbAPProfile -Identifier 'displayName'
                    #populate device category
                    Add-UIList -Runspace $syncHash -ItemsList (Get-IDMDeviceCategory) -DropdownObject $syncHash.cmbDeviceCategoryList -Identifier 'displayName'

                    #build device query
                    $DeviceParams = @{AuthToken=$syncHash.Data.AuthToken}
                    If($syncHash.Properties.DevicePlatform){
                        $DeviceParams += @{Platform=$syncHash.Properties.DevicePlatform}
                    }
                    If($syncHash.Properties.DevicePrefix){
                        $DeviceParams += @{Filter=$syncHash.Properties.DevicePrefix}
                    }
                    #encapsulate device in array (incase there is only 1)
                    #$syncHash.Data.IntuneDevices = @(Get-IDMDevice @DeviceParams -Expand)
                    #$syncHash.Data.IntuneDevices = @()
                    #$syncHash.Data.IntuneDevices += Get-RunspaceIntuneDevices -Runspace $syncHash @DeviceParams -Expand -ListObject $syncHash.listIntuneDevices
                    Get-RunspaceIntuneDevices -Runspace $syncHash -ParentRunspace $syncHash @DeviceParams -Expand -ListObject $syncHash.listIntuneDevices
                    #Invoke-Command -ScriptBlock {Get-RunspaceIntuneDevices -Runspace $syncHash -ParentRunspace $syncHash @DeviceParams -Expand -ListObject $syncHash.listIntuneDevices} -ArgumentList @($syncHash,$DeviceParams,$syncHash.listIntuneDevices)

                    If($syncHash.Data.IntuneDevices.count -gt 0)
                    {
                        $syncHash.tabDetails.Visibility = 'Visible'
                        If($syncHash.Properties.AllowRename -eq $true){$syncHash.tabRenamer.Visibility = 'Visible'}

                        $syncHash.btnRefreshList.IsEnabled = $true
                        $syncHash.btnNewDeviceName.IsEnabled =$true

                        #Add-UIList -ItemsList $syncHash.Data.IntuneDevices -ListObject $syncHash.listIntuneDevices -Identifier 'deviceName'
                        #Add-UIList -Runspace $syncHash -ItemsList $syncHash.Data.IntuneDevices -ListObject $syncHash.listIntuneDevices -Identifier 'deviceName'
                    }
                    Else{
                        $syncHash.btnRefreshList.IsEnabled = $false
                        $syncHash.btnNewDeviceName.IsEnabled = $false
                        Update-UIProgress -Runspace $synchash -StatusMsg ('No devices found') -PercentComplete 100 -Color 'Red'
                        Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("No devices found. Log into a different Azure tenant or credentials to retrieve registered devices") -Type Error
                    }
                #})

            }
            $this.IsEnabled = $true
        })

        # Select a Device List
        #========================
        #Update UI when Device is selected
        $syncHash.listIntuneDevices.Add_SelectionChanged({
            $syncHash.btnViewIntuneAssignments.IsEnabled = $True
            $syncHash.txtSelectedDevice.text = $syncHash.listIntuneDevices.SelectedItem
            If($syncHash.listIntuneDevices.SelectedItem.length -gt 0)
            {
                $syncHash.Data.SelectedDevice = $syncHash.Data.IntuneDevices | Where {$_.deviceName -eq $syncHash.listIntuneDevices.SelectedItem}
                $syncHash.Data.DeviceStatus = Get-IDMDevicePendingActions -DeviceID $syncHash.Data.SelectedDevice.id
                $syncHash.Data.AutopilotDevice = Get-IDMAutopilotDevice -Serial $syncHash.Data.SelectedDevice.serialNumber -Expand
                $syncHash.cmbDeviceCategoryList.SelectedItem = $syncHash.Data.SelectedDevice.deviceCategoryDisplayName

                If($syncHash.Data.SelectedDevice.userPrincipalName){
                    $syncHash.Data.AssignedUser = Get-IDMDeviceAADUser -UPN $syncHash.Data.SelectedDevice.userPrincipalName
                }Else{
                    $syncHash.Data.AssignedUser = $null
                }

                Switch($syncHash.Data.SelectedDevice.joinType){
                    'hybridAzureADJoined' {
                            $syncHash.txtDeviceJoinType.Text = "Hybrid Azure AD Joined"
                            If(Test-RSATModule -and Test-IsDomainJoined)
                            {
                                Try{
                                    $Global:ADComputer = Get-ADComputer -Identity $syncHash.listIntuneDevices.SelectedItem -ErrorAction Stop
                                    $syncHash.txtStatus.Text = ''
                                    $syncHash.txtStatus.Foreground = 'Green'
                                }
                                Catch{
                                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Failed to get AD object [{1}]. Error: {0}" -f $_.Exception.Message,$syncHash.listIntuneDevices.SelectedItem) -Type Error
                                    $syncHash.txtStatus.Text = 'Failed to retrieve AD object. Please see log for more details'
                                    $syncHash.txtStatus.Foreground = 'Red'
                                }
                            }
                            Else {
                                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("This device must be joined to the domain and have RSAT installed to query AD computer object [{0}]" -f $syncHash.listIntuneDevices.SelectedItem) -Type Warning
                                $syncHash.txtStatus.Text = ("This device must be joined to the domain and have RSAT installed to query AD computer object [{0}]" -f $syncHash.listIntuneDevices.SelectedItem)
                                $syncHash.txtStatus.Foreground = 'Orange'
                            }
                            (Get-UIProperty -HashName $syncHash "ADComputer" -Wildcard) | Set-UIElement -Enable:$true -ErrorAction SilentlyContinue
                    }
                    'azureADJoined' {
                        $syncHash.txtDeviceJoinType.Text = "Azure AD Joined"
                        Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("On-prem AD options are not available for Azure AD joined devices [{0}]" -f $syncHash.listIntuneDevices.SelectedItem) -Type Warning
                        #$syncHash.txtStatus.Foreground = 'Orange'
                        #(Get-UIProperty -HashName $syncHash "ADComputer" -Wildcard) | Set-UIElement -Enable:$false -ErrorAction SilentlyContinue
                    }
                    'azureADRegistered' {
                        $syncHash.txtDeviceJoinType.Text = "Azure AD Registered"
                        Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Limited options are available for Azure AD registered device [{0}]" -f $syncHash.listIntuneDevices.SelectedItem) -Type Warning
                        #(Get-UIProperty -HashName $syncHash "ADComputer" -Wildcard) | Set-UIElement -Enable:$false -ErrorAction SilentlyContinue
                    }
                }
                #check if system running device is joined to the domain and has RSAT tools installed
                $DeviceAsString = $syncHash.Data.SelectedDevice | Select deviceName,osVersion,manufacturer,model,serialNumber,joinType,deviceEnrollmentType,userDisplayName,userPrincipalName | Out-String
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Selected device:`n{0}" -f $DeviceAsString)

                $syncHash.txtDeviceIntuneId.Text = $syncHash.Data.SelectedDevice.id
                $syncHash.txtDeviceAzureId.Text = $syncHash.Data.SelectedDevice.azureADDeviceId
                $syncHash.txtDeviceAzureObjectId.Text = $syncHash.Data.SelectedDevice.azureADObjectId
                $syncHash.txtDeviceSerial.Text = $syncHash.Data.SelectedDevice.serialNumber
                $syncHash.txtDeviceOSver.Text = $syncHash.Data.SelectedDevice.osVersion
                If($syncHash.Data.SelectedDevice.isCompliant){
                    $syncHash.lblDeviceComplianceStatus.Foreground = 'Black'
                    $syncHash.chkDeviceComplianceStatus.IsChecked = $true
                }Else{
                    $syncHash.lblDeviceComplianceStatus.Foreground = 'Gray'
                    $syncHash.chkDeviceComplianceStatus.IsChecked = $false
                }


                #Detemine if device is co-managed
                If($syncHash.Data.SelectedDevice.deviceEnrollmentType -eq 'windowsCoManagement'){
                    $syncHash.lblDeviceCoManagedStatus.Foreground = 'Black'
                    $syncHash.chkDeviceCoManagedStatus.IsChecked = $true
                }Else{
                    $syncHash.lblDeviceCoManagedStatus.Foreground = 'Gray'
                    $syncHash.chkDeviceCoManagedStatus.IsChecked = $false
                }

                 #Detemine if device is an AVD host
                 If($syncHash.Data.SelectedDevice.skuFamily -eq 'EnterpriseMultisession'){
                    $syncHash.lblDeviceMultiSession.Foreground = 'Black'
                    $syncHash.chkDeviceMultiSession.IsChecked = $true
                }Else{
                    $syncHash.lblDeviceMultiSession.Foreground = 'Gray'
                    $syncHash.chkDeviceMultiSession.IsChecked = $false
                }

                #https://docs.microsoft.com/en-us/graph/api/resources/intune-devices-managementagenttype?view=graph-rest-1.0
                switch($syncHash.Data.SelectedDevice.managementAgent){
                    'configurationManagerClientMdm' {$syncHash.txtDeviceMDM.Text = 'MECM & MDM'}
                    'configurationManagerClient' {$syncHash.txtDeviceMDM.Text = 'MECM'}
                    'intuneClient' {$syncHash.txtDeviceMDM.Text = 'Intune MDM'}
                    'Mdm' {$syncHash.txtDeviceMDM.Text = 'Intune MDM'}
                    'jamf' {$syncHash.txtDeviceMDM.Text = 'Jamf MDM'}
                    'googleCloudDevicePolicyController' {$syncHash.txtDeviceMDM.Text = 'Google CloudDPC.'}
                    default {$syncHash.txtDeviceMDM.Text = 'None'}
                }

                #determine if device Autopilot ready...meaning its hardware id has been uploaded with Autopilot devices
                If($syncHash.Data.AutopilotDevice){
                    $syncHash.lblDeviceAutopilotReadyStatus.Foreground = 'Black'
                    $syncHash.chkDeviceAutopilotReadyStatus.IsChecked = $true
                    #update autopilot group tag
                    $syncHash.txtAPProfileGroupTag.text = $syncHash.Data.AutopilotDevice.groupTag
                    $syncHash.cmbAPProfile.SelectedItem = $syncHash.Data.AutopilotDevice.deploymentProfile.displayName
                }Else{
                    $syncHash.lblDeviceAutopilotReadyStatus.Foreground = 'Gray'
                    $syncHash.chkDeviceAutopilotReadyStatus.IsChecked = $false
                    $syncHash.txtAPProfileGroupTag.text = $Null
                    $syncHash.cmbAPProfile.SelectedItem = $Null
                }
                (Get-UIProperty -HashName $syncHash "APProfile" -Wildcard) | Set-UIElement -Enable:($syncHash.chkDeviceAutopilotReadyStatus.IsChecked -eq $True) -ErrorAction SilentlyContinue

                #determine if device has been autopiloted (look for ZTDID and profile type). Is there a better way???
                If($syncHash.Data.SelectedDevice.physicalIds -match '\[ZTDID\]' -and $syncHash.Data.SelectedDevice.profileType -ne 'RegisteredDevice'){
                    $syncHash.lblDeviceAutopilotedStatus.Foreground = 'Black'
                    $syncHash.txtDeviceAutopilotedStatus.Foreground = 'Green'
                    $syncHash.txtDeviceAutopilotedStatus.Text = 'Online Profile'
                }ElseIf($syncHash.Data.SelectedDevice.enrollmentProfileName -like 'OfflineAutopilotprofile*'){
                    $syncHash.lblDeviceAutopilotedStatus.Foreground = 'Black'
                    $syncHash.txtDeviceAutopilotedStatus.Foreground = 'Blue'
                    $syncHash.txtDeviceAutopilotedStatus.Text = 'Offline JSON'
                }Else{
                    $syncHash.lblDeviceAutopilotedStatus.Foreground = 'Gray'
                    $syncHash.txtDeviceAutopilotedStatus.Foreground = 'Gray'
                    $syncHash.txtDeviceAutopilotedStatus.Text = 'Not Performed'
                }

                #Display Assigned User
                $syncHash.txtAssignedUserName.text = $syncHash.Data.AssignedUser.displayName
                $syncHash.txtAssignedUserUPN.text = $syncHash.Data.AssignedUser.userPrincipalName
                $syncHash.txtAssignedUserEmail.text = $syncHash.Data.AssignedUser.mail
                $syncHash.txtAssignedUserId.text = $syncHash.Data.AssignedUser.id

                If($syncHash.Data.AssignedUser.signInSessionsValidFromDateTime){
                    $syncHash.txtAssignedUserLastSignIn.text = [datetime]$syncHash.Data.AssignedUser.signInSessionsValidFromDateTime
                }Else{
                    $syncHash.txtAssignedUserLastSignIn.text = ''
                }

                If($syncHash.Data.AssignedUser.onPremisesSyncEnabled -eq $True){
                    $syncHash.lblAssignedUserADSyncd.Foreground = 'Black'
                    $syncHash.chkAssignedUserADSyncd.IsChecked = $true
                    $syncHash.txtAssignedUserDN.text = $syncHash.Data.AssignedUser.onPremisesDistinguishedName
                    $syncHash.lblAssignedUserDN.Visibility = 'Visible'
                    $syncHash.txtAssignedUserDN.Visibility = 'Visible'

                    $syncHash.Data.ADUser = '' | Select DistinguishedName,Name,SamAccountName,UserPrincipalName,SID
                    $syncHash.Data.ADUser.DistinguishedName = $syncHash.Data.AssignedUser.onPremisesDistinguishedName
                    $syncHash.Data.ADUser.Name = $syncHash.Data.AssignedUser.displayName
                    $syncHash.Data.ADUser.SamAccountName = $syncHash.Data.AssignedUser.onPremisesSamAccountName
                    $syncHash.Data.ADUser.UserPrincipalName = $syncHash.Data.AssignedUser.onPremisesUserPrincipalName
                    $syncHash.Data.ADUser.SID = $syncHash.Data.AssignedUser.onPremisesSecurityIdentifier

                    $syncHash.txtADUserDN.text = $syncHash.Data.AssignedUser.onPremisesDistinguishedName
                }
                Else{
                    $syncHash.lblAssignedUserADSyncd.Foreground = 'Gray'
                    $syncHash.chkAssignedUserADSyncd.IsChecked = $false
                    $syncHash.txtAssignedUserDN.text = ''
                    $syncHash.lblAssignedUserDN.Visibility = 'Hidden'
                    $syncHash.txtAssignedUserDN.Visibility = 'Hidden'
                    $syncHash.Data.ADUser = $Null
                    $syncHash.txtADUserDN.text = ''
                }
                (Get-UIProperty -HashName $syncHash "ADUser" -Wildcard) | Set-UIElement -Enable:($syncHash.Data.AssignedUser.onPremisesSyncEnabled -eq $True) -ErrorAction SilentlyContinue


                #$syncHash.txtAssignedUser.text = $syncHash.Data.AssignedUser.$($syncHash.cmbUserDisplayOptions.SelectedItem)
                If($null -ne $syncHash.Data.DeviceStatus){
                    $statusMsg = @()
                    switch($syncHash.Data.DeviceStatus.actionName){
                        'setDeviceName' {$statusMsg += "Device is pending rename to:{0}" -f "$($syncHash.Data.DeviceStatus.passcode)" ;$FontColor = 'Red'}
                        'rebootNow' {$statusMsg += "Device is pending reboot";$FontColor = 'Red'}
                    }
                    $syncHash.txtDeviceStatus.Visibility='Visible'
                    $syncHash.txtDeviceStatus.Text = $statusMsg -join "`n"
                    $syncHash.txtDeviceStatus.Foreground = $FontColor
                }Else{
                    $syncHash.txtDeviceStatus.Visibility='Hidden'
                }
            }
        })

        # Refresh Device List
        #========================
        $syncHash.btnRefreshList.Add_Click({
            $this.IsEnabled = $false
            Update-UIProgress -Runspace $synchash -StatusMsg ('Refreshing managed [{0}] device list...' -f $syncHash.properties.DevicePlatform) -Indeterminate

            #clear current list
            $syncHash.btnRefreshList.Dispatcher.Invoke("Normal",[action]{
                $syncHash.txtSearchIntuneDevices.Text = 'Search...'
                $syncHash.listIntuneDevices.Items.Clear()
            })

            #grab all managed devices
            If($null -ne $syncHash.Data.AuthToken){
                $DeviceParams = @{AuthToken=$syncHash.Data.AuthToken}
                If($syncHash.Properties.DevicePlatform){
                    $DeviceParams += @{Platform=$syncHash.Properties.DevicePlatform}
                }
                If($syncHash.Properties.DevicePrefix){
                    $DeviceParams += @{Filter=$syncHash.Properties.DevicePrefix}
                }
                #refresh list
                #$syncHash.Data.IntuneDevices = @()
                #$syncHash.Data.IntuneDevices += Get-RunspaceIntuneDevices -Runspace $syncHash @DeviceParams -Expand -ListObject $syncHash.listIntuneDevices
                Get-RunspaceIntuneDevices -Runspace $syncHash -ParentRunspace $syncHash @DeviceParams -Expand -ListObject $syncHash.listIntuneDevices
                #$syncHash.Data.IntuneDevices = @(Get-IDMDevice @DeviceParams -Expand)
            }

            If($syncHash.Data.IntuneDevices.count -gt 0)
            {
                $syncHash.tabDetails.Visibility = 'Visible'
                $syncHash.tabRenamer.Visibility = 'Visible'

                $syncHash.btnRefreshList.IsEnabled = $true
                $syncHash.btnNewDeviceName.IsEnabled =$true

                Update-UIProgress -Runspace $synchash -StatusMsg ('Found {0} devices the meet platform requirement [{1}]' -f $syncHash.Data.IntuneDevices.count,$syncHash.properties.DevicePlatform) -PercentComplete 100

                #Add-UIList -ItemsList $syncHash.Data.IntuneDevices -ListObject $syncHash.listIntuneDevices -Identifier 'deviceName'
            }
            Else{
                $syncHash.btnRefreshList.IsEnabled = $false
                $syncHash.btnNewDeviceName.IsEnabled = $false
                Update-UIProgress -Runspace $synchash -StatusMsg ('No devices found') -PercentComplete 100 -Color 'Red'
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("No devices found. Log into a different Azure tenant or credentials to retrieve registered devices") -Type Error
            }
            $this.IsEnabled = $true
        })


        $syncHash.btnAPProfileExport.Add_Click({
            $this.IsEnabled = $false
            $syncHash.btnAPProfileChange.Dispatcher.Invoke("Normal",[action]{
                If($syncHash.cmbAPProfile.SelectedItem){
                    $SelectedAPProfile = Get-IDMAutopilotProfile | where DisplayName -eq $syncHash.cmbAPProfile.SelectedItem
                    $SelectedAPProfile | ConvertTo-AutopilotConfigurationJSON | Out-File "$env:UserProfile\Desktop\AutopilotConfigurationFile.json" -Encoding ASCII -Force

                    $Message=("Autopilot Profile [{0}] was exported to: [{1}]" -f $SelectedAPProfile.displayName,"$env:UserProfile\Desktop\AutopilotConfigurationFile.json")
                    $syncHash.txtStatus.Text = $Message
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message $Message
                }
            })
            $this.IsEnabled = $true
        })

        $syncHash.btnHardwareDeviceInfo.Add_Click({
            $this.IsEnabled = $false
            $syncHash.btnHardwareDeviceInfo.Dispatcher.Invoke("Normal",[action]{
                If($syncHash.Data.SelectedDevice){
                    If($syncHash.chkHardwareDeviceRemote.IsChecked -eq $true){
                        Try{
                            $DeviceInfo = Get-PlatformInfo -DeviceName $syncHash.Data.SelectedDevice.deviceName -ErrorAction Stop
                        }
                        Catch{
                            $syncHash.txtStatus.Foreground = 'Red'
                            $syncHash.txtStatus.Text =('{1}' -f $_.exception.message)
                        }

                        $DeviceData = New-Object PSObject
                        Foreach($p in ($syncHash.Data.SelectedDevice | Get-Member -MemberType NoteProperty) )
                        {
                            $DeviceData | Add-Member NoteProperty $p.name -Value $syncHash.Data.SelectedDevice.($p.name)
                        }
                        #$AADObjects | Where displayName -eq 'DTOLAB-46VEYL1'
                        If($DeviceInfo){
                            Foreach($p in ($DeviceInfo | Get-Member -MemberType NoteProperty))
                            {
                                If($p.name -notin ($DeviceData | Get-Member -MemberType NoteProperty).Name){
                                    $DeviceData | Add-Member NoteProperty $p.name -Value $DeviceInfo.($p.name)
                                }
                            }
                            # Add the object to our array of output objects
                        }
                    }

                    <#
                    $Data = ($syncHash.Data.SelectedDevice | Select deviceRegistrationState,azureADRegistered,easDeviceId,userPrincipalName,userId,wiFiMacAddress,
                                                            easActivated,userDisplayName,aadRegistered,complianceState,deviceType,joinType,specificationVersion,skuNumber,serialNumber,ownerType,
                                                            processorArchitecture,isEncrypted,managementState,ethernetMacAddress,model,physicalMemoryInBytes,
                                                            id,emailAddress,osVersion,deviceEnrollmentType,azureADDeviceId,freeStorageSpaceInBytes,
                                                            operatingSystem,manufacturer,managementAgent,deviceName,chassisType,enrollmentProfileName,
                                                            totalStorageSpaceInBytes,autopilotEnrolled,managedDeviceOwnerType,
                                                            accountEnabled, deviceId,
                                                            skuFamily).psobject.properties | foreach -begin {$h=@{}} -process {$h."$($_.Name)" = $_.Value} -end {$h}
                                                            #>
                    $Data = ($syncHash.Data.SelectedDevice | Select *).psobject.properties | foreach -begin {$h=@{}} -process {$h."$($_.Name)" = $_.Value} -end {$h}
                    $syncHash.lstHardwareDevice.ItemsSource = $Data
                }
                Else{
                    $syncHash.txtStatus.Foreground = 'Red'
                    $syncHash.txtStatus.Text = 'You must select a device first'
                }
            })
            $this.IsEnabled = $true
        })

        # Update Category
        #========================
        $syncHash.btnDeviceCategoryChange.IsEnabled = $false
        $syncHash.cmbDeviceCategoryList.Add_SelectionChanged({
            If($syncHash.cmbDeviceCategoryList.SelectedItem -ne $syncHash.Data.SelectedDevice.deviceCategoryDisplayName){
                $syncHash.btnDeviceCategoryChange.IsEnabled = $true
            }Else{
                $syncHash.btnDeviceCategoryChange.IsEnabled = $false
            }
        })

        # Update Category
        #========================
        $syncHash.btnDeviceCategoryChange.Add_Click({
            $syncHash.btnDeviceCategoryChange.Dispatcher.Invoke("Normal",[action]{
                Set-IDMDeviceCategory -DeviceID $syncHash.Data.SelectedDevice.id -Category $syncHash.cmbDeviceCategoryList.SelectedItem
                $syncHash.txtStatus.Foreground = 'Green'
                $syncHash.txtStatus.Text = ("Updated device [{0}] category to [{1}]" -f $syncHash.Data.SelectedDevice.deviceName,$syncHash.cmbDeviceCategoryList.SelectedItem)
            })

        })

        # Update Autopilot Group Tag
        #============================
        $syncHash.btnAPProfileChange.Add_Click({
            $syncHash.btnAPProfileChange.Dispatcher.Invoke("Normal",[action]{
                Set-IDMAutopilotDeviceTag -AutopilotID $syncHash.Data.AutopilotDevice.id -GroupTag $syncHash.txtAPProfileGroupTag.text
                $syncHash.txtStatus.Foreground = 'Green'
                $syncHash.txtStatus.Text = ("Updated Autopilot device [{0}] group tag to [{1}]" -f $syncHash.Data.SelectedDevice.deviceName,$syncHash.txtAPProfileGroupTag.text)
            })

        })

        # Sync Computer object from ConfigMgr
        #========================
        $syncHash.btnCMSiteSync.Add_Click({
            #attempt to reconnect to CM (this is only if initial connection is not made and server and code has been changed)
            If($syncHash.txtCMSiteCode.text -and $syncHash.txtCMSiteServer.text -and ($syncHash.txtRSAT.text -eq 'No') )
            {
                If(Test-CMModule -CMSite $syncHash.txtCMSiteCode.text -CMSite $syncHash.txtCMSiteServer.text){
                    $syncHash.txtRSA.text = 'Yes';$syncHash.txtRSAT.Foreground = 'Green'
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Configuration Manager PowerShell module is installed: {0}" -f (Test-CMModule -CMSite $syncHash.txtCMSiteCode.text -CMSite $syncHash.txtCMSiteServer.text -Passthru)) -Type Info
                    $syncHash.btnCMDeviceSync.IsEnabled = $true
                }Else{
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Configuration Manager PowerShell module must be installed to be able to query CM device names") -Type Error
                    $syncHash.txtRSAT.text = 'No'
                    $syncHash.btnCMSiteDeviceSync.IsEnabled = $False
                }
            }
            Else{
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Configuration Manager settings are not configured, configure them to use the CM feature") -Type Warning
            }
            #grab all CM devices
            $AllCMDevices = Get-CMDevice
            #determine how to filter CM devices
            switch($syncHash.cmbCMSiteAttribute.SelectedItem){
                'SerialNumber' {$Query = "select SMS_R_System.Name, SMS_G_System_SYSTEM_ENCLOSURE.SerialNumber from  SMS_R_System inner join SMS_G_System_SYSTEM_ENCLOSURE on SMS_G_System_SYSTEM_ENCLOSURE.ResourceID = SMS_R_System.ResourceId"}
                'MacAddress'   {}
                'LastLoggedOnUser' {}
                'AssetTag'  {}
                default {$Query = "select SMS_R_System.Name, SMS_G_System_SYSTEM_ENCLOSURE.SerialNumber from  SMS_R_System inner join SMS_G_System_SYSTEM_ENCLOSURE on SMS_G_System_SYSTEM_ENCLOSURE.ResourceID = SMS_R_System.ResourceId"}
            }
            $CMdeviceMatch = Get-WmiObject -Query $Query -ComputerName $syncHash.txtCMSiteServer.text -Namespace "root/SMS/$($syncHash.txtCMSiteCode.text)"
            #display CM device based on matched filter
            $syncHash.txtCMSiteResult.text = $CMdeviceMatch
            #display device OU from AD (if exists)
            $syncHash.txtADComputerDN.text = (Get-ADComputer -Name $syncHash.txtCMSiteResult.text).DistinguishedName
        })

        # Sync Device Assignments - WORK IN PROGRESS
        #========================
        $syncHash.btnViewIntuneAssignments.Add_Click({
            # disable this button to prevent multiple export.
            $syncHash.btnViewIntuneAssignments.Dispatcher.Invoke("Normal",[action]{
                $this.IsEnabled = $false
                Update-UIProgress -Runspace $synchash -StatusMsg ("Please wait while loading device and user assignment data, this can take a while...") -Indeterminate

                #Get-RunspaceIntuneAssignments -Runspace $syncHash -ParentRunspace $syncHash -Platform $syncHash.Properties.DevicePlatform -TargetSet @{devices=$syncHash.Data.SelectedDevice.azureADObjectId;users=$syncHash.Data.AssignedUser.id} -IncludePolicySetInherits
                #Update-UIProgress -Runspace $synchash -StatusMsg ("Please wait while loading device and user assignment data, this can take a while...") -Indeterminate

                #$syncHash.Data.DeviceAssignments = Get-IDMIntuneAssignments -Target Devices -Platform $syncHash.Properties.DevicePlatform -TargetId $syncHash.txtDeviceAzureObjectId.text -IncludePolicySetInherits
                #Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Found {0} {1} device assignments for device [{2}]" -f $syncHash.Data.DeviceAssignments.count,$syncHash.Properties.DevicePlatform,$syncHash.txtSelectedDevice.text) -Type info
                #$syncHash.Data.UserAssignments = Get-IDMIntuneAssignments -Target Users -Platform $syncHash.Properties.DevicePlatform -TargetId $syncHash.txtAssignedUserId.text -IncludePolicySetInherits
                #Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Found {0} {1} user assignments for user [{2}]" -f $syncHash.Data.UserAssignments.count,$syncHash.Properties.DevicePlatform,$syncHash.txtAssignedUserUPN.text) -Type info
                #Show-UIAssignmentsWindow -DeviceData $syncHash.Data.SelectedDevice -UserData $syncHash.Data.AssignedUser -SupportScripts @("$FunctionPath\Intune.ps1","$FunctionPath\Runspace.ps1") -AuthToken $syncHash.Data.AuthToken
                #Show-UIAssignmentsWindow -DeviceData $syncHash.Data.SelectedDevice -DeviceAssignments $syncHash.Data.DeviceAssignments -UserData $syncHash.Data.AssignedUser -UserAssignments $syncHash.Data.UserAssignments -IncludeInherited

                <#
                Show-UIAssignmentsWindow -ParentSynchash $syncHash -AuthToken $syncHash.Data.AuthToken `
                                                -DeviceData $syncHash.Data.SelectedDevice `
                                                -UserData $syncHash.Data.AssignedUser `
                                                -SupportScripts @("$FunctionPath\Intune.ps1","$FunctionPath\Runspace.ps1","$FunctionPath\UIControls.ps1") -IncludeInherited
                #>
                $syncHash.AssignmentWindow = Show-UIAssignmentsWindow -ParentSynchash $syncHash -AuthToken $syncHash.Data.AuthToken `
                                                -DeviceData $syncHash.Data.SelectedDevice `
                                                -UserData $syncHash.Data.AssignedUser `
                                                -SupportScripts @("$FunctionPath\Runspace.ps1","$FunctionPath\UIControls.ps1") -IncludeInherited -LoadOnStartup


                <#
                $syncHash.Data.DeviceAssignments + $syncHash.Data.UserAssignments |
                    Select @{n='Assignment Name';e={$_.Name}}, @{n='Assignment Category';e={$_.Type}}, Status, Target, @{n='Azure AD group';e={$_.Group}},GroupType,@{n='Member Of';e={If($_.Target -eq 'Device'){$syncHash.Data.SelectedDevice.deviceName}Else{$syncHash.Data.AssignedUser.userPrincipalName} }}|
                    Out-GridView -Title ("Assignments :: Device [{0}], Assigned user [{1}]" -f $syncHash.Data.SelectedDevice.deviceName,$syncHash.Data.AssignedUser.userPrincipalName)
                #>

            })

        })

        #Currently Keep check and disabled
        $syncHash.chkNewDeviceNameIncrement.IsEnabled = $false
        $syncHash.chkNewDeviceNameIncrement.IsChecked = $true
        $syncHash.btnNewDeviceName.IsEnabled = $false

        # Sync AD Computer
        #========================
        $syncHash.btnADComputerSync.Add_Click({
            # disable this button to prevent multiple export.
            $this.IsEnabled = $false
            $syncHash.Window.Dispatcher.Invoke([action]{
                Import-Module ActiveDirectory
                #START to build computer parameter
                $GetComputersParam = @{identity=$syncHash.listIntuneDevices.SelectedItem}
                $CompSearchParmAsString = $GetComputersParam.GetEnumerator() |%{ "$($_.Name) = $($_.Value)" }
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Searching for AD computers within the parameters:`n{0}" -f $CompSearchParmAsString)
                # list all computers in AD
                $syncHash.Data.ADComputer = Get-ADComputer @GetComputersParam
                If($syncHash.Data.ADComputer){
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Found computer object in AD" )
                    $syncHash.txtADComputerDN.Text = $syncHash.Data.ADComputer.DistinguishedName
                    #$syncHash.txtADComputerOUPath.Text = ($syncHash.Data.ADComputer.DistinguishedName).Substring(($syncHash.Data.ADComputer.DistinguishedName).IndexOf('OU='))
                    #$syncHash.txtADComputerOU.Text = ($syncHash.Data.ADComputer.DistinguishedName).Split(',')[1].Split('OU=')[1]
                }
                # disable this button to prevent multiple export.
                $this.IsEnabled = $true
            },'Normal')
        })

        # Sync AD User
        #========================
        $syncHash.btnADUserSync.Add_Click({
            #grab User from UPN

            #$AADUserObjectName = ($syncHash.txtAssignedUser.text -Split '@','')[0].Trim()
            [System.Net.Mail.MailAddress]$AadUserMailAddress = $syncHash.Data.AssignedUser.userPrincipalName
            $syncHash.Data.ADUser = Get-ADUser -Identity $AadUserMailAddress.User -ErrorAction SilentlyContinue

            If($null -eq $syncHash.Data.ADUser.DistinguishedName){
                $syncHash.txtADUserDN.text = "No AD User Found"
            }
            Else{
                $AdUserAsString = $syncHash.Data.ADUser | Select DistinguishedName,Name,SamAccountName,UserPrincipalName | Format-List | Out-String
                Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Found AD user:`n{0}" -f $AdUserAsString)
                $syncHash.txtADUserDN.text = $syncHash.Data.ADUser.DistinguishedName
            }
        })
        # Generate new name
        #========================
        $syncHash.btnNewDeviceNameGen.Add_Click({
            #START to build computer parameter
            $GetComputersParam = @{filter='*'}
            #Get search DN for computers
            switch($syncHash.cmbSearchInOptions.SelectedItem){
                'User Root OU'  {
                    #get the root OU
                    $SearchOU = ($syncHash.Data.ADUser.DistinguishedName -split ",",3)[2]
                    $GetComputersParam += @{SearchBase=$SearchOU;searchscope='subtree'}
                }
                'Computers Root OU'  {
                    $SearchOU = Get-WellKnownOU -KnownOU 'Computers Root'
                    $GetComputersParam += @{SearchBase=$SearchOU}
                }
                'Computers Default OU'  {
                    $SearchOU = Get-WellKnownOU -KnownOU 'Default Computers'
                    $GetComputersParam += @{SearchBase=$SearchOU;searchscope='subtree'}
                }
                'Custom'        {
                    If($syncHash.txtSearchFilter.Text -ne '*'){
                        $SearchOU = $syncHash.txtSearchFilter.Text
                        $GetComputersParam += @{SearchBase=$SearchOU}
                    }
                }
                default{
                    $GetComputersParam += @{searchscope='subtree'}
                }
            }
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Found {0} computer(s) in AD from search criteria" -f $Computers.count)

            # list all computers in AD
            $Computers = Get-ADComputer @GetComputersParam
            #TEST $Computers = @('BLY05A001','BLY05A002','BLY05A003','BLY05A005')
            $CompSearchParmAsString = $GetComputersParam.GetEnumerator() |%{ "$($_.Name) = $($_.Value)" }
            Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Searching for AD computers within the parameters:`n{0}" -f $CompSearchParmAsString)

            switch($syncHash.cmbQueryRule.SelectedItem){
                'User OU Name' {
                        #get the current user OU to be used as query
                        $syncHash.Data.QueryString = ($syncHash.Data.ADUser.DistinguishedName -split ",",3)[1] -replace 'OU=',''
                }
                'User Name' {$syncHash.Data.QueryString = $syncHash.Data.ADUser.SamAccountName}
                'User Display Name' {$syncHash.Data.QueryString = ($syncHash.Data.ADUser.displayName) -replace ' ',''}
                'Device Name' {$syncHash.Data.QueryString = $syncHash.listIntuneDevices.SelectedItem}
                'Device SerialNumber' {
                    #$syncHash.Data.QueryString = Get-CIMInstance -Class Win32_Bios -ComputerName $syncHash.listIntuneDevices.SelectedItem | Select -ExpandProperty SerialNumber
                    $syncHash.Data.QueryString = $syncHash.Data.SelectedDevice.serialNumber
                }
                'Device AssetTag' {$syncHash.Data.QueryString = Get-CIMInstance -Class Win32_SystemEnclosure -ComputerName $syncHash.listIntuneDevices.SelectedItem | Select-Object -ExpandProperty SMBiosAssetTag}
                'Random' {$syncHash.Data.QueryString = Generate-RandomName}
            }
            #get what loaded in rules
            $syncHash.Data.Rules = @{}
            IF($syncHash.txtRuleRegex1.text){$syncHash.Data.Rules['RuleRegex1'] = $syncHash.txtRuleRegex1.text}
            IF($syncHash.txtRuleRegex2.text){$syncHash.Data.Rules['RuleRegex2'] = $syncHash.txtRuleRegex2.text}
            IF($syncHash.txtRuleRegex3.text){$syncHash.Data.Rules['RuleRegex3'] = $syncHash.txtRuleRegex3.text}
            IF($syncHash.txtRuleRegex4.text){$syncHash.Data.Rules['RuleRegex4'] = $syncHash.txtRuleRegex4.text}
            #BUILD NEW COMPUTER NAME using query string and Query Rules
            $ComputerSample = @{Query=$syncHash.Data.QueryString;RegexRules=$syncHash.Data.Rules}
            If($syncHash.txtRuleAbbrKey.Text.Length -gt 0){$ComputerSample += @{device=$syncHash.listIntuneDevices.SelectedItem;AbbrKey=$syncHash.txtRuleAbbrKey.text}}
            If($syncHash.txtRulePrefix.Text.Length -gt 0){$ComputerSample += @{Prefix=$syncHash.txtRulePrefix.Text}}
            #If($null -ne $syncHash.cmbRuleAddDigits.SelectedItem){$ComputerSample += @{AppendDigits=$syncHash.cmbRuleAddDigits.SelectedItem}}
            $d=0
            $UsedDigits = @()
            #get the used digits on inventoried computers
            If($syncHash.cmbRuleAddDigits.SelectedItem){
                $AppendDigits = $syncHash.cmbRuleAddDigits.SelectedItem
                $Computers.Name | %{ $UsedDigits += $_.substring($_.length-$AppendDigits) }
            }
            Else{
                #grabs all digits at end of string
                $Computers.Name | %{ $UsedDigits += [regex]::Matches($_, "\d+(?!.*\d+)").value }
            }
            $MaxDigit = ($UsedDigits | Measure-Object -Maximum -Property Length).Maximum
            $MaxLoop = ("{0:d$MaxDigit}" -f 9) -replace '0','9'
            #loop through all available digits to see what not used
            #stop once you grab one
            for($i=1;$i -le $MaxLoop;$i++)
            {
                If(("{0:d$MaxDigit}" -f $i) -notin $UsedDigits){
                    $NextIncrement = ("{0:d$MaxDigit}" -f $i)
                    break
                }
            }
            #populate new device name
            If($syncHash.chkNewDeviceNameIncrement.IsChecked){
                $syncHash.txtNewDeviceName.Text = ((Get-NewDeviceName @ComputerSample) + $NextIncrement)
            }
            Else{
                $syncHash.txtNewDeviceName.Text = (Get-NewDeviceName @ComputerSample)
            }
            $syncHash.btnNewDeviceName.IsEnabled = $true
        })

        # Rename Device
        #========================
        $syncHash.btnNewDeviceName.Add_Click({
            $syncHash.Window.Dispatcher.Invoke([action]{
                #attempt to rename object in Intune
                Try{
                    Invoke-IDMDeviceAction -DeviceID $syncHash.Data.SelectedDevice.id -Action Rename -NewDeviceName $syncHash.txtNewDeviceName.Text -ErrorAction Stop
                    $syncHash.txtNewDeviceNameStatus.Text = 'Successfully renamed device.'
                    $syncHash.txtNewDeviceNameStatus.Foreground = 'Green'
                    $MoveableObject = $true
                }
                Catch{
                    Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Failed to rename device. Error: {0}" -f $_.Exception.Message) -Type Error
                    $syncHash.txtNewDeviceNameStatus.Text = 'Failed to rename device. Please see log for more details'
                    $syncHash.txtNewDeviceNameStatus.Foreground = 'Red'
                    $MoveableObject = $false
                }
                #attempt to move object in AD
                If($MoveableObject -and $syncHash.chkNewDeviceNameMoveOU.IsChecked -and ($null -ne $syncHash.Data.ADComputer) -and ($null -ne $syncHash.txtOUPath.Text)){
                    Try{
                        Move-ADObject -Identity $syncHash.Data.ADComputer.DistinguishedName -TargetPath $syncHash.txtOUPath.Text
                    }
                    Catch{
                        Write-UIOutput -Runspace $syncHash -UIObject $syncHash.Logging-Message ("Failed to move AD object [{2}] to [{1}]. Error: {0}" -f $_.Exception.Message,$syncHash.txtOUPath.Text,$syncHash.Data.ADComputer.Name) -Type Error
                        $syncHash.txtNewDeviceNameStatus.Text = 'Failed to move device. Please see log for more details'
                        $syncHash.txtNewDeviceNameStatus.Foreground = 'Red'
                    }
                }
            })
        })

        #Allow UI to be dragged around screen
        $syncHash.Window.Add_MouseLeftButtonDown( {
            $syncHash.Window.DragMove()
        })
        #action for exit button
        $syncHash.btnExit.Add_Click({
            Close-IDMWindow
        })


        $syncHash.Window.Add_KeyDown({
            #allow window in back if ESC is hit
            if ( ($_.Key -match 'Esc') -and $syncHash.Window.Topmost ) {
                $syncHash.Window.Topmost = $false
            }
            #and set inf front if hit again
            ElseIf ( ($_.Key -match 'Esc') ) {
                $syncHash.Window.Topmost = $true
            }
        })

        # Before the UI is displayed
        # Create a timer dispatcher to watch for value change externally on regular interval
        # update those values when found using scriptblock ($updateblock)
        $syncHash.Window.Add_SourceInitialized({
            ## create a timer
            $timer = new-object System.Windows.Threading.DispatcherTimer
            ## set to fire 4 times every second
            $timer.Interval = [TimeSpan]"0:0:0.01"
            ## invoke the $updateBlock after each fire
            $timer.Add_Tick( $updateUI )
            ## start the timer
            $timer.Start()

            if( -Not($timer.IsEnabled) ) {
               $syncHash.Error = "Timer didn't start"
            }
        })

        #Add smooth closing for Window
        $syncHash.Window.Add_Loaded({ $syncHash.isLoaded = $True })
        $syncHash.Window.Add_Closing({ $syncHash.isClosing = $True; Close-IDMWindow })
        $syncHash.Window.Add_Closed({ $syncHash.isClosed = $True })
        #make sure this display on top of every window
        $syncHash.Window.Topmost = $true
        $syncHash.window.ShowDialog()
        $syncHash.Error = $Error
    }) # end scriptblock
    #collect data from runspace
    $Data = $syncHash
    #invoke scriptblock in runspace
    $PowerShellCommand.Runspace = $IDMRunSpace
    $AsyncHandle = $PowerShellCommand.BeginInvoke()
    #wait until runspace is completed before ending
    If($Wait){
        do {
            Start-sleep -m 100 }
        while (!$AsyncHandle.IsCompleted)
        #end invoked process
        $null = $PowerShellCommand.EndInvoke($AsyncHandle)
    }

    #cleanup registered object
    Register-ObjectEvent -InputObject $syncHash.Runspace `
            -EventName 'AvailabilityChanged' `
            -Action {
                    if($Sender.RunspaceAvailability -eq "Available")
                    {
                        $Sender.Closeasync()
                        $Sender.Dispose()
                        # Speed up resource release by calling the garbage collector explicitly.
                        # Note that this will pause *all* threads briefly.
                        [GC]::Collect()
                    }
                } | Out-Null
    return $Data
}
#endregion
##*=============================================
##* MAIN
##*=============================================
#Call UI and store it in same variable as runspace ($syncHash); allows easier troubleshooting
$global:syncHash = Show-IDMWindow -XamlFile $XAMLFilePath -StylePath $StylePath -FunctionPath $FunctionPath -Properties $ParamProps -Wait
#Show properties UI took in
$global:syncHash.Properties
#show data out
$global:syncHash.Data
#show any UI error from isolated runspace
$global:syncHash.Error

$Global:AuthToken = $syncHash.Data.AuthToken
