#SEARCH HANDLER FOR DEVICES
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
            $syncHash.txtSearchIntuneDevices.Text = 'Search...'
            $syncHash.txtSearchIntuneDevices.Foreground = 'Gray'
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
            Search-UIList -ItemsList $syncHash.Data.IntuneDevices -ListObject $syncHash.listIntuneDevices -Identifier 'deviceName' -filter $syncHash.txtSearchIntuneDevices.Text
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

#SEARCH HANDLER FOR USER
# -------------------------------------------
$syncHash.txtSearchUser.AddHandler(
    [System.Windows.Controls.Primitives.TextBoxBase]::GotFocusEvent,
    [System.Windows.RoutedEventHandler]{
        #set a variable if there is text in field BEFORE the new name is typed
        If($syncHash.txtSearchUser.Text){
            $script:SearchText = $syncHash.txtSearchUser.Text
        }
    }
)

$syncHash.txtSearchUser.AddHandler(
    [System.Windows.Controls.Primitives.TextBoxBase]::LostFocusEvent,
    [System.Windows.RoutedEventHandler]{
        #because there is a example text field in the box by default, check for that
        If($syncHash.txtSearchUser.Text -eq 'Search...'){
            $script:SearchText = $syncHash.txtSearchUser.Text
        }
        ElseIf([string]::IsNullOrEmpty($syncHash.txtSearchUser.Text)){
            #add example back in light gray font
            $syncHash.txtSearchUser.Text = 'Search...'
            $syncHash.txtSearchUser.Foreground = 'Gray'
        }
        Else{
        }
    }
)

#ACTIVATE LIVE SEARCH
$syncHash.txtSearchUser.AddHandler(
    [System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
    [System.Windows.RoutedEventHandler]{
        If(-not([string]::IsNullOrEmpty($syncHash.txtSearchUser.Text)) -and ($syncHash.txtSearchUser.Text -ne 'Search...') -and ($syncHash.Data.AzureUsers.count -gt 0)){
            Search-UIList -ItemsList $syncHash.Data.AzureUsers -ListObject $syncHash.listUsers -Identifier 'userPrincipalName' -filter $syncHash.txtSearchUser.Text
        }
    }
)

#Textbox placeholder remove default text when textbox is being used
$syncHash.txtSearchUser.Add_GotFocus({
    #if it has an example
    if ($syncHash.txtSearchUser.Text -eq 'Search...') {
        #clear value and make it black bold ready for input
        $syncHash.txtSearchUser.Text = ''
        $syncHash.txtSearchUser.Foreground = 'Black'
        #should be black while typing....
    }
    #if it does not have an example
    Else{
        #ensure test is black and medium
        $syncHash.txtSearchUser.Foreground = 'Black'
    }
})

#Textbox placeholder grayed out text when textbox empty and not in being used
$syncHash.txtSearchUser.Add_LostFocus({
    #if text is null (after it has been clicked on which cleared by the Gotfocus event)
    if ($syncHash.txtSearchUser.Text -eq '') {
        #add example back in light gray font
        $syncHash.txtSearchUser.Foreground = 'Gray'
        $syncHash.txtSearchUser.Text = 'Search...'
    }
})

#SEARCH HANDLER FOR STALE DEVICES
# -------------------------------------------
$syncHash.txtSearchStaleDevices.AddHandler(
    [System.Windows.Controls.Primitives.TextBoxBase]::GotFocusEvent,
    [System.Windows.RoutedEventHandler]{
        #set a variable if there is text in field BEFORE the new name is typed
        If($syncHash.txtSearchStaleDevices.Text){
            $script:SearchText = $syncHash.txtSearchStaleDevices.Text
        }
    }
)

$syncHash.txtSearchStaleDevices.AddHandler(
    [System.Windows.Controls.Primitives.TextBoxBase]::LostFocusEvent,
    [System.Windows.RoutedEventHandler]{
        #because there is a example text field in the box by default, check for that
        If($syncHash.txtSearchStaleDevices.Text -eq 'Search...'){
            $script:SearchText = $syncHash.txtSearchStaleDevices.Text
        }
        ElseIf([string]::IsNullOrEmpty($syncHash.txtSearchStaleDevices.Text)){
            #add example back in light gray font
            $syncHash.txtSearchStaleDevices.Text = 'Search...'
            $syncHash.txtSearchStaleDevices.Foreground = 'Gray'
        }
        Else{
        }
    }
)

#ACTIVATE LIVE SEARCH
$syncHash.txtSearchStaleDevices.AddHandler(
    [System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
    [System.Windows.RoutedEventHandler]{
        If(-not([string]::IsNullOrEmpty($syncHash.txtSearchStaleDevices.Text)) -and ($syncHash.txtSearchStaleDevices.Text -ne 'Search...') -and ($syncHash.Data.StaleDevices.count -gt 0)){
            Search-UIList -ItemsList $syncHash.Data.StaleDevices -ListObject $syncHash.listStaleDevices -Identifier 'deviceName' -filter $syncHash.txtSearchStaleDevices.Text
        }
    }
)

#Textbox placeholder remove default text when textbox is being used
$syncHash.txtSearchStaleDevices.Add_GotFocus({
    #if it has an example
    if ($syncHash.txtSearchStaleDevices.Text -eq 'Search...') {
        #clear value and make it black bold ready for input
        $syncHash.txtSearchStaleDevices.Text = ''
        $syncHash.txtSearchStaleDevices.Foreground = 'Black'
        #should be black while typing....
    }
    #if it does not have an example
    Else{
        #ensure test is black and medium
        $syncHash.txtSearchStaleDevices.Foreground = 'Black'
    }
})

#Textbox placeholder grayed out text when textbox empty and not in being used
$syncHash.txtSearchStaleDevices.Add_LostFocus({
    #if text is null (after it has been clicked on which cleared by the Gotfocus event)
    if ($syncHash.txtSearchStaleDevices.Text -eq '') {
        #add example back in light gray font
        $syncHash.txtSearchStaleDevices.Foreground = 'Gray'
        $syncHash.txtSearchStaleDevices.Text = 'Search...'
    }
})
