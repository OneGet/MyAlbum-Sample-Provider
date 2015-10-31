# This is a sample PackageManagement provider. It is trying to discover photos in your remote file repository 
# and installs them to your local folder.  

# Import the localized Data
Microsoft.PowerShell.Utility\Import-LocalizedData  LocalizedData -filename MyAlbum.Resource.psd1

#region Local variable definitions
# Define the provider name
$script:ProviderName = "MyAlbum"

# The folder where stores the provider configuration file
$script:LocalPath="$env:LOCALAPPDATA\Contoso\$script:ProviderName"
$script:RegisteredPackageSources = $null    
$script:RegisteredPackageSourcesFilePath = Microsoft.PowerShell.Management\Join-Path -Path $script:LocalPath -ChildPath "MyAlbumPackageSource.xml"


# Wildcard pattern matching configuration
$script:wildcardOptions = [System.Management.Automation.WildcardOptions]::CultureInvariant -bor `
                          [System.Management.Automation.WildcardOptions]::IgnoreCase

#endregion


#region Provider APIs Implementation

# Mandatory function for the PackageManagement providers. It returns the name of your provider.
function Get-PackageProviderName { 

    return $script:ProviderName
}

# Mandatory function for the PackageManagement providers. It initializes your provider before performing any actions.
function Initialize-Provider { 

    Write-Debug ($LocalizedData.ProviderDebugMessage -f ('Initialize-Provider'))

    #add your intialize code here
}



<# Optional function that indicates what featues your provider supports. Returns a collection of features this provider supports.
    This is primarily for others to leveage your provider. Here is the existing features defined by PackageManagement:

    SupportsPowerShellModules = "supports-powershell-modules";    === find, install, powershell modules
    SupportsRegexSearch       = "supports-regex-search";          === support Regualar expression search
    SupportsWildcardSearch    = "supports-wildcard-search";       === support wildcard search

    SupportedExtensions       = "file-extensions";                === package file extensions, e.g., .msi, .nupkg
    SupportedSchemes          = "uri-schemes";                    === url shemes, e.g., http, https, file
    MagicSignatures           = "magic-signatures";               === bytes at the begining of a package file, .cab, .zip
#>
function Get-Feature
{
    Write-Debug ($LocalizedData.ProviderDebugMessage -f ('Get-Feature'))

    # Write out to the host. In this case, PackageManagement is the host.
    Write-Output -InputObject (New-Feature -name "file-extensions" -values @(".png"))
    
   <#
    Add more features that your provider supports here.  e.g.,
    Write-Output -InputObject (New-Feature -name "supports-python-modules")
    #>
}


# Optional function that returns dynamic parameters defined by the provider to the PackageManagement. 
function Get-DynamicOptions
{
    param
    (
        [Microsoft.PackageManagement.MetaProvider.PowerShell.OptionCategory] 
        $category
    )

    Write-Debug ($LocalizedData.ProviderDebugMessage -f ('Get-DynamicOptions'))
    
    # There are available categories defined by PackageManagement: 
    # Package  - for searching for packages 
    # Source   - for package sources
    # Install  - for Install/Uninstall/Get-InstalledPackage

    switch($category)
    {
        Package {
                    Write-Output -InputObject (New-DynamicOption -Category $category -Name "Filter" -ExpectedType String -IsRequired $false)                    
                }


        Install 
                {
                    Write-Output -InputObject (New-DynamicOption -Category $category -Name "Destination" -ExpectedType String -IsRequired $true)
                }
    }
}


# Optional function that gets called when the user is registering a package source. 
# .e.g, Register-PackageSource -Name demo -Location  C:\CameraRoll -ProviderName MyAlbum
# If your provider supports Register-PackageSource, it is required to implement this function.
function Add-PackageSource
{
    [CmdletBinding()]
    param
    (
        [string]
        $Name,
         
        [string]
        $Location,

        [bool]
        $Trusted
    )     
    
    Write-Debug ($LocalizedData.ProviderDebugMessage -f ('Add-PackageSource'))  
    Get-PSDrive
    if(-not (Microsoft.PowerShell.Management\Test-Path -path $Location))
    {        
        ThrowError -ExceptionName "System.ArgumentException" `
                    -ExceptionMessage ($LocalizedData.PathNotFound -f ($Location)) `
                    -ErrorId "PathNotFound" `
                    -CallerPSCmdlet $PSCmdlet `
                    -ErrorCategory InvalidArgument `
                    -ExceptionObject $Location
        return
    }
    
    # We do not allow "Register-PackageSource -Name a*"
    if(Test-WildcardPattern $Name)
    {
        ThrowError -ExceptionName "System.ArgumentException" `
                    -ExceptionMessage ($LocalizedData.PackageSourceNameContainsWildCards -f ($Name)) `
                    -ErrorId "PackageSourceNameContainsWildCards" `
                    -CallerPSCmdlet $PSCmdlet `
                    -ErrorCategory InvalidArgument `
                    -ExceptionObject $Name
        return
    }

    Set-PackageSourcesVariable -Force
             
    # Add new package source
    $packageSource = Microsoft.PowerShell.Utility\New-Object PSCustomObject -Property ([ordered]@{
            Name = $Name
            SourceLocation = $Location.TrimEnd("\") 
            Trusted=$Trusted
            Registered= $true
            InstallationPolicy = if($Trusted) {'Trusted'} else {'Untrusted'}          
        })    

    $script:RegisteredPackageSources.Add($Name, $packageSource)

    Write-Verbose -Message ($LocalizedData.SourceRegistered -f ($Name, $Location))

    # Persist the package sources
    Save-PackageSources

    # yield the package source to OneGet
    Write-Output -InputObject (New-PackageSourceAndYield -Source $packageSource)

}

# Optional function that unregisters a package Source. e.g., Unregister-PackageSource -Name album.
# It is required to implement this function for providers that support Unregister-PackageSource.
function Remove-PackageSource
{ 
    param
    (
        [string]
        $Name
    )

    Write-Debug ($LocalizedData.ProviderDebugMessage -f ('Remove-PackageSource'))

    Set-PackageSourcesVariable -Force

    # Check if $Name contains any wildcards
    if(Test-WildcardPattern $Name)
    {
        $message = $LocalizedData.PackageSourceNameContainsWildCards -f ($Name)
        Write-Error -Message $message -ErrorId "PackageSourceNameContainsWildCards" -Category InvalidOperation -TargetObject $Name
        return
    }

    # Error out if the specified source name is not in the registered package sources.
    if(-not $script:RegisteredPackageSources.Contains($Name))
    {
        $message = $LocalizedData.PackageSourceNotFound -f ($Name)
        Write-Error -Message $message -ErrorId "PackageSourceNotFound" -Category InvalidOperation -TargetObject $Name
        return
    }

    # Remove the SourcesToBeRemoved
    $script:RegisteredPackageSources.Remove($Name) 

    # Persist the package sources
    Save-PackageSources 
    Write-Verbose ($LocalizedData.PackageSourceUnregistered -f ($Name))     
}


# This is an optional function that returns the registered package sources or the sources the provider can handle. 
# For exmaple, it gets called during find-package, install-package, get-packagesource etc.
# PackageManagement uses this method to identify which provider can handle the packages from a particular source location.
# Therefore in general this function needs to be implemented.

function Resolve-PackageSource
{ 
    Write-Debug ($LocalizedData.ProviderDebugMessage -f ('Resolve-PackageSource'))
        
    # Use the $request object to get user's cmdline parameter values, or return the values back to PackageManagement.
    # Get the value of "-Source" from user's commandline input
    $SourceName = $request.PackageSources

    # get Sources from the registered config file
    Set-PackageSourcesVariable

    if(-not $SourceName)
    {
        $SourceName = "*"
    }

    foreach($src in $SourceName)
    {
        if($request.IsCanceled) { return }

        # Get the sources that registered before
        $wildcardPattern = New-Object System.Management.Automation.WildcardPattern $src,$script:wildcardOptions
        $sourceFound = $false

        $script:RegisteredPackageSources.GetEnumerator() | 
            Microsoft.PowerShell.Core\Where-Object {$wildcardPattern.IsMatch($_.Key)} | 
                Microsoft.PowerShell.Core\ForEach-Object {
                    $source = $script:RegisteredPackageSources[$_.Key]
                    $packageSource = New-PackageSourceAndYield -Source $source

                    Write-Output -InputObject $packageSource
                    $sourceFound = $true
                }

        # If a user does specify -Source but not registered
        if(-not $sourceFound)
        {    
            # Get source name from the source location in case a user passes in location instead of name                   
            $sourceName  = Get-SourceName -Location $src
            if($sourceName)
            {
                $source = $script:RegisteredPackageSources[$sourceName]
                $packageSource = New-PackageSourceAndYield -Source $source
                Write-Output -InputObject $packageSource
            } 
            # So far we found the given source is not a registered package source Name nor Location   
            # It depends on your provider's implementation whether you want to support unregistered source. 
            # If you do, add your code here. In this example, we only suppport the registered ones.         
            elseif( -not (Test-WildcardPattern $src))            
            {
                $message = $LocalizedData.PackageSourceNotFound -f ($src)
                Write-Error -Message $message -ErrorId "PackageSourceNotFound" -Category InvalidOperation -TargetObject $src
            }
        }
    }
}


# Optional function that finds packages by given name and version information. 
# It is required to implement this function for the providers that support find-package. For example, find-package -ProviderName  MyAlbum -Source demo.
function Find-Package { 
    param(
        [string] $name,
        [string] $requiredVersion,
        [string] $minimumVersion,
        [string] $maximumVersion
    )

    Write-Debug ($LocalizedData.ProviderDebugMessage -f ('Find-Package'))

    # Read in the registered package source information to the memory
    Set-PackageSourcesVariable
	
    $ValidationResult = Validate-VersionParameters  -Name $Name `
                                                    -MinimumVersion $MinimumVersion `
                                                    -MaximumVersion $MaximumVersion `
                                                    -RequiredVersion $RequiredVersion
    
    if(-not $ValidationResult)
    {
        # Return now as the version validation failed already
        return
    }                                                

    # Get the cmdlet parameter values that were passed from the user via the $request.Options. 
    # Here we can find out the package source name passed by a user.
    <#
        Commonly used properties of $request object:
        PackageSources     --  -Source
        Options            --  Get any user's input via Options
        Credential         --  -Credential
        IsCanceled         --  Is operation cancelling?
    #>

    $options = $request.Options
    foreach( $o in $options.Keys )
    {
        Write-Debug ( "OPTION: {0} => {1}" -f ($o, $options[$o]) )
    }

    # Check if a user specifies -Source
    $selectedSources = @()
    if($options -and $options.ContainsKey('Source'))
    {        
        # Finding the matched package sources from the registered ones
        $sourceNames = $($options['Source'])
        Write-Verbose ($LocalizedData.SpecifiedSourceName -f ($sourceNames))        
        
        foreach($sourceName in $sourceNames)
        {            
            if($script:RegisteredPackageSources.Contains($sourceName))
            {
                # Found the matched registered source
                $selectedSources += $script:RegisteredPackageSources[$sourceName]                
            }
            else
            {
                $sourceByLocation = Get-SourceName -Location $sourceName
                if ($sourceByLocation -ne $null)
                {
                    $selectedSources += $script:RegisteredPackageSources[$sourceByLocation]                                        
                }
                else
                {
                     $message = $LocalizedData.PackageSourceNotFound -f ($sourceName)
                     ThrowError -ExceptionName "System.ArgumentException" `
                           -ExceptionMessage $message `
                           -ErrorId "PackageSourceNotFound" `
                           -CallerPSCmdlet $PSCmdlet `
                           -ErrorCategory InvalidArgument `
                           -ExceptionObject $sourceName
                }
            }
        }
    }
    else
    {
        # User does not specify -Source, we will use the registered sources
        Write-Verbose $LocalizedData.NoSourceNameIsSpecified        
        $script:RegisteredPackageSources.Values | Microsoft.PowerShell.Core\ForEach-Object { $selectedSources += $_ }
    }

    # finding the package 
    foreach($source in $selectedSources)
    {      
        if($request.IsCanceled) { return }

        $location = $source.SourceLocation

        if(-not (Test-Path $location)) { continue }
                   
        # Find the photos
        $files = Get-ChildItem -Path $location -Filter '*.png' -Recurse  | `
                        Where-Object { ($_.PSIsContainer -eq $false) -and  ( $_.Name -like "*$name*") }
                          
                                  
        foreach($file in $files)
        {
            <#add code here for handling filter #>

            if($request.IsCanceled) { return }  
                
                # Note: FastPackageReference is used across multiple calls such as Find-package, Install-package, UnInstall-Package and Download-Package.
                # The format of FastPackageReference needs to be consistent within your provider. It usually contains package Name, Version and Source. 
                # In the MyAlbum case, we choose the file full path just for demo purpose.
                $swidObject = @{
                    FastPackageReference = $file.FullName;
                    Name = $file.Name;
                    Version = New-Object System.Version ("0.1");  # Note: You need to fill in a proper package version. 
                    versionScheme  = "MultiPartNumeric";
                    summary = "Add the summary of your package provider here";
                    Source = $location;              
                }

                $sid = New-SoftwareIdentity @swidObject              
                Write-Output -InputObject $sid               
        }                    
    }
}

# Optional function that downloads a remote package file to a local location. It is called for Save-Package.
# It is required to implement this function for the providers that support save-package. For example, save-package -Name Seattle -Path C:\ForSave\.
function Download-Package
{ 
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FastPackageReference,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Location
    )
   
    Write-Debug ($LocalizedData.ProviderDebugMessage -f ('Download-Package'))
    Write-Debug -Message ($LocalizedData.FastPackageReference -f $fastPackageReference)
	

    <#
        You need to add code here in your real provider:
     1. parse the FastPackageReference for package name, version, source etc.
     2. Find the matched source from the registered ones
     3. Use the Source to download packages
    #>

    Install-PackageUtility -FastPackageReference $fastPackageReference -Location $Location -Request $request
}

# It is required to implement this function for the providers that support install-package. 
# for example, install-package -Name seattle -ProviderName myalbum -Source demo -Destination c:\myfolder
function Install-Package
{ 
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $fastPackageReference
    )

    Write-Debug -Message ($LocalizedData.ProviderDebugMessage -f ('Install-Package'))  
    Write-Debug -Message ($LocalizedData.FastPackageReference -f $fastPackageReference)

    $path = Get-Path -Request $request
	
    Install-PackageUtility -FastPackageReference $fastPackageReference -Location $path -Request $request
}

# A helper function for install-package and save-package
function Install-PackageUtility
{ 
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FastPackageReference,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Location,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        $Request
    )


    # Check the source location
    if(-Not (Test-Path -Path $fastPackageReference))
    {
        ThrowError -ExceptionName "System.ArgumentException" `
            -ExceptionMessage ($LocalizedData.PathNotFound -f ($fastPackageReference)) `
            -ErrorId "PathNotFound" `
            -CallerPSCmdlet $CallerPSCmdlet `
            -ErrorCategory InvalidArgument `
            -ExceptionObject $fastPackageReference
    }

    # Check the destination location
    if(-Not (Test-Path -Path $Location))
    {
        New-Item -Path $Location -ItemType Directory -Force  
    }

    # Get the cmdlet parameter values that were passed from the user
    $force = $false
    $options = $request.Options
    if($options.ContainsKey('Force'))
    {
        $force = $options['Force']
    }

    Copy-Item -Path $fastPackageReference -Destination $Location -Force:$force -WhatIf:$false -Confirm:$false

    $swidObject = @{
                    FastPackageReference = $fastPackageReference;
                    Name = [System.IO.Path]::GetFileName($fastPackageReference);
                    Version = New-Object System.Version ("0.1");  # Note: You need to fill in a proper package version    
                    versionScheme  = "MultiPartNumeric";              
                    summary = "Summary of your package provider"; 
                    Source =   [System.IO.Path]::GetDirectoryName($fastPackageReference)         
                   }
    $swidTag = New-SoftwareIdentity @swidObject
    Write-Output -InputObject $swidTag    
}


# It is required to implement this function for the providers that support UnInstall-Package. 
# For example, UnInstall-Package -Name seattle -ProviderName myalbum -Destination c:\myfolder.
function UnInstall-Package
{ 
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $fastPackageReference
    )

    Write-Debug -Message ($LocalizedData.ProviderDebugMessage -f ('Uninstall-Package'))
    Write-Debug -Message ($LocalizedData.FastPackageReference -f $fastPackageReference)
            
    $fileFullName = $fastPackageReference

    if(Test-Path -Path $fileFullName)
    {
        Remove-Item $fileFullName -Force -WhatIf:$false -Confirm:$false

        $swidObject = @{
            FastPackageReference = $fileFullName;                        
            Name = [System.IO.Path]::GetFileName($fileFullName);
            Version = New-Object System.Version ("0.1");  # Note: You need to fill in a proper package version    
            versionScheme  = "MultiPartNumeric";              
            summary = "Summary of your package provider"; 
            Source =   [System.IO.Path]::GetDirectoryName($fileFullName)                             
        }

        $swidTag = New-SoftwareIdentity @swidObject
        Write-Output -InputObject $swidTag
    }	 
}


# Optional function that returns the packages that are installed. However it is required to implement this function for the providers 
# that support Get-Package. It's also called during install-package.
# For example, Get-package -Destination c:\myfolder -ProviderName MyAlbum
function Get-InstalledPackage
{ 
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [string]
        $Name,

        [Parameter()]
        [string]
        $RequiredVersion,

        [Parameter()]
        [string]
        $MinimumVersion,

        [Parameter()]
        [string]
        $MaximumVersion
    )

    Write-Debug -Message ($LocalizedData.ProviderDebugMessage -f ('Get-InstalledPackage'))
        
    #You can check the version here...
    #<your code>


    $fullPath = Get-Path -Request $request
     
     if (Test-Path -Path $fullPath)
     {
        # Find the photos
        $files = Get-ChildItem -Path $fullPath -Filter '*.png' -Recurse  | `
                        Where-Object { ($_.PSIsContainer -eq $false) -and  ( $_.Name -like "*$Name*") }
                          
                                  
        foreach($file in $files)
        {
            if($request.IsCanceled) { return }
                        
            $swidObject = @{
                FastPackageReference = $file.FullName;
                Name = $file.Name;
                Version = New-Object System.Version ("0.1"); 
                versionScheme  = "MultiPartNumeric";
                summary = "Summary of your package provider";
                Source = $file.FullName;               
            }
            $swidTag = New-SoftwareIdentity @swidObject
            Write-Output -InputObject $swidTag               
        } 
     } 
}

