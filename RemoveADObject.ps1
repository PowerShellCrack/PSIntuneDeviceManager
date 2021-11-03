#Define the Credential
$User = '$User'
$securePassword = $password | ConvertTo-SecureString -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $securePassword

# Retrieve NetBIOS name of local computer.
$strName = $env:ComputerName

# Create an ADSI Search
$adsisearcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher

# Find AD computer object.
#https://social.technet.microsoft.com/wiki/contents/articles/5392.active-directory-ldap-syntax-filters.aspx
$adsisearcher.Filter = "(&(objectCategory=Computer)(sAMAccountName=$strName`$))"

# Limit the output to unlimited objects
$Searcher.SizeLimit = 0
$Searcher.PageSize = 10000

# Get the current domain
$DomainDN = $(([adsisearcher]"").Searchroot.path)
#$DomainDN = $adsisearcher.SearchRoot = [ADSI]'LDAP://OU=MyOU,OU=MyParentOU,DC=MyDomain,DC=local'

# Create an object "DirectoryEntry" and specify the domain, username and password
$Domain = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList $DomainDN,
   $($Credential.UserName),
   $($Credential.GetNetworkCredential().password)

# Add the Domain to the search
$Searcher.SearchRoot = $Domain

# Execute the Search
$colResults = $adsisearcher.FindAll()

#Search should return 1 value
ForEach ($strComputer In $colResults)
{
    $strDN = $strComputer.properties.Item("distinguishedName")
    $Computer = [ADSI]"LDAP://$strDN"
    $Computer.DeleteTree()
}