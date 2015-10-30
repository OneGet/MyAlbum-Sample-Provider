@{

RootModule = 'MyAlbum.psm1'
ModuleVersion = '0.1'
GUID = 'ae72ced2-5c91-46e2-9081-e272df6282ef'
Author = 'Contoso Corporation'
CompanyName = 'Contoso Corporation'
Copyright = '© Contoso Corporation. All rights reserved.'
Description = 'MyAlbum provider discovers the photos in your remote file repository and installs them to your local folder.'
PowerShellVersion = '3.0'   
RequiredModules = @('PackageManagement')
PrivateData = @{"PackageManagementProviders" = 'MyAlbum.psm1'

    PSData = @{

        # Tags applied to this module to indicate this is a PackageManagement Provider.
        Tags = @("PackageManagement","Provider")

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/OneGet/MyAlbum-Sample-Provider/blob/master/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/OneGet/MyAlbum-Sample-Provider'

        # ReleaseNotes of this module
        ReleaseNotes = 'This is a sample PackageManagement provider. It discovers photos in your remote file repository and installs them to your local folder.
        The purpose of this provider is trying to provide some help for people to get started with writing a PackageManagement provider in PowerShell. The point
        is not trying to provide an implementation that users can directly copy and paste.          
        '
        } # End of PSData
    }
}

