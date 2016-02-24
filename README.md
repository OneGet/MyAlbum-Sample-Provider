
This is a sample PackageManagement provider. It discovers photos in your remote file repository and installs them to your local folder. The purpose of this provider is trying to provide some help for people to get started with writing a PackageManagement provider in PowerShell. The point is not trying to provide an implementation that users can directly copy and paste.

Let's try it out

####1. Search and Install the MyAlbum provider####
``` PowerShell
PS C:\>find-packageprovider -name MyAlbum
PS C:\>install-packageprovider -name MyAlbum -force
```
####2. Create a local repository####
``` PowerShell
PS C:\>mkdir c:\test
PS C:\>New-Item seattle.png
PS C:\>New-Item "new york.png"
```
####3. Register a repository

``` PowerShell
Register-PackageSource -Name album -ProviderName myalbum -Location  C:\test
```
####4. Find packages
``` PowerShell
Find-Package -ProviderName myalbum
```


