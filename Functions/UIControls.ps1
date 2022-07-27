#region FUNCTION: Builds dynamic variables in form with alias
Function Get-UIVariable{
    param(
        [Parameter(Mandatory = $true, Position=0)]
        [string]$Name,
        [string]$Prefix  = 'ui',
        [switch]$Wildcard

    )

    If($Wildcard){
        Return [array]($Global:AllUIVariables | Where Name -like ($Prefix + "_*" + $Name + '*')).Value
    }
    Else{
        Return [array]($Global:AllUIVariables | Where Name -eq ($Prefix + "_" + $Name)).Value
    }
}
#endregion


Function Get-UIProperty{
    param(
        [Parameter(Mandatory = $true, Position=0)]
        [hashtable]$HashName,
        [Parameter(Mandatory = $true, Position=1)]
        [string]$Name,
        [switch]$Wildcard

    )
    If($Wildcard){
        Return ($HashName.GetEnumerator() | Where {$_.Name -like "*$name*"}).Value
    }
    Else{
        Return ($HashName.GetEnumerator() | Where Name -eq $Name).Value
    }
}
#endregion

Function Set-UIProperty{
    param(
        [Parameter(Mandatory = $true, Position=0)]
        [hashtable]$Runspace,
        [Parameter(Mandatory = $true, Position=1)]
        [string]$Name,
        [boolean]$Enable,
        [boolean]$Visible,
        [string]$Content,
        [string]$Text
    )
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $MyInvocation.MyCommand

        #build field object from name
        If ($PSCmdlet.ParameterSetName -eq "name")
        {
            $UIProperty = @()
            $UIProperty += Get-UIProperty -Name $Name -Wildcard
        }

        #set visable values
        switch($Visible)
        {
            $true  {$SetVisible='Visible'}
            $false {$SetVisible='Hidden'}
        }

    }
    Process{
        Foreach($item in $UIProperty)
        {
            #grab all the parameters
            $Parameters = $PSBoundParameters | Select -ExpandProperty Keys
            #loop each parameter
            Foreach($Parameter in $Parameters)
            {
                #Determine what each parameter and value is
                #if parameter is FieldObject of FieldName ignore setting it value
                Switch($Parameter){
                    'Enable'    {$SetValue=$true;$Property='IsEnabled';$value=$Enable}
                    'Visible'    {$SetValue=$true;$Property='Visibility';$value=$SetVisible}
                    'Content'    {$SetValue=$true;$Property='Content';$value=$Content}
                    'Text'    {$SetValue=$true;$Property='Text';$value=$Text}
                    'Source'    {$SetValue=$true;$Property='Source';$value=$Source}
                    default     {$SetValue=$false;}
                }

                If($SetValue){
                # Write-Host ('Parameter value is: {0}' -f $value)
                    If( $item.$Property -ne $value )
                    {
                        $item.$Property = $value
                        If($DebugPreference){Write-LogEntry ("Object [{0}] {1} property is changed to [{2}]" -f $item.Name,$Property,$Value) -Source ${CmdletName} -Severity 5}
                    }
                    Else
                    {
                        If($DebugPreference){Write-LogEntry ("Object [{0}] {1} property already set to [{2}]" -f $item.Name,$Property,$Value) -Source ${CmdletName} -Severity 5}
                    }
                }
            }#endloop each parameter
        }#endloop each field object
    }
}
#endregion

Function Search-UIDeviceList{
    Param(
        [Parameter(Mandatory = $true)]
        $ItemsList,
        [Parameter(Mandatory = $true)]
        [System.Windows.Controls.ListBox]$ListObject,
        [Parameter(Mandatory = $true)]
        [string]$Identifier,
        [Parameter(Mandatory = $true)]
        [string]$Filter
    )

    $ListObject.Items.Clear();

    foreach ($item in ($ItemsList | Where-Object { $_.$Identifier -like "*$Filter*" })){
        #only include what items exist in either in the folders collected initially or root locations
        #$ListObject.Tag = @($item.Name,$item.Path,$item.Guid)
        $ListObject.Items.Add($item.$Identifier) | Out-Null
    }
}
#endregion



#region FUNCTION: Action for Next & back button to change tab
function Switch-UITabItem {
    param(
        [Parameter(Mandatory = $true, Position=0)]
        [System.Windows.Controls.TabControl]$TabControlObject,
        [Parameter(Mandatory = $true, Position=1,ParameterSetName="index")]
        [int]$increment,
        [Parameter(Mandatory = $true, Position=1,ParameterSetName="name")]
        [string]$name
    )
    ## Get the name of this function
    [string]${CmdletName} = $MyInvocation.MyCommand

    If ($PSCmdlet.ParameterSetName -eq "index") {
        #Add index number to current tab
        $newtab = $TabControlObject.SelectedIndex + $increment
        #ensure number is not greater than tabs
        If ($newtab -ge $TabControlObject.items.count) {
            $newtab=0
        }
        elseif ($newtab -lt 0) {
            $newtab = $TabControlObject.SelectedIndex - 1
        }
        #Set new tab index
        $TabControlObject.SelectedIndex = $newtab

        $message = ("index [{0}]" -f $newtab)
    }
    ElseIf($PSCmdlet.ParameterSetName -eq "name"){
        $newtab = $TabControlObject.items | Where Header -eq $name
        $newtab.IsSelected = $true

        $message = ("name [{0}]" -f $newtab.Header)

    }
}
#endregion

Function Get-UIElement {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=1,ParameterSetName="name",ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [object[]]$Name
    )
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $MyInvocation.MyCommand

        $objects = @()
    }
    Process{
        Foreach($item in $Name){
            If($null -ne (Get-FormVariable $item -Wildcard)){
                $FieldObject = (Get-FormVariable $item -Wildcard)
                $Objects += $FieldObject
                If($DebugPreference){Write-LogEntry ("Found field object [{0}]" -f $FieldObject.Name) -Source ${CmdletName} -Severity 5}
            }
            Else{
                If($DebugPreference){Write-LogEntry ("Field object [{0}] does not exist" -f $FieldObject.Name) -Source ${CmdletName} -Severity 5}
            }
        }

    }
    End{
        Return $Objects
    }
}

