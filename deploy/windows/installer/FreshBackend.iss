; Installs a new local backend. The PowerShell installer creates and verifies the
; databases, realm, API and Windows services after checking the package manifest.
#ifndef Package
  #error Package is required
#endif
#ifndef Delivery
  #error Delivery is required
#endif

[Setup]
AppId=PromalzaBackendFreshInstall
AppName=PROMALZA Backend - Instalacion nueva
AppVersion=2026.10.23.4
AppPublisher=PROMALZA
VersionInfoDescription=Instalacion nueva del backend PROMALZA
DefaultDirName={autopf}\PROMALZA\FreshInstaller
DisableDirPage=yes
DisableProgramGroupPage=yes
UsePreviousAppDir=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
Uninstallable=no
CreateUninstallRegKey=no
CloseApplications=no
RestartApplications=no
SetupLogging=yes
InfoAfterFile=PASOS-DESPUES-DE-INSTALAR.txt
Compression=zip
SolidCompression=no
OutputDir={#Delivery}
OutputBaseFilename=Instalar-Promalza-Desde-Cero
WizardStyle=modern

[Languages]
Name: spanish; MessagesFile: compiler:Languages\Spanish.isl

[Files]
Source: "{#Package}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion uninsneveruninstall
Source: "PASOS-DESPUES-DE-INSTALAR.txt"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall
Source: "Guia-instalacion-PROMALZA-cliente.pdf"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall

[Messages]
spanish.WelcomeLabel2=Instala PostgreSQL, Keycloak y la API en un equipo sin instalacion previa. Se abrirá una consola para introducir el dominio HTTPS del portal y las credenciales iniciales. El tunel de Cloudflare requiere configuracion posterior.

[Code]
var
  BackendVerified: Boolean;
  BackendExitCode: Integer;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Arguments: String;
begin
  if CurStep = ssPostInstall then begin
    WizardForm.StatusLabel.Caption := 'Instalando y verificando PostgreSQL, Keycloak y la API. Complete la consola de PROMALZA.';
    Arguments := '-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "' + ExpandConstant('{app}\Instalar.ps1') + '"';
    if ExpandConstant('{param:RESUME|0}') = '1' then
      Arguments := Arguments + ' -Resume';
    BackendVerified := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      Arguments, ExpandConstant('{app}'), SW_SHOWNORMAL, ewWaitUntilTerminated, BackendExitCode);
    BackendVerified := BackendVerified and (BackendExitCode = 0);
    if not BackendVerified then
      Log('Fresh backend installation NOT verified. Files retained for diagnosis and resume. Exit=' + IntToStr(BackendExitCode));
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then begin
    if BackendVerified then begin
      WizardForm.FinishedHeadingLabel.Caption := 'Backend instalado y verificado';
      WizardForm.FinishedLabel.Caption := 'PostgreSQL, Keycloak, API e inicio de sesion comprobados. Para conectar el portal, configure el tunel de Cloudflare y compruebe API_ORIGIN y los secretos Service Auth del Worker. Lea LEEME-INSTALACION-NUEVA.md.';
    end else begin
      WizardForm.FinishedHeadingLabel.Caption := 'Instalacion NO completada';
      WizardForm.FinishedLabel.Caption := 'La instalacion o la verificacion fallo. Los archivos se han conservado en Program Files\PROMALZA\FreshInstaller; consulte los registros. Para reanudar una instalacion interrumpida, ejecute este EXE con /RESUME=1.';
    end;
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  if BackendVerified then Result := 0 else Result := 4;
end;
