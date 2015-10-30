$DestiantionPath = "$env:tmp\MyAlbumTests\InstallPackage"
$SavePath = "$env:tmp\MyAlbumTests\ForSavePackage"


Describe "MyAlblum Test Cases" -Tags @('BVT', 'DRT') {

    BeforeAll {

        # Make sure that Pester testing tool is installed and loaded
        Find-Module Pester  | Install-Module Pester
        Import-Module Pester

        # Make sure that my provider is loaded
        Import-PackageProvider myalbum
        $modulePath = Get-Module -Name "MyAlbum" -ListAvailable
        $LocalRepositoryPath  = Join-Path $modulePath.ModuleBase -ChildPath "Test\Localrepository"
               
        if(Test-Path -Path $LocalRepositoryPath)
        {
            Register-PackageSource -Name album -ProviderName myalbum -Location $LocalRepositoryPath -ErrorAction SilentlyContinue
        }
        else
        {
            throw "Path $LocalRepositoryPath does not exist"
        }
    }
    
    AfterAll {
        UnRegister-PackageSource -Name album -ProviderName myalbum

        if( test-path $DestiantionPath ) {
            rmdir -recurse -force $DestiantionPath -ea silentlycontinue
        }

        if( test-path $SavePath ) {
            rmdir -recurse -force $SavePath -ea silentlycontinue
        }
    }


    It "Find-Package -Source parameter, Expect succeed" {

        $results = Find-Package -Source 'Album' 

        $results.Name -contains  "Seattle.png" | should be $true
        $results.Name -contains  "Happy.png" | should be $true
        $results.Name -contains  "Nice.png" | should be $true
    }

    It "Find-Package -Name parameter, Expect succeed" {

        $results = Find-Package -Source 'Album' -Name 'Seattle'

        $results.Name -contains  "Seattle.png" | should be $true
        $results.Name -contains  "Happy.png" | should be $false

    }
    
    It "Install-UnInstall-Package, Expect succeed" {
        $a = (Install-Package -Name Nice -RequiredVersion 1.0 -Destination $DestiantionPath -source album -force).name 
        $a | should match "Nice"

        $results = Get-Package -Destination $DestiantionPath
        $results.Name -contains  "Nice.png" | should be $true

        UnInstall-Package -Name Nice -Destination $DestiantionPath 
        $results = Get-Package -Destination $DestiantionPath -ErrorAction SilentlyContinue
        $results.Count -eq 0 | should be $true
    }



    It "Save-Package, Expect succeed" {

        if(-not (Test-Path -Path $SavePath))
        {
            New-Item -Path $SavePath -ItemType Directory -Force 
        }

        $a = (Save-Package -Name Nice -Source Album -Path $SavePath -force).name 
        $a | should match "Nice"
    }
           
 }


 Describe "MyAlblum Error Cases" -Tags @('BVT', 'DRT') {

    BeforeAll {

        # Make sure that my provider is loaded
        Import-PackageProvider myalbum
       
    }
    
    It "Find-Package -Source parameter, Expect succeed" {

        $results = Find-Package -Source 'DONOTEXIST' -ErrorAction SilentlyContinue -ErrorVariable theError
        $theError.FullyQualifiedErrorId | should be "SourceNotFound,Microsoft.PowerShell.PackageManagement.Cmdlets.FindPackage"
    }
  }