#region FUNCTION: Set UI fields to either visible and state
Function Set-UIElement {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=1,ParameterSetName="object",ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [object[]]$FieldObject,
        [parameter(Mandatory=$true, Position=1,ParameterSetName="name",ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [string[]]$FieldName,
        [boolean]$Enable,
        [boolean]$Visible,
        [string]$Content,
        [string]$Text,
        $Source
    )
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $MyInvocation.MyCommand

        #build field object from name
        If ($PSCmdlet.ParameterSetName -eq "name")
        {
            $FieldObject = @()
            $FieldObject = Get-UIElement -Name $FieldName
        }

        #set visable values
        switch($Visible)
        {
            $true  {$SetVisible='Visible'}
            $false {$SetVisible='Hidden'}
        }

    }
    Process{
        Try{
            #loop each field object
            Foreach($item in $FieldObject)
            {
                #grab all the parameters
                $Parameters = $PSBoundParameters | Select -ExpandProperty Keys
                #loop each parameter
                Foreach($Parameter in $Parameters)
                {
                    #Determine what each parameter and value is
                    #if parameter is FieldObject of FieldName ignore setting it value
                    Switch($Parameter){
                        'Enable'    {$SetValue=$true;$Property='IsEnabled';$value=$Enable}
                        'Visible'    {$SetValue=$true;$Property='Visibility';$value=$SetVisible}
                        'Content'    {$SetValue=$true;$Property='Content';$value=$Content}
                        'Text'    {$SetValue=$true;$Property='Text';$value=$Text}
                        'Source'    {$SetValue=$true;$Property='Source';$value=$Source}
                        default     {$SetValue=$false;}
                    }

                    If($SetValue){
                       # Write-Host ('Parameter value is: {0}' -f $value)
                        If( $item.$Property -ne $value )
                        {
                            $item.$Property = $value
                            If($DebugPreference){Write-LogEntry ("Object [{0}] {1} property is changed to [{2}]" -f $item.Name,$Property,$Value) -Source ${CmdletName} -Severity 5}
                        }
                        Else
                        {
                            If($DebugPreference){Write-LogEntry ("Object [{0}] {1} property already set to [{2}]" -f $item.Name,$Property,$Value) -Source ${CmdletName} -Severity 5}
                        }
                    }
                }#endloop each parameter
            }#endloop each field object
        }
        Catch{
            Return $_.Exception.Message
        }
    }
}
#endregion


function Write-UIOutput {
	param(
        [Parameter(Mandatory=$false)]
        [hashtable]$Runspace,

        [parameter(Mandatory=$true)]
    	$UIObject,

    	[parameter(Mandatory=$true)]
    	[string]$Message,

    	[ValidateSet("Warning","Error","Info", "Start")]
    	[string]$Type,

        [switch]$Passthru
	)
    ## Get the name of this function
    [string]${CmdletName} = $MyInvocation.MyCommand

    Switch ($Type) {
        "Info"    { $fg = "Gray";$Severity=1}
        "Start"   { $fg = "Cyan";$Severity=1}
        "Warning" { $fg = "Yellow";$Severity=2}
        "Error"   {$fg = "Red";$Severity=3}
        default {$fg = 'White';$Severity=1}
    }
    $date = (Get-Date -Format G)

    If($PSBoundParameters.ContainsKey('Runspace'))
    {
        $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
            $UIObject.AppendText(("`n{0} :: {1}: {2}" -f $date.ToString(),$Type.ToUpper(),$Message))
            $UIObject.ScrollToEnd()
        })
    }
    Else{

        $UIObject.AppendText(("`n{0} :: {1}: {2}" -f $date.ToString(),$Type.ToUpper(),$Message))
        #[System.Windows.Forms.Application]::DoEvents()
        $UIObject.ScrollToEnd()
    }


    If($Passthru){
        Write-LogEntry $Message -Severity $Severity -Source ${CmdletName}
    }
}


Function Update-UIProgress{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Runspace,

        [Parameter(Mandatory=$true,ParameterSetName='Progress')]
        [int]$PercentComplete,

        [Parameter(Mandatory=$true,ParameterSetName='Scroll')]
        [switch]$Indeterminate,

        [Parameter(Mandatory=$False)]
        [String]$StatusMsg,

        [string]$Color = "Green"
    )

    if(!$Indeterminate){
        if(($PercentComplete -ge 0) -and ($PercentComplete -lt 100))
        {
	        $Runspace.ProgressBar.Dispatcher.Invoke("Normal",[action]{
			        $Runspace.ProgressBar.IsIndeterminate = $False
			        $Runspace.ProgressBar.Value = $PercentComplete
			        $Runspace.ProgressBar.Foreground = $Color
			        $Runspace.txtStatus.Text = $StatusMsg
                    $Runspace.txtStatus.Foreground = $Color
			        $Runspace.txtPercentage.Text = ('' + $PercentComplete + '%')
            })
        }
        else{
            $Runspace.ProgressBar.Dispatcher.Invoke("Normal",[action]{
			        $Runspace.ProgressBar.IsIndeterminate = $False
			        $Runspace.ProgressBar.Value = $PercentComplete
			        $Runspace.ProgressBar.Foreground = $Color
			        $Runspace.txtStatus.Text = $StatusMsg
                    $Runspace.txtStatus.Foreground = $Color
			        $Runspace.txtPercentage.Text = ('' + $PercentComplete + '%')
            })
        }
    }
    else{
        $Runspace.ProgressBar.Dispatcher.Invoke("Normal",[action]{
			$Runspace.ProgressBar.IsIndeterminate = $True
			$Runspace.ProgressBar.Foreground = $Color
			$Runspace.txtStatus.Text = $StatusMsg
            $Runspace.txtStatus.Foreground = $Color
            $Runspace.txtPercentage.Text = ' '
      })
    }
}

Function Get-UIElement {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0,ParameterSetName="name",ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [object[]]$Name
    )
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $MyInvocation.MyCommand

        $objects = @()
    }
    Process{
        Foreach($item in $Name){
            If($null -ne (Get-UIVariable $item -Wildcard)){
                $FieldObject = (Get-UIVariable $item -Wildcard)
                $Objects += $FieldObject
                If($DebugPreference){Write-LogEntry ("Found field object [{0}]" -f $FieldObject.Name) -Source ${CmdletName} -Severity 5 -Outhost}
            }
            Else{
                If($DebugPreference){Write-LogEntry ("Field object [{0}] does not exist" -f $FieldObject.Name) -Source ${CmdletName} -Severity 5 -Outhost}
            }
        }

    }
    End{
        Return $Objects
    }
}


Function Add-PopupContent{
    param(
        [Parameter(Mandatory = $true, Position=0)]
        $FlowDocumentObject,
        [Parameter(Mandatory = $true, Position=1)]
        [hashtable]$ContextHash
    )

    #TEST $Context = $ContextHash.GetEnumerator() | Sort Name
    Foreach($Context in $ContextHash.GetEnumerator() | Sort Name)
    {
        $i=0
        $NewParagraph = New-Object System.Windows.Documents.Paragraph
        $NewRunContext = New-Object System.Windows.Documents.Run
        #$NewRunContext.Name = "PopupTitle" + $i
        $NewRunContext.Text = $Context.Name
        $NewRunContext.FontFamily = "Segoe UI"
        $NewRunContext.FontWeight="Bold"
        $NewParagraph.AddChild($NewRunContext)
        $FlowDocumentObject.AddChild($NewParagraph)

        Foreach($Context in $Context.Value){
            $i++
            Try{
                $NewParagraph = New-Object System.Windows.Documents.Paragraph
                $NewRunContext = New-Object System.Windows.Documents.Run
                #$NewRunContext.Name = "PopupContext" + $i
                $NewRunContext.Text = $Context
                $NewRunContext.FontFamily = "Segoe UI"
                $NewParagraph.AddChild($NewRunContext)
                $FlowDocumentObject.AddChild($NewParagraph)
            }
            Catch{
                $_.exception.message
            }
        }
    }
}