#endregion


#region Helper functions


# Get the package destination path
function Get-Path 
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        $Request
    )
    
    # Get the cmdlet parameter values that were passed from the user. Via Options, we can find out what's the installation path.
    $options = $Request.Options
    foreach( $o in $options.Keys )
    {
        Write-Debug ( "OPTION: {0} => {1}" -f ($o, $options[$o]) )
    }
    
    if($options -and $options.ContainsKey('Destination'))
    {        
        $path = $($options['Destination'])

        return $path
    }
}

# Test if the $Name contains any wildcard characters
function Test-WildcardPattern
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Name
    )

    return [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Name)    
}

# Find package source name from a given location
function Get-SourceName
{
    [CmdletBinding()]
    [OutputType("string")]
    Param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Location
    )

    Set-PackageSourcesVariable

    foreach($source in $script:RegisteredPackageSources.Values)
    {
        if($source.SourceLocation -eq $Location) 
        {
            return $source.Name
        }
    }
}

# Yield the package source to OneGet
function New-PackageSourceAndYield
{
    param
    (
        [Parameter(Mandatory)]
        $Source
    )
     
    # create a new package source
    $src =  New-PackageSource -Name $Source.Name `
                              -Location $Source.SourceLocation `
                              -Trusted $Source.Trusted `
                              -Registered $Source.Registered `

    Write-Verbose ( $LocalizedData.PackageSourceDetails -f ($src.Name, $src.Location, $src.IsTrusted, $src.IsRegistered) )

    # return the package source object.
    Write-Output -InputObject $src
}

# Read the registered package sources from its configuration file
function Set-PackageSourcesVariable
{
    param([switch]$Force)

    if(-not $script:RegisteredPackageSources -or $Force)
    {
        if(Microsoft.PowerShell.Management\Test-Path $script:RegisteredPackageSourcesFilePath)
        {
            $script:RegisteredPackageSources = DeSerializePSObject -Path $script:RegisteredPackageSourcesFilePath
        }
        else
        {
            $script:RegisteredPackageSources = [ordered]@{}
        }
    }   
}

# Read xml content to into an object
function DeSerializePSObject
{
    [CmdletBinding(PositionalBinding=$false)]    
    Param
    (
        [Parameter(Mandatory=$true)]        
        $Path
    )

    # You can use import-clixml here. However this cmdlet is not available on Nano Server yet, so we choose PSSerializer to
    # make the provider run on both full server and Nano Server.

    $filecontent = Microsoft.PowerShell.Management\Get-Content -Path $Path
    [System.Management.Automation.PSSerializer]::Deserialize($filecontent)    
}

# Save the package source to the configuration file
function Save-PackageSources
{
    if($script:RegisteredPackageSources)
    {
        if(-not (Microsoft.PowerShell.Management\Test-Path $script:LocalPath))
        {
            $null = Microsoft.PowerShell.Management\New-Item -Path $script:LocalPath `
                                                             -ItemType Directory `
                                                             -Force `
                                                             -ErrorAction SilentlyContinue `
                                                             -WarningAction SilentlyContinue `
                                                             -Confirm:$false -WhatIf:$false
        } 
        
        # You can use export-clixml here. However this cmdlet is not available on Nano Server yet, so we choose PSSerializer to
        # make the provider run on both full server and Nano Server.       
        Microsoft.PowerShell.Utility\Out-File `
            -FilePath $script:RegisteredPackageSourcesFilePath `
            -Force `
            -InputObject ([System.Management.Automation.PSSerializer]::Serialize($script:RegisteredPackageSources))
   }   
}


# Validate versions
function Validate-VersionParameters
{
    Param(
        [Parameter()]
        [String[]]
        $Name,

        [Parameter()]
        [string]
        $MinimumVersion,

        [Parameter()]
        [string]
        $RequiredVersion,

        [Parameter()]
        [string]
        $MaximumVersion,

        [Parameter()]
        [Switch]
        $AllVersions
    )

    
    <#       
        Add code here to validate versions
    #>

    # Once we complete the validation, return the result. As a sample here, we assume we have passed the version checking
    return $true

}

# Utility to throw an errorrecord
function ThrowError
{
    param
    (        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCmdlet]
        $CallerPSCmdlet,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]        
        $ExceptionName,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ExceptionMessage,
        
        [System.Object]
        $ExceptionObject,
        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorId,

        [parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Management.Automation.ErrorCategory]
        $ErrorCategory
    )
        
    $exception = New-Object $ExceptionName $ExceptionMessage;
    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $ErrorId, $ErrorCategory, $ExceptionObject    
    $CallerPSCmdlet.ThrowTerminatingError($errorRecord)
}

#endregion
