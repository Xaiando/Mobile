; The Windows installer, built with Inno Setup 6 from the release build:
;
;   flutter build windows --release
;   iscc /DAppVersion=0.2.0 windows\installer\sommelier.iss
;
; It installs for the current user, so it needs no administrator rights,
; and writes build\installer\SommelierStudyCompanion-<version>-setup.exe.
; The learner's data lives in %APPDATA%\Xaiando\Sommelier Study Companion
; and survives uninstalling and upgrading.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "Sommelier Study Companion"
#define AppExe "sommelier.exe"
#define Release "..\..\build\windows\x64\runner\Release"

[Setup]
; Never change the AppId: Windows recognises upgrades by it.
AppId={{86D997EA-A9A0-4C02-ACA9-CC322A05F777}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Xaiando
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\installer
OutputBaseFilename=SommelierStudyCompanion-{#AppVersion}-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