Function Clear-PopupContent{
    param(
        [Parameter(Mandatory = $true, Position=0)]
        $FlowDocumentObject
    )
    $FlowDocumentObject.Blocks.Clear();
}

Function Add-UIList{
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [hashtable]$Runspace,
        [Parameter(Mandatory = $true, Position=1)]
        $ItemsList,
        [Parameter(Mandatory = $true, Position=2,ParameterSetName="listbox")]
        [System.Windows.Controls.ListBox]$ListObject,
        [Parameter(Mandatory = $true, Position=2,ParameterSetName="dropdown")]
        [System.Windows.Controls.ComboBox]$DropdownObject,
        [Parameter(Mandatory = $false, Position=3)]
        [string]$Identifier,
        [switch]$Passthru
    )
    ## Get the name of this function
    [string]${CmdletName} = $MyInvocation.MyCommand

    If ($PSCmdlet.ParameterSetName -eq "listbox") {
        $Object = $ListObject
        $ListObject.Items.Clear();
    }
    If ($PSCmdlet.ParameterSetName -eq "dropdown") {
        $Object = $DropdownObject
    }

    If (!($PSBoundParameters.ContainsKey("Identifier")) ) {
        $Identifier = $false
    }

    #TEST  $item = $ItemsList[0]
    #$ItemsList=$AbbrTypeList
    #$Object=$UIResponseData.cmbRuleAbbrType
    $i = 0
    foreach ($item in $ItemsList | Where { $null -ne $_ })
    {
        $i++
        If($PSBoundParameters.ContainsKey('Runspace')){
            If($Identifier){
                Update-UIProgress -Runspace $Runspace -PercentComplete ($i/$ItemsList.count * 100) -StatusMsg ("[{0} of {1}] :: Adding [{2}] to list..." -f $i,$ItemsList.count,$item.$Identifier)
                Write-UIOutput -Runspace $Runspace -UIObject $Runspace.Logging -Message ("Adding item to [{1}] {2}: {0}" -f $item.$Identifier,$Object.Name,$PSCmdlet.ParameterSetName) -Type Info

                $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                    $Object.Items.Add($item.$Identifier) | Out-Null
                })
            }
            Else{
                Update-UIProgress -Runspace $Runspace -PercentComplete ($i/$ItemsList.count * 100) -StatusMsg ("[{0} of {1}] :: Adding [{2}] to list..." -f $i,$ItemsList.count,$item)
                Write-UIOutput -Runspace $Runspace -UIObject $Runspace.Logging -Message ("Adding item to [{1}] {2}: {0}" -f $item,$Object.Name,$PSCmdlet.ParameterSetName) -Type Info
                $Runspace.Window.Dispatcher.Invoke("Normal",[action]{
                    $Object.Items.Add($item) | Out-Null
                })
            }
        }
        Else{
            #Check to see if properties exists
            If($Identifier){
                $Object.Items.Add($item.$Identifier) | Out-Null
            }
            Else{
                $Object.Items.Add($item) | Out-Null
            }
        }
    }

    If($PSBoundParameters.ContainsKey('Runspace')){
        Update-UIProgress -Runspace $Runspace -PercentComplete 100 -StatusMsg ("Added {0} items to list" -f $ItemsList.count) -Color Green
    }

    If($Passthru){
        return $Object.Items
    }
}
#endregion


