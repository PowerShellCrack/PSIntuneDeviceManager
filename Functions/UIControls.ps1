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
    $UIObject.AppendText(("`n{0} :: {1}: {2}" -f $date.ToString(),$Type.ToUpper(),$Message))
    #[System.Windows.Forms.Application]::DoEvents()
    $UIObject.ScrollToEnd()

    Write-LogEntry $Message -Severity $Severity -Source ${CmdletName}

    If($Passthru){

    }
}

Function Update-IDMProgress{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='Progress')]
        [Parameter(Mandatory=$true,ParameterSetName='Scroll')]
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
                    $syncHash.txtStatus.Foreground = $Color
			        $Runspace.txtPercentage.Text = ('' + $PercentComplete + '%')
            })
        }
        else{
            $Runspace.ProgressBar.Dispatcher.Invoke("Normal",[action]{
			        $Runspace.ProgressBar.IsIndeterminate = $False
			        $Runspace.ProgressBar.Value = $PercentComplete
			        $Runspace.ProgressBar.Foreground = $Color
			        $Runspace.txtStatus.Text = $StatusMsg
                    $syncHash.txtStatus.Foreground = $Color
			        $Runspace.txtPercentage.Text = ('' + $PercentComplete + '%')
            })
        }
    }
    else{
        $Runspace.ProgressBar.Dispatcher.Invoke("Normal",[action]{
			$Runspace.ProgressBar.IsIndeterminate = $True
			$Runspace.ProgressBar.Foreground = $Color
			$Runspace.txtStatus.Text = $StatusMsg
            $syncHash.txtStatus.Foreground = $Color
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
        [Parameter(Mandatory = $true, Position=0)]
        $ItemsList,
        [Parameter(Mandatory = $true, Position=1,ParameterSetName="listbox")]
        [System.Windows.Controls.ListBox]$ListObject,
        [Parameter(Mandatory = $true, Position=1,ParameterSetName="dropdown")]
        [System.Windows.Controls.ComboBox]$DropdownObject,
        [Parameter(Mandatory = $false, Position=2)]
        [string]$Identifier,
        [switch]$Passthru
    )
    ## Get the name of this function
    [string]${CmdletName} = $MyInvocation.MyCommand

    If ($PSCmdlet.ParameterSetName -eq "listbox") {
        $Object = $ListObject
        $Object.Items.Clear();
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
    foreach ($item in $ItemsList)
    {
        #Check to see if properties exists
        If($item.PSobject.Properties.Name.Contains($Identifier)){
            $Object.Items.Add($item.$Identifier) | Out-Null
        }
        Else{
            $Object.Items.Add($item) | Out-Null
        }
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


Function Show-IDMAssignmentsWindow {

    Param(
        $DeviceData,
        $DeviceAssignments,
        $UserData,
        $UserAssignments,
        [switch]$External
    )
    #build runspace
    $syncHash = [hashtable]::Synchronized(@{})
    $ASPRunSpace =[runspacefactory]::CreateRunspace()
    $syncHash.Runspace = $ASPRunSpace
    $syncHash.IsChangeable = $External
    $syncHash.DeviceData = $DeviceData
    $syncHash.DeviceAssignments = $DeviceAssignments
    $syncHash.UserData = $UserData
    $syncHash.UserAssignments = $UserAssignments
    $syncHash.AssignmentData = @()
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
        mc:Ignorable="d"
        Title="DeviceAssignments" Height="600" Width="1000"
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

        <Label Content="Search" HorizontalAlignment="Center" VerticalAlignment="Top" Width="48" HorizontalContentAlignment="Right" Margin="0,12,0,0"/>
        <TextBox x:Name="txtAssignmentSearch" HorizontalAlignment="Left" Height="22" VerticalAlignment="Top" Width="422" Margin="522,16,0,0"/>
        <Button x:Name="btnAssignments" Content="Get Assignments" HorizontalAlignment="Left" VerticalAlignment="Top" VerticalContentAlignment="Center"  Width="97" Height="51" Margin="295,17,0,0" />
        <Label Content="Column Filter" HorizontalAlignment="Left" VerticalAlignment="Top" Width="93" HorizontalContentAlignment="Right" Margin="429,44,0,0"/>
        <ComboBox x:Name="cmbFilterOnColumn" Width="140" Margin="522,46,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" />
        <ComboBox x:Name="cmbColumnValues" Width="277" Margin="667,46,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" />
        <Button x:Name="btnReset" Content="X" VerticalContentAlignment="Center" HorizontalContentAlignment="Center" HorizontalAlignment="Left" VerticalAlignment="Top"  Width="28" Height="22" Margin="949,46,0,0" />

        <ListView x:Name="lstDeviceAssignments" HorizontalAlignment="Center" Height="437" Margin="0,73,0,0"  VerticalAlignment="Top" Width="958">
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
        <Label Content="Total Assignments:" HorizontalAlignment="Left" VerticalAlignment="Top" Width="142" HorizontalContentAlignment="Right" Margin="19,514,0,0"/>
        <TextBox x:Name="txtTotalAssignments" Text="0" HorizontalAlignment="Left" Height="22" VerticalAlignment="Top" Width="66" IsEnabled="False" Margin="166,519,0,0" BorderThickness="0"/>
        <Label Content="Device Assignments:" HorizontalAlignment="Left" VerticalAlignment="Top" Width="142" HorizontalContentAlignment="Right" Margin="19,536,0,0"/>
        <TextBox x:Name="txtDeviceAssignments" Text="0" HorizontalAlignment="Left" Height="22" VerticalAlignment="Top" Width="66" IsEnabled="False" Margin="166,543,0,0" BorderThickness="0"/>
        <Label Content="User Assignments:" HorizontalAlignment="Left" VerticalAlignment="Top" Width="142" HorizontalContentAlignment="Right" Margin="19,560,0,0"/>
        <TextBox x:Name="txtUserAssignments" Text="0" HorizontalAlignment="Left" Height="22" VerticalAlignment="Top" Width="66" IsEnabled="False" Margin="166,567,0,0" BorderThickness="0"/>

        <Button x:Name="btnExport" Content="Export" HorizontalAlignment="Left" VerticalAlignment="Top"  Width="124" Height="33"  FontSize="16" Margin="724,521,0,0" />
        <Button x:Name="btnExit" Content="Exit" HorizontalAlignment="Left" VerticalAlignment="Top"  Width="124" Height="33" FontSize="16" Margin="853,521,0,0"/>
        <ProgressBar x:Name="ProgressBar" Width="644" Height="14" Margin="188,566,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" Background="White" Foreground="LightGreen" />
        <TextBox x:Name="txtStatus" HorizontalAlignment="Left" Height="28" VerticalAlignment="Top" Width="433" IsEnabled="False" Margin="188,527,0,0" BorderThickness="0" TextWrapping="Wrap"/>
        <TextBox x:Name="txtPercentage" Text="100%" HorizontalAlignment="Left" Height="23" VerticalAlignment="Top" Width="37" IsEnabled="False" Margin="837,563,0,0" BorderThickness="0"/>
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
        Function Close-IDMAssignmentsWindow
        {
            if ($syncHash.hadCritError) { Write-Host -Message "Background thread had a critical error" -ForegroundColor red }
            #if runspace has not errored Dispose the UI
            if (!($syncHash.isClosing)) { $syncHash.Window.Close() | Out-Null }
        }

        If($syncHash.DeviceAssignments.count -gt 0){$syncHash.AssignmentData += $syncHash.DeviceAssignments}
        If($syncHash.UserAssignments.count -gt 0){$syncHash.AssignmentData += $syncHash.UserAssignments}

        #Combine data into one
        $syncHash.lstDeviceAssignments.ItemsSource = $syncHash.AssignmentData

        @("Name","Type","Mode","Target","Group","GroupType","Platform") | %{$syncHash.cmbFilterOnColumn.Items.Add($_) | Out-Null}
        $syncHash.cmbFilterOnColumn.SelectedItem = "Name"

        #populate text fields
        $syncHash.txtDeviceName.Text = $syncHash.DeviceData.DeviceName
        $syncHash.txtAssignedUPN.Text = $syncHash.UserData.userPrincipalName
        $syncHash.txtTotalAssignments.Text = $syncHash.AssignmentData.Count
        $syncHash.txtDeviceAssignments.Text = $syncHash.DeviceAssignments.Count
        $syncHash.txtUserAssignments.Text = $syncHash.UserAssignments.Count

        If($syncHash.IsChangeable){
            $syncHash.txtDeviceName.IsReadOnly = $false
            $syncHash.txtAssignedUPN.IsReadOnly = $false
            $syncHash.ProgressBar.Visibility = 'Visible'
            $syncHash.txtPercentage.Visibility = 'Visible'
            $syncHash.txtStatus.Visibility = 'Visible'
            $syncHash.btnAssignments.Visibility = 'Visible'
        }
        Else{
            $syncHash.txtDeviceName.IsReadOnly = $true
            $syncHash.txtAssignedUPN.IsReadOnly = $true
            $syncHash.ProgressBar.Visibility = 'Hidden'
            $syncHash.txtPercentage.Visibility = 'Hidden'
            $syncHash.txtStatus.Visibility = 'Hidden'
            $syncHash.btnAssignments.Visibility = 'Hidden'
        }

        #ACTIVATE LIVE SEARCH
        $syncHash.txtAssignmentSearch.AddHandler(
            [System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
            [System.Windows.RoutedEventHandler]{
                If($syncHash.cmbFilterOnColumn.SelectedItem){
                    $syncHash.lstDeviceAssignments.ItemsSource = ($syncHash.AssignmentData | Where {$_.($syncHash.cmbFilterOnColumn.SelectedItem) -like "*$($syncHash.txtAssignmentSearch.text)*"})
                }
                Else{
                    $syncHash.lstDeviceAssignments.ItemsSource = ($syncHash.AssignmentData | Where {$_.Name -like "*$($syncHash.txtAssignmentSearch.text)*"})
                }
            }
        )

        $syncHash.cmbFilterOnColumn.Add_SelectionChanged({
            #first sort data by selected item
            $syncHash.lstDeviceAssignments.ItemsSource = ($syncHash.AssignmentData | Sort $syncHash.cmbFilterOnColumn.SelectedItem)
            #build values for next item
            $syncHash.cmbColumnValues.Items.Clear()
            $syncHash.AssignmentData.($syncHash.cmbFilterOnColumn.SelectedItem) | Select -Unique | %{$syncHash.cmbColumnValues.Items.Add($_) | Out-Null}
        })

        $syncHash.cmbColumnValues.Add_SelectionChanged({
            $syncHash.lstDeviceAssignments.ItemsSource = ($syncHash.AssignmentData | Where {$_.($syncHash.cmbFilterOnColumn.SelectedItem) -eq $syncHash.cmbColumnValues.SelectedItem})
        })

        $syncHash.btnReset.Add_Click({
            $syncHash.txtAssignmentSearch.text = $null
            $syncHash.cmbFilterOnColumn.SelectedItem = $null
            $syncHash.cmbColumnValues.SelectedItem = $null
            $syncHash.lstDeviceAssignments.ItemsSource = $syncHash.AssignmentData
        })

        $syncHash.btnExport.Add_Click({
            # disable this button to prevent multiple export.
            $this.IsEnabled = $false
            $syncHash.Data | Export-Csv -NoTypeInformation "$env:USERPROFILE\Desktop\$($syncHash.txtDeviceName.Text)_$($syncHash.txtAssignedUPN.Text.replace('@','_'))_$(Get-Date -Format yyyyMMdd).csv" -Force
        })

        $syncHash.btnExit.Add_Click({
            Close-IDMAssignmentsWindow
        })

        #Allow UI to be dragged around screen
        $syncHash.Window.Add_MouseLeftButtonDown( {
            $syncHash.Window.DragMove()
        })

        #Add smooth closing for Window
        $syncHash.Window.Add_Loaded({ $syncHash.isLoaded = $True })
        $syncHash.Window.Add_Closing({ $syncHash.isClosing = $True; Close-IDMAssignmentsWindow })
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

#$IDMAssignment = Show-IDMAssignmentsWindow -DeviceData $syncHash.Data.SelectedDevice -DeviceAssignments $syncHash.Data.DeviceAssignments -UserData $syncHash.Data.AssignedUser -UserAssignments $syncHash.Data.UserAssignments
