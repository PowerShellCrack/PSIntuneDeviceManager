# PSIntuneDeviceRenamer
Rename a HAADJ device in Intune

**WORK-IN-PROGRESS** This is still in development. 

## Here is how you use it:
To launch the script; its best to call it through PowerShell, like so:

The script will check for prerequisites:

- MSGraph Intune module
- Azure AD
- RSAT Tools/PowerShell Module
- If its ran on a Domain joined device
- If PowerShell is version 5.1 or higher

It will attempt to install them (from internet)…so if it’s not ran as privilege administrator; it may fail. You will see them as red in the bottom status bar in the UI

Once all prereqs are installed and everything shows green in the status bar (besides MSGraph Connected), you can continue. 

I wrote the script to output data while it launches the UI. You will see that in the console window, it will also provide a working log in the UI (not external)

Once the UI is launched, here are the steps to perform:

1.	Click the button:  Connect to Intune (MSGraph)
![Connect](/.images/connect.PNG)

a.	This will minimize the UI and request your Azure login. 
b.	You will be required to accept the “allow permissions to read and write to Intune”. Scroll down and click Accept
c.	You may have to brin the UI back up from the task bar. I tried to get to restore window, but sometimes it does not. 

2.	Once its connected, it will immediately start pulling Windows AAD devices into the list. 
a.	This is preconfigured to filter anything other than Windows. 
NOTE: this may take a bit, depending on device count. The UI may look like its not responding (its not a multithreaded UI). Please let me know how long it took to retrieve the device and count.

3.	You can search the device in the search window (it will filter as you type). 

4.	Once you select click the object, the script will grab the user information from Azure AD and it will attempt to find the corresponding object in AD.
a.	You will see the Assigned User in the right area. 

5.	Click on the Sync button to corollate the Azure account with the AD account. 
a.	If the account is found, the accounts distinguished name will appear below.
b.	And it will auto generate the name as well (based on rules set) 

6.	The auto generated name, will use the Generation rules specified in the configure tab
a.	This is preconfigured to use your naming convention but can be changed. * 
b.	If you change the rules, click the Sync button to refresh the name

7.	Select the move to OU checkbox to move the AD object to another OU. 
a.	This is preconfigured to the root computers OU. This can be changed in configure tab. 

8.	Click Rename Device. 
WARNING: this will attempt to rename the Intune object and not in AD.
a.	If you refresh the list and select the same device again; a warning message will come up near bottom of screen stating there is a pending rename action. 
b.	You can also check Intune and see the same action. 


Intune message after rename


You will receive a message it is successfully renamed. 


A notification will display, If you click on the same device after rename


Here is an error that the AD object cannot be found


The configure screen is pretty complex but I wanted to make it more universal. Its preconfigured with your environment in mind and with a few tweaks to the options it may support changes in the future. 
It does have a rule tester that can be used to test OU based name generation.
 


The pre-configurations can be changes when calling script with parameters **
 

There is also a logging tab that will allow you to view the work being done. ***

I was also unable to test chassis function to pull correct letter for laptop or workstation. Let me know if this works. 

Features that don’t work just yet:
•	Alternate AD credentials
•	Option to not increment name
•	*All Generation Methods except “User OU Name”
•	** Azure government support not working
•	*** Some logging is missing


Even though I have tested this to the extend that I could I want to ensure your aware of Microsoft’s position on developing scripts. 
This is usually what come along with the scripts:

This Sample Code is provided for the purpose of illustration only and is not
intended to be used in a production environment.  THIS SAMPLE CODE AND ANY
RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a
nonexclusive, royalty-free right to use and modify the Sample Code and to
reproduce and distribute the object code form of the Sample Code, provided
that You agree: (i) to not use Our name, logo, or trademarks to market Your
software product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is embedded;
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and
against any claims or lawsuits, including attorneys’ fees, that arise or result
from the use or distribution of the Sample Code.

This posting is provided "AS IS" with no warranties, and confers no rights. Use
of included script samples are subject to the terms specified
at https://www.microsoft.com/en-us/legal/copyright.