Function Show-UIMenu{
    Param(
        $FormObject
    )
    ## Get the name of this function
    [string]${CmdletName} = $MyInvocation.MyCommand

    If($Global:HostOutput){Write-Host ("=============================================================") -ForegroundColor Green}
    #Slower method to present form for non modal (no popups)
    #$UI.ShowDialog() | Out-Null

    #Console control
    # Credits to - http://powershell.cz/2013/04/04/hide-and-show-console-window-from-gui/
    Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
    # Allow input to window for TextBoxes, etc
    [Void][System.Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($FormObject)

    #for ISE testing only: Add ESC key as a way to exit UI
    $code = {
        [System.Windows.Input.KeyEventArgs]$esc = $args[1]
        if ($esc.Key -eq 'ESC')
        {
            $FormObject.Close()
            [System.Windows.Forms.Application]::Exit()
            #this will kill ISE
            [Environment]::Exit($ExitCode);
        }
    }
    $null = $FormObject.add_KeyUp($code)


    $FormObject.Add_Closing({
        [System.Windows.Forms.Application]::Exit()
    })

    $async = $FormObject.Dispatcher.InvokeAsync({
        #make sure this display on top of every window
        $FormObject.Topmost = $true
        # Running this without $appContext & ::Run would actually cause a really poor response.
        $FormObject.Show() | Out-Null
        # This makes it pop up
        $FormObject.Activate() | Out-Null

        #$FormObject.window.ShowDialog()
    })
    $async.Wait() | Out-Null

    ## Force garbage collection to start form with slightly lower RAM usage.
    [System.GC]::Collect() | Out-Null
    [System.GC]::WaitForPendingFinalizers() | Out-Null

    # Create an application context for it to all run within.
    # This helps with responsiveness, especially when Exiting.
    $appContext = New-Object System.Windows.Forms.ApplicationContext
    [void][System.Windows.Forms.Application]::Run($appContext)

    #[Environment]::Exit($ExitCode);
}
#endregion

Function Open-AppSecretPrompt {

    Param(
        $Secret
    )
    #build runspace
    $syncHash = [hashtable]::Synchronized(@{})
    $ASPRunSpace =[runspacefactory]::CreateRunspace()
    $syncHash.Runspace = $ASPRunSpace
    $syncHash.AppSecret = $Secret
    $ASPRunSpace.ApartmentState = "STA"
    $ASPRunSpace.ThreadOptions = "ReuseThread"
    $ASPRunSpace.Open() | Out-Null
    $ASPRunSpace.SessionStateProxy.SetVariable("syncHash",$syncHash)
    $PowerShellCommand = [PowerShell]::Create().AddScript({

    [string]$xaml = @"
        <Window
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:AppSecret"
        Title="AppSecret"
        WindowStyle="None"
        WindowStartupLocation="CenterScreen"
        Height="200" Width="400"
        ResizeMode="NoResize"
        ShowInTaskbar="False">
    <Window.Resources>
            <Style TargetType="{x:Type Button}">
                <!-- This style is used for buttons, to remove the WPF default 'animated' mouse over effect -->
                <Setter Property="OverridesDefaultStyle" Value="True"/>
                <Setter Property="Foreground" Value="#FFEAEAEA"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="Button" >

                            <Border Name="border"
                                        BorderThickness="1"
                                        Padding="4,2"
                                        BorderBrush="#FFEAEAEA"
                                        CornerRadius="2"
                                        Background="{TemplateBinding Background}">
                                <ContentPresenter HorizontalAlignment="Center"
                                                    VerticalAlignment="Center"
                                                    TextBlock.FontSize="10px"
                                                    TextBlock.TextAlignment="Center"
                                                    />
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="border" Property="BorderBrush" Value="#FF919191" />
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Style>
        </Window.Resources>
        <Grid Background="#313130">
            <Label x:Name="lblPassword" Content="Type in the App Secret:" HorizontalAlignment="Left" Margin="32,47,0,0" VerticalAlignment="Top" Foreground="White" RenderTransformOrigin="0.557,-0.246" Width="147"/>
            <PasswordBox x:Name="pwdBoxPassword" Width="332" Height="24" Margin="37,78,31,98"/>
            <Label x:Name="lblMsg" HorizontalAlignment="Left" Margin="37,102,0,0" VerticalAlignment="Top" Width="332" Foreground="Red"/>

            <Button x:Name="btnSubmit" Content="Submit" HorizontalAlignment="Left" Margin="286,140,0,0" VerticalAlignment="Top" Width="95" Height="50" Background="Black" Foreground="White"/>
            <Button x:Name="btnCancel" Content="Cancel" HorizontalAlignment="Left" Margin="32,140,0,0" VerticalAlignment="Top" Width="95" Height="50" Background="Black" Foreground="White"/>

        </Grid>
    </Window>
"@

        #Load assembies to display UI
        [void][System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework')

        [xml]$xaml = $xaml -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace '^<Win.*', '<Window'
        $reader=(New-Object System.Xml.XmlNodeReader $xaml)
        $syncHash.Window=[Windows.Markup.XamlReader]::Load( $reader )
        #===========================================================================
        # Store Form Objects In PowerShell
        #===========================================================================
        $xaml.SelectNodes("//*[@Name]") | %{ $syncHash."$($_.Name)" = $syncHash.Window.FindName($_.Name)}

        # INNER  FUNCTIONS
        #Closes UI objects and exits (within runspace)
        Function Close-AppSecretPrompt
        {
            if ($syncHash.hadCritError) { Write-Host -Message "Background thread had a critical error" -ForegroundColor red }
            #if runspace has not errored Dispose the UI
            if (!($syncHash.isClosing)) { $syncHash.Window.Close() | Out-Null }
        }

        If($syncHash.AppSecret){
            $syncHash.pwdBoxPassword.Password = $syncHash.AppSecret
        }

        $syncHash.btnSubmit.Add_Click({
            If([string]::IsNullOrEmpty($syncHash.pwdBoxPassword.Password) ){
                $syncHash.lblMsg.content = "Invalid Secret, please try again or cancel"
            }Else{
                $syncHash.Secret = $syncHash.pwdBoxPassword.Password
                Close-AppSecretPrompt
            }
        })

        $syncHash.btnCancel.Add_Click({
            Close-AppSecretPrompt
        })

        #Allow UI to be dragged around screen
        $syncHash.Window.Add_MouseLeftButtonDown( {
            $syncHash.Window.DragMove()
        })

        #Add smooth closing for Window
        $syncHash.Window.Add_Loaded({ $syncHash.isLoaded = $True })
        $syncHash.Window.Add_Closing({ $syncHash.isClosing = $True; Close-AppSecretPrompt })
        $syncHash.Window.Add_Closed({ $syncHash.isClosed = $True })

        #make sure this display on top of every window
        $syncHash.Window.Topmost = $true

        $syncHash.window.ShowDialog()
        $syncHash.Error = $Error
    }) # end scriptblock

    #collect data from runspace
    $Data = $syncHash

    #invoke scriptblock in runspace
    $PowerShellCommand.Runspace = $ASPRunSpace
    $AsyncHandle = $PowerShellCommand.BeginInvoke()

    #wait until runspace is completed before ending
    do {
        Start-sleep -m 100 }
    while (!$AsyncHandle.IsCompleted)
    #end invoked process
    $null = $PowerShellCommand.EndInvoke($AsyncHandle)

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

}#end runspace


Function Show-UIAssignmentsWindow {
    [CmdletBinding(DefaultParameterSetName='PreLoadId')]
    Param(
        [Parameter(Mandatory=$false,ParameterSetName='PreLoadId')]
        $DeviceName,

        [Parameter(Mandatory=$false,ParameterSetName='PreLoadId')]
        $UPN,

        [Parameter(Mandatory=$false,ParameterSetName='PreloadData')]
        $DeviceData,

        [Parameter(Mandatory=$false,ParameterSetName='PreloadData')]
        $UserData,

        [Parameter(Mandatory=$false,ParameterSetName='PreloadData')]
        $DeviceAssignments,

        [Parameter(Mandatory=$false,ParameterSetName='PreloadData')]
        $UserAssignments,

        [Parameter(Mandatory=$false,ParameterSetName='PreloadData')]
        [Parameter(Mandatory=$true,ParameterSetName='PreLoadId')]
        [string[]]$SupportScripts,

        $ParentSyncHash,

        [Parameter(Mandatory=$false,ParameterSetName='PreloadData')]
        [Parameter(Mandatory=$true,ParameterSetName='PreLoadId')]
        $AuthToken,

        [Parameter(Mandatory=$false)]
        [switch]$IncludeInherited,

        [Parameter(Mandatory=$false)]
        [switch]$LoadOnStartup
    )

    #build runspace
    $syncHash = [hashtable]::Synchronized(@{})
    $ASPRunSpace = [runspacefactory]::CreateRunspace()
    $syncHash.Runspace = $ASPRunSpace
    $syncHash.PreloadType = $PSCmdlet.ParameterSetName
    $syncHash.Inherited = $IncludeInherited
    $syncHash.LoadOnStartup = $LoadOnStartup
    $syncHash.DeviceName = $DeviceName
    $syncHash.DeviceData = $DeviceData
    $syncHash.DeviceAssignments = $DeviceAssignments
    $syncHash.UPN = $UPN
    $syncHash.UserData = $UserData
    $syncHash.UserAssignments = $UserAssignments
    $syncHash.Scripts = $SupportScripts
    $syncHash.AuthToken = $AuthToken
    $syncHash.AssignmentData = @()
    $ASPRunSpace.ApartmentState = "STA"
    $ASPRunSpace.ThreadOptions = "ReuseThread"
    $ASPRunSpace.Open() | Out-Null
    $ASPRunSpace.SessionStateProxy.SetVariable("syncHash",$syncHash)
    $ASPRunSpace.SessionStateProxy.SetVariable("ParentSyncHash",$ParentSyncHash)
    $PowerShellCommand = [PowerShell]::Create().AddScript({

    [string]$xaml = @"
    <Window
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        mc:Ignorable="d"
        Title="DeviceAssignments" Height="640" Width="1024"
        WindowStyle="None"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        BorderBrush="Black"
        BorderThickness="2">
    <Grid>
        <Label Content="Device" HorizontalAlignment="Left" VerticalAlignment="Top" Width="48" HorizontalContentAlignment="Right" Margin="15,14,0,0"/>
        <TextBox x:Name="txtDeviceName" HorizontalAlignment="Left" Height="22" VerticalAlignment="Top" Width="227" Margin="63,16,0,0"/>
        <Label Content="User" HorizontalAlignment="Left" VerticalAlignment="Top" Width="48" HorizontalContentAlignment="Right" Margin="15,42,0,0"/>
        <TextBox x:Name="txtAssignedUPN" HorizontalAlignment="Left" Height="22" VerticalAlignment="Top" Width="227" Margin="63,45,0,0"/>

        <Label Content="Search" HorizontalAlignment="Left" VerticalAlignment="Top" Width="48" HorizontalContentAlignment="Right" Margin="427,14,0,0"/>
        <TextBox x:Name="txtAssignmentSearch" HorizontalAlignment="Left" Height="22" VerticalAlignment="Top" Width="497" Margin="475,16,0,0"/>
        <Button x:Name="btnAssignments" Content="Get Assignments" HorizontalAlignment="Left" VerticalAlignment="Top" VerticalContentAlignment="Center"  Width="97" Height="51" Margin="295,17,0,0" />
        <Label Content="Column Filter" HorizontalAlignment="Left" VerticalAlignment="Top" Width="80" HorizontalContentAlignment="Right" Margin="395,44,0,0"/>
        <Label x:Name="lblFilterColumn" FontSize="8" HorizontalAlignment="Left" VerticalAlignment="Top" Width="145" HorizontalContentAlignment="Right" VerticalContentAlignment="Top" Margin="475,71,0,0" IsEnabled="False"/>
        <Label x:Name="lblFilterOperator" FontSize="8" HorizontalAlignment="Left" VerticalAlignment="Top" Width="70" HorizontalContentAlignment="Center" VerticalContentAlignment="Top" Margin="620,71,0,0" IsEnabled="False"/>
        <Label x:Name="lblFilterValue" FontSize="8" HorizontalAlignment="Left" VerticalAlignment="Top" Width="315" HorizontalContentAlignment="Left" VerticalContentAlignment="Top" Margin="690,71,0,0" IsEnabled="False"/>
        <CheckBox x:Name="chkIncludePolicySets" Width="324" Margin="20,77,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" Content="Include inheritance from Policy Sets" />

        <ComboBox x:Name="cmbFilterColumns" Width="140" Margin="475,46,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" />
        <ComboBox x:Name="cmbFilterOperators" Width="60" Margin="620,46,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" />
        <ComboBox x:Name="cmbFilterValues" Width="287" Margin="685,46,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" />
        <Button x:Name="btnReset" Content="X" VerticalContentAlignment="Center" HorizontalContentAlignment="Center" HorizontalAlignment="Left" VerticalAlignment="Top"  Width="28" Height="22" Margin="977,46,0,0" />

        <ListView x:Name="lstDeviceAssignments" HorizontalAlignment="Center" Height="437" Margin="0,97,0,0"  VerticalAlignment="Top" Width="990">
            <ListView.View>
                <GridView>
                    <GridViewColumn Header="Assignment Name" DisplayMemberBinding="{Binding Name}" />
                    <GridViewColumn Header="Assignment Type" DisplayMemberBinding="{Binding Type}" />
                    <GridViewColumn Header="Mode" DisplayMemberBinding="{Binding Mode}" />
                    <GridViewColumn Header="Target" DisplayMemberBinding="{Binding Target}" />
                    <GridViewColumn Header="Azure AD Group" DisplayMemberBinding="{Binding Group}" />
                    <GridViewColumn Header="GroupType" DisplayMemberBinding="{Binding GroupType}" />
                </GridView>
            </ListView.View>
        </ListView>
        <Label Content="Total Assignments:" HorizontalAlignment="Left" VerticalAlignment="Top" Width="126" HorizontalContentAlignment="Right" Margin="19,538,0,0"/>
        <TextBox x:Name="txtTotalAssignments" Text="0" HorizontalAlignment="Left" Height="22" VerticalAlignment="Top" Width="33" IsEnabled="False" Margin="149,543,0,0" BorderThickness="0"/>
        <Label Content="Device Assignments:" HorizontalAlignment="Left" VerticalAlignment="Top" Width="126" HorizontalContentAlignment="Right" Margin="19,560,0,0"/>
        <TextBox x:Name="txtDeviceAssignments" Text="0" HorizontalAlignment="Left" Height="22" VerticalAlignment="Top" Width="33" IsEnabled="False" Margin="149,567,0,0" BorderThickness="0"/>
        <Label Content="User Assignments:" HorizontalAlignment="Left" VerticalAlignment="Top" Width="126" HorizontalContentAlignment="Right" Margin="19,584,0,0"/>
        <TextBox x:Name="txtUserAssignments" Text="0" HorizontalAlignment="Left" Height="22" VerticalAlignment="Top" Width="33" IsEnabled="False" Margin="149,591,0,0" BorderThickness="0"/>

        <Button x:Name="btnExport" Content="Export" HorizontalAlignment="Left" VerticalAlignment="Top"  Width="124" Height="33"  FontSize="16" Margin="752,546,0,0" />
        <Button x:Name="btnExit" Content="Exit" HorizontalAlignment="Left" VerticalAlignment="Top"  Width="124" Height="33" FontSize="16" Margin="881,546,0,0"/>
        <ProgressBar x:Name="ProgressBar" Width="644" Height="7" Margin="0,597,0,0" HorizontalAlignment="Center" VerticalAlignment="Top" Background="White" Foreground="LightGreen" />
        <TextBox x:Name="txtStatus" HorizontalAlignment="Left" Height="49" VerticalAlignment="Top" Width="560" IsEnabled="False" Margin="187,543,0,0" BorderThickness="0" TextWrapping="Wrap"/>
        <TextBox x:Name="txtPercentage" HorizontalAlignment="Left" Height="23" VerticalAlignment="Top" Width="37" IsEnabled="False" Margin="837,591,0,0" BorderThickness="0"/>
    </Grid>
</Window>
"@

        #Load assembies to display UI
        [void][System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework')

        [xml]$xaml = $xaml -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace '^<Win.*', '<Window'
        $reader=(New-Object System.Xml.XmlNodeReader $xaml)
        $syncHash.Window=[Windows.Markup.XamlReader]::Load( $reader )
        #===========================================================================
        # Store Form Objects In PowerShell
        #===========================================================================
        $xaml.SelectNodes("//*[@Name]") | %{ $syncHash."$($_.Name)" = $syncHash.Window.FindName($_.Name)}

        Import-Module IDMCmdlets

        #load scripts
        Foreach($Script in $syncHash.Scripts){
            . $Script
        }

        #add elements that you want to update often
        #the value must also be added to top of function as synchash property
        #then it can be called by the timer to update
        $updateAssignments = {
            $syncHash.lstDeviceAssignments.Items.Refresh();
        }


        # INNER  FUNCTIONS
        #Closes UI objects and exits (within runspace)
        Function Close-UIAssignmentsWindow
        {
            if ($syncHash.hadCritError) { Write-Host -Message "Background thread had a critical error" -ForegroundColor red }
            #if runspace has not errored Dispose the UI
            if (!($syncHash.isClosing)) { $syncHash.Window.Close() | Out-Null }
        }

        # UI INITIAL LOAD
        #=================
        #Disable column extra filter
        $syncHash.cmbFilterOperators.IsEnabled = $false
        $syncHash.cmbFilterValues.IsEnabled = $false
        $syncHash.btnReset.IsEnabled = $false

        @("Name","Type","Mode","Target","Group","GroupType","Platform") | %{$syncHash.cmbFilterColumns.Items.Add($_) | Out-Null}
        #$syncHash.cmbFilterColumns.SelectedItem = "Name"

        @("include","exclude") | %{$syncHash.cmbFilterOperators.Items.Add($_) | Out-Null}

        If($syncHash.PreloadType -eq 'PreloadData')
        {
            #populate text fields
            $syncHash.txtDeviceName.Text = $syncHash.DeviceData.DeviceName
            $syncHash.txtAssignedUPN.Text = $syncHash.UserData.userPrincipalName

            #check box on start up if inherited is set
            $syncHash.chkIncludePolicySets.IsChecked = $syncHash.Inherited
            #Combine data into one
            If($syncHash.DeviceAssignments.count -gt 0){$syncHash.AssignmentData += $syncHash.DeviceAssignments}
            If($syncHash.UserAssignments.count -gt 0){$syncHash.AssignmentData += $syncHash.UserAssignments}

            If($syncHash.AssignmentData.count -gt 0){
                $syncHash.ProgressBar.Visibility = 'Hidden'
                $syncHash.txtPercentage.Visibility = 'Hidden'
                $syncHash.txtStatus.Visibility = 'Hidden'
                $syncHash.btnAssignments.Visibility = 'Hidden'
            }

            If($syncHash.Inherited -eq $true){
                #Set global list so other elements can use it
                $Global:AssignmentList = $syncHash.AssignmentData
                $syncHash.txtTotalAssignments.Text = $syncHash.AssignmentData.Count
                $syncHash.txtDeviceAssignments.Text = $syncHash.DeviceAssignments.Count
                $syncHash.txtUserAssignments.Text = $syncHash.UserAssignments.Count
            }
            Else{
                #Set global list so other elements can use it
                $Global:AssignmentList = ($syncHash.AssignmentData | Where Mode -NotLike '*Inherited*')
                $syncHash.txtTotalAssignments.Text =  $Global:AssignmentList.Count
                $syncHash.txtDeviceAssignments.Text = ($syncHash.DeviceAssignments | Where Mode -NotLike '*Inherited*').Count
                $syncHash.txtUserAssignments.Text = ($syncHash.UserAssignments | Where Mode -NotLike '*Inherited*').Count
            }

            #Add global list to UI
            $syncHash.lstDeviceAssignments.ItemsSource = $Global:AssignmentList
        }
        Else{
            $syncHash.ProgressBar.Visibility = 'Visible'
            $syncHash.txtPercentage.Visibility = 'Visible'
            $syncHash.txtStatus.Visibility = 'Visible'
            $syncHash.btnAssignments.Visibility = 'Visible'

            $syncHash.txtDeviceName.Text = $syncHash.DeviceName
            $syncHash.txtAssignedUPN.Text = $syncHash.UPN
        }

        # UI HANDLERS
        #===================
        #RUN EVENTS ON CHECK CHANGE
        [System.Windows.RoutedEventHandler]$Script:CheckedEventHandler = {
            #reset everything
            $syncHash.lstDeviceAssignments.Items.Clear()
            $syncHash.txtAssignmentSearch.text = $null
            $syncHash.cmbFilterColumns.SelectedItem = $null
            $syncHash.cmbFilterOperators.SelectedItem = $null
            $syncHash.cmbFilterValues.SelectedItem = $null
            $syncHash.lblFilterColumn.Content = $null
            $syncHash.lblFilterOperator.Content = $null
            $syncHash.lblFilterValue.Content = $null
            #Disable column extra filter
            $syncHash.cmbFilterOperators.IsEnabled = $false
            $syncHash.cmbFilterValues.IsEnabled = $false
            $syncHash.btnReset.IsEnabled = $false

            #Update count
            $syncHash.txtTotalAssignments.Text = $syncHash.AssignmentData.Count
            $syncHash.txtDeviceAssignments.Text = $syncHash.DeviceAssignments.Count
            $syncHash.txtUserAssignments.Text = $syncHash.UserAssignments.Count
            #Set global list so other elements can use it
            $Global:AssignmentList = $syncHash.AssignmentData
            $syncHash.lstDeviceAssignments.ItemsSource = $Global:AssignmentList
        }
        #UPDATE LIST WITH ALL ITEMS
        $syncHash.chkIncludePolicySets.AddHandler([System.Windows.Controls.CheckBox]::CheckedEvent, $CheckedEventHandler)

        [System.Windows.RoutedEventHandler]$Script:UnCheckedEventHandler = {
            #reset everything
            $syncHash.lstDeviceAssignments.Items.Clear()
            $syncHash.txtAssignmentSearch.text = $null
            $syncHash.cmbFilterColumns.SelectedItem = $null
            $syncHash.cmbFilterOperators.SelectedItem = $null
            $syncHash.cmbFilterValues.SelectedItem = $null
            $syncHash.lblFilterColumn.Content = $null
            $syncHash.lblFilterOperator.Content = $null
            $syncHash.lblFilterValue.Content = $null
            #Disable column extra filter
            $syncHash.cmbFilterOperators.IsEnabled = $false
            $syncHash.cmbFilterValues.IsEnabled = $false
            $syncHash.btnReset.IsEnabled = $false

            #Update count
            $syncHash.txtTotalAssignments.Text =  $Global:AssignmentList.Count
            $syncHash.txtDeviceAssignments.Text = ($syncHash.DeviceAssignments | Where Mode -NotLike '*Inherited*').Count
            $syncHash.txtUserAssignments.Text = ($syncHash.UserAssignments | Where Mode -NotLike '*Inherited*').Count
            #Set global list so other elements can use it
            $Global:AssignmentList = ($syncHash.AssignmentData | Where Mode -NotLike '*Inherited*')
            $syncHash.lstDeviceAssignments.ItemsSource = $Global:AssignmentList
        }

        #UPDATE LIST WITH ALL ITEMS EXCEPT INHERITED
        $syncHash.chkIncludePolicySets.AddHandler([System.Windows.Controls.CheckBox]::UncheckedEvent, $UnCheckedEventHandler)

        #ACTIVATE LIVE SEARCH
        $syncHash.txtAssignmentSearch.AddHandler(
            [System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
            [System.Windows.RoutedEventHandler]{
                If($syncHash.cmbFilterColumns.SelectedItem){
                    $syncHash.lstDeviceAssignments.ItemsSource = ($syncHash.AssignmentData | Where {$_.($syncHash.cmbFilterColumns.SelectedItem) -like "*$($syncHash.txtAssignmentSearch.text)*"})
                }
                Else{
                    $syncHash.lstDeviceAssignments.ItemsSource = ($syncHash.AssignmentData | Where {$_.Name -like "*$($syncHash.txtAssignmentSearch.text)*"})
                }
                $syncHash.btnReset.IsEnabled = $true
            }
        )

        $syncHash.txtDeviceName.AddHandler(
            [System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
            [System.Windows.RoutedEventHandler]{
                $syncHash.btnAssignments.IsEnabled = $true
                $syncHash.btnAssignments.Visibility = 'Visible'
            }
        )

        $syncHash.txtAssignedUPN.AddHandler(
            [System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
            [System.Windows.RoutedEventHandler]{
                $syncHash.btnAssignments.IsEnabled = $true
                $syncHash.btnAssignments.Visibility = 'Visible'
                $syncHash.ProgressBar.Visibility = 'Visible'
                $syncHash.txtPercentage.Visibility = 'Visible'
                $syncHash.txtStatus.Visibility = 'Visible'
                $syncHash.btnAssignments.Visibility = 'Visible'
            }
        )


        $syncHash.cmbFilterColumns.Add_SelectionChanged({
            #sort it
            $syncHash.lstDeviceAssignments.ItemsSource = ($syncHash.AssignmentData | Sort $syncHash.cmbFilterColumns.SelectedItem)
            #first sort data by selected item
            #$syncHash.lstDeviceAssignments.ItemsSource = ($syncHash.AssignmentData | Sort $syncHash.cmbFilterColumns.SelectedItem)
            #build values for next item
            $syncHash.cmbFilterValues.Items.Clear()
            ($syncHash.lstDeviceAssignments.ItemsSource).($syncHash.cmbFilterColumns.SelectedItem) | Select -Unique | %{$syncHash.cmbFilterValues.Items.Add($_) | Out-Null}
            #enable extra filters
            $syncHash.cmbFilterOperators.IsEnabled = $true
            $syncHash.cmbFilterValues.IsEnabled = $true
            $syncHash.btnReset.IsEnabled = $true
            #set default
            $syncHash.cmbFilterOperators.SelectedItem = "include"
            #set label
            $syncHash.lblFilterColumn.Content = ("Find item where " + ($syncHash.cmbFilterColumns.SelectedItem).ToUpper())
        })

        $syncHash.cmbFilterOperators.Add_SelectionChanged({
            switch($syncHash.cmbFilterOperators.SelectedItem){
                "include" {$syncHash.lblFilterOperator.Content = 'is equal to'}
                "exclude" {$syncHash.lblFilterOperator.Content = 'does not equal'}
            }
            $syncHash.cmbFilterValues.SelectedItem = $null
        })

        $syncHash.cmbFilterValues.Add_SelectionChanged({
            #filter it based on operator
            switch($syncHash.cmbFilterOperators.SelectedItem){
                "include" {$syncHash.lstDeviceAssignments.ItemsSource = ($syncHash.AssignmentData | Where {$_.($syncHash.cmbFilterColumns.SelectedItem) -eq $syncHash.cmbFilterValues.SelectedItem})}
                "exclude" {$syncHash.lstDeviceAssignments.ItemsSource = ($syncHash.AssignmentData | Where {$_.($syncHash.cmbFilterColumns.SelectedItem) -ne $syncHash.cmbFilterValues.SelectedItem})}
                default {$syncHash.lstDeviceAssignments.ItemsSource = ($syncHash.AssignmentData | Where {$_.($syncHash.cmbFilterColumns.SelectedItem) -eq $syncHash.cmbFilterValues.SelectedItem})}
            }
            #$syncHash.lstDeviceAssignments.ItemsSource = ($syncHash.AssignmentData | Where {$_.($syncHash.cmbFilterColumns.SelectedItem) -eq $syncHash.cmbFilterValues.SelectedItem})
            $syncHash.lblFilterValue.Content = $syncHash.cmbFilterValues.SelectedItem.ToUpper()
        })

        $syncHash.btnReset.Add_Click({
            $syncHash.txtAssignmentSearch.text = $null
            $syncHash.cmbFilterColumns.SelectedItem = $null
            $syncHash.cmbFilterOperators.SelectedItem = $null
            $syncHash.cmbFilterValues.SelectedItem = $null
            $syncHash.lblFilterColumn.Content = $null
            $syncHash.lblFilterOperator.Content = $null
            $syncHash.lblFilterValue.Content = $null
            #Disable column extra filter
            $syncHash.cmbFilterOperators.IsEnabled = $false
            $syncHash.cmbFilterValues.IsEnabled = $false

            $syncHash.lstDeviceAssignments.ItemsSource = $syncHash.AssignmentData
            #update Prog
            Update-UIProgress -Runspace $syncHash -PercentComplete 100 -Color Green
            #disable button
            $syncHash.btnReset.IsEnabled = $false
        })

        $syncHash.btnAssignments.Add_Click({
            # disable this button to prevent multiple clicks.
            $this.IsEnabled = $false
            $syncHash.lstDeviceAssignments.ItemsSource.Clear()
            Update-UIProgress -Runspace $syncHash -StatusMsg ("Please wait while loading device and user assignment data, this can take a while...") -Indeterminate

            $syncHash.Window.Dispatcher.Invoke("Normal",[action]{

                #$syncHash.DeviceData = Get-IDMDevice -Filter $syncHash.txtDeviceName.Text -AuthToken $syncHash.AuthToken -Expand
                If($syncHash.DeviceData = Get-IDMDevice -Filter $syncHash.txtDeviceName.Text -AuthToken $syncHash.AuthToken -Expand)
                {
                    If([string]::IsNullOrEmpty($syncHash.txtAssignedUPN.Text)){
                        $syncHash.txtAssignedUPN.Text = $syncHash.DeviceData.userPrincipalName
                    }
                    $syncHash.UserData = Get-IDMDeviceAADUser -UPN $syncHash.txtAssignedUPN.Text

                    $Global:AssignmentList = Get-IDMIntuneAssignments `
                                                        -Platform $syncHash.DeviceData.OperatingSystem `
                                                        -TargetSet @{devices=$syncHash.DeviceData.azureADObjectId;users=$syncHash.UserData.id} `
                                                        -AuthToken $syncHash.AuthToken -IncludePolicySetInherits

                    #Set global list so other elements can use it
                    $syncHash.AssignmentData = $Global:AssignmentList
                    $syncHash.DeviceAssignments = ($Global:AssignmentList | Where Target -eq 'Devices')
                    $syncHash.UserAssignments = ($Global:AssignmentList | Where Target -eq 'Users')

                    #Update count
                    $syncHash.txtTotalAssignments.Text = $syncHash.AssignmentData.Count
                    $syncHash.txtDeviceAssignments.Text = $syncHash.DeviceAssignments.Count
                    $syncHash.txtUserAssignments.Text = $syncHash.UserAssignments.Count

                    #update list view
                    $syncHash.lstDeviceAssignments.ItemsSource = $syncHash.AssignmentData
                }

            })

            If($syncHash.DeviceData){
                #update Prog
                Update-UIProgress -Runspace $syncHash -PercentComplete 100 -StatusMsg ('Found {0} assignments for user [{1}] and device [{2}]' -f $syncHash.AssignmentData.count,$syncHash.txtAssignedUPN.Text,$syncHash.txtDeviceName.Text) -Color Green
            }
            Else{
                Update-UIProgress -Runspace $syncHash -PercentComplete 100 -StatusMsg ('Unable to find device named [{1}]. Type in new name and try again.' -f $syncHash.txtDeviceName.Text) -Color Red
                $Global:AssignmentList = $null
                $syncHash.AssignmentData = $Null
                $syncHash.txtDeviceName.Text = $Null
                $syncHash.txtAssignedUPN.Text = $Null
            }
        })

        $syncHash.btnExport.Add_Click({
            # disable this button to prevent multiple export.
            $this.IsEnabled = $false
            $UserDesktopPath = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" | Select -ExpandProperty Desktop
            If(Test-Path $UserDesktopPath){
                $ExportFilePath = "$UserDesktopPath\$($syncHash.txtDeviceName.Text)_$($syncHash.txtAssignedUPN.Text.replace('@','_'))_$(Get-Date -Format yyyyMMdd).csv"
            }Else{
                $ExportFilePath = "$env:UserProfile\Desktop\$($syncHash.txtDeviceName.Text)_$($syncHash.txtAssignedUPN.Text.replace('@','_'))_$(Get-Date -Format yyyyMMdd).csv"
            }
            $syncHash.AssignmentData | Export-Csv -NoTypeInformation $ExportFilePath -Force
            $syncHash.txtStatus.text = ('Exported CSV file to {0}' -f $ExportFilePath)
        })

        $syncHash.btnExit.Add_Click({
            Close-UIAssignmentsWindow
        })

        #Allow UI to be dragged around screen
        $syncHash.Window.Add_MouseLeftButtonDown( {
            $syncHash.Window.DragMove()
        })

        If($syncHash.LoadOnStartup){
            $syncHash.btnAssignments.IsEnabled = $false

            $Global:AssignmentList = Get-IDMIntuneAssignments `
                                                    -Platform $syncHash.DeviceData.OperatingSystem `
                                                    -TargetSet @{devices=$syncHash.DeviceData.azureADObjectId;users=$syncHash.UserData.id} `
                                                    -AuthToken $syncHash.AuthToken -IncludePolicySetInherits

            #Set global list so other elements can use it
            $syncHash.AssignmentData = $Global:AssignmentList
            $syncHash.DeviceAssignments = ($Global:AssignmentList | Where Target -eq 'Devices')
            $syncHash.UserAssignments = ($Global:AssignmentList | Where Target -eq 'Users')

            #Update count
            $syncHash.txtTotalAssignments.Text = $syncHash.AssignmentData.Count
            $syncHash.txtDeviceAssignments.Text = $syncHash.DeviceAssignments.Count
            $syncHash.txtUserAssignments.Text = $syncHash.UserAssignments.Count

            #update list view
            $syncHash.lstDeviceAssignments.ItemsSource = $syncHash.AssignmentData

            Update-UIProgress -Runspace $syncHash -PercentComplete 100 -StatusMsg ('Found {0} assignments for user [{1}] and device [{2}]' -f $syncHash.AssignmentData.count,$syncHash.txtAssignedUPN.Text,$syncHash.txtDeviceName.Text) -Color Green
        }

        # Before the UI is displayed
        # Create a timer dispatcher to watch for value change externally on regular interval
        # update those values when found using scriptblock ($updateblock)
        $syncHash.Window.Add_SourceInitialized({
            ## create a timer
            $timer = new-object System.Windows.Threading.DispatcherTimer
            ## set to fire 4 times every second
            $timer.Interval = [TimeSpan]"0:0:0.01"
            ## invoke the $updateBlock after each fire
            $timer.Add_Tick( $updateAssignments )
            ## start the timer
            $timer.Start()

            if( -Not($timer.IsEnabled) ) {
               $syncHash.Error = "Timer didn't start"
            }
        })

        #Add smooth closing for Window
        $syncHash.Window.Add_Loaded({ $syncHash.isLoaded = $True })
        $syncHash.Window.Add_Closing({ $syncHash.isClosing = $True; Close-UIAssignmentsWindow })
        $syncHash.Window.Add_Closed({ $syncHash.isClosed = $True })

        #make sure this display on top of every window
        $syncHash.Window.Topmost = $true

        $syncHash.window.ShowDialog()
        $syncHash.Error = $Error
    }) # end scriptblock

    #collect data from runspace
    $Data = $syncHash

    #invoke scriptblock in runspace
    $PowerShellCommand.Runspace = $ASPRunSpace
    $AsyncHandle = $PowerShellCommand.BeginInvoke()


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

}#end runspace



<#
TESTS
.\IntuneDeviceManagerUI.ps1
. .\Functions\UIControls.ps1
. .\Functions\Runspace.ps1
$Global:AssignmentUI = Show-UIAssignmentsWindow `
    -DeviceData $syncHash.Data.SelectedDevice `
    -DeviceAssignments $syncHash.Data.DeviceAssignments `
    -UserData $syncHash.Data.AssignedUser `
    -UserAssignments $syncHash.Data.UserAssignments `
    -AuthToken $syncHash.Data.AuthToken -LoadOnStartup

$Global:AssignmentUI = Show-UIAssignmentsWindow -SupportScripts "$($syncHash.FunctionPath)\Intune.ps1" -DeviceData $syncHash.Data.SelectedDevice -UserData $syncHash.Data.AssignedUser -AuthToken $syncHash.Data.AuthToken
$Global:AssignmentUI = Show-UIAssignmentsWindow -SupportScripts "$($syncHash.FunctionPath)\Intune.ps1" -AuthToken $syncHash.Data.AuthToken
$Global:AssignmentUI = Show-UIAssignmentsWindow -SupportScripts "$($syncHash.FunctionPath)\Intune.ps1" -UPN "leeg@DTOLAB.LTD" -AuthToken $syncHash.Data.AuthToken
Show-UIAssignmentsWindow -DeviceData $syncHash.Data.SelectedDevice -UserData $syncHash.Data.AssignedUser -SupportScripts @(".\Functions\UIControls.ps1",".\Functions\Runspace.ps1") -AuthToken $syncHash.Data.AuthToken
#>
