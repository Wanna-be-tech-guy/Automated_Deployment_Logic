Root directory for the script (where the script should be ran from):

C:\Users\<username>\Documents\Automated_Deployment_Logic

When you ls from that directory, you should see something akeen to the following:
PS C:\Users\andy1\Documents\Automated_Depolyment_Logic> ls


    Directory: C:\Users\andy1\Documents\Automated_Depolyment_Logic


Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
d-----        10/31/2024  10:12 AM                New_Install_Files
d-----        10/31/2024  10:06 AM                Script_Files
-a----        10/31/2024  10:19 AM          25323 automated_deployment.ps1

The CSV that the script looks for (New_Install_Test.csv) should live in the New_Install_Files:
PS C:\Users\andy1\Documents\Automated_Depolyment_Logic> ls C:\Users\andy1\Documents\Automated_Depolyment_Logic\New_Install_Files\


    Directory: C:\Users\andy1\Documents\Automated_Depolyment_Logic\New_Install_Files


Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
d-----        10/31/2024  10:06 AM                New_Install_Template
-a----         2/27/2024   3:27 PM             66 New_Install_Test.csv
