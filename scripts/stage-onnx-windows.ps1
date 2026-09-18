param(
    [Parameter(Mandatory = $true)]
    [string] $BuildDirectory,
    [Parameter(Mandatory = $true)]
    [string] $OutputDirectory,
    [Parameter(Mandatory = $true)]
    [ValidateSet('x64', 'arm64')]
    [string] $Architecture
)

$ErrorActionPreference = 'Stop'

# The generated copy target records the SDK root and version selected by Dawn.
[xml] $project = Get-Content -LiteralPath (Join-Path $BuildDirectory '_deps/dawn-build/third_party/copy_dxil_dll.vcxproj') -Raw
$namespaces = New-Object System.Xml.XmlNamespaceManager($project.NameTable)
$namespaces.AddNamespace('msbuild', 'http://schemas.microsoft.com/developer/msbuild/2003')
$sources = @($project.SelectNodes('//msbuild:Command', $namespaces) | ForEach-Object {
    $match = [regex]::Match($_.InnerText, '-E\s+copy_if_different\s+(?:"(?<path>[^"]+)"|(?<path>\S+))')
    if ($match.Success) {
        $match.Groups['path'].Value.Replace('\', '/')
    }
} | Sort-Object -Unique)
if ($sources.Count -ne 1) {
    throw 'Expected one Windows SDK DXIL source in the generated Dawn copy target.'
}
$sdk = [regex]::Match($sources[0], '^(?<root>.+)/bin/(?<version>[^/]+)/(?:x64|arm64)/dxil\.dll$', 'IgnoreCase')
if (!$sdk.Success -or ![IO.Path]::IsPathRooted($sources[0])) {
    throw "Invalid Windows SDK DXIL source: $($sources[0])"
}

$sdkRoot = $sdk.Groups['root'].Value
$sdkVersion = $sdk.Groups['version'].Value
$compiler = Join-Path $BuildDirectory 'Release/dxcompiler.dll'
$validator = Join-Path $sdkRoot "bin/$sdkVersion/$Architecture/dxil.dll"
$sdkLicenses = Join-Path $sdkRoot "Licenses/$sdkVersion"
$notices = @('sdk_license.rtf', 'sdk_third_party_notices.rtf')
$machine = if ($Architecture -eq 'arm64') { 0xAA64 } else { 0x8664 }

foreach ($library in @($compiler, $validator)) {
    $reader = New-Object IO.BinaryReader([IO.File]::OpenRead($library))
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Invalid Windows library: $library"
        }
        $reader.BaseStream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        if ($peOffset -lt 0x40 -or $peOffset -gt $reader.BaseStream.Length - 6) {
            throw "Invalid PE header in $library"
        }
        $reader.BaseStream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne $machine) {
            throw "Expected a $Architecture PE library: $library"
        }
    }
    finally {
        $reader.Dispose()
    }
}
foreach ($notice in $notices) {
    if ((Get-Item -LiteralPath (Join-Path $sdkLicenses $notice)).Length -eq 0) {
        throw "Empty Windows SDK notice: $notice"
    }
}

$licenseOutput = Join-Path $OutputDirectory 'licenses/toolchain/windows-sdk'
New-Item -ItemType Directory -Path $licenseOutput -Force | Out-Null
Copy-Item -LiteralPath $compiler, $validator -Destination $OutputDirectory -Force
foreach ($notice in $notices) {
    Copy-Item -LiteralPath (Join-Path $sdkLicenses $notice) -Destination $licenseOutput -Force
}
Write-Output $sdkVersion