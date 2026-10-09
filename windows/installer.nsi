; utubmp3 for Windows: installs the helper, its tools and the Chrome extension folder
; per user (no admin prompt), and starts the helper at every login.
; Built by windows/build.sh:  makensis -DVERSION=x.y -DSTAGE=<dir> -DOUTFILE=<exe> installer.nsi

Unicode true
!include "MUI2.nsh"

!define APP "utubmp3"
!define RUN_KEY "Software\Microsoft\Windows\CurrentVersion\Run"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP}"

Name "${APP}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
RequestExecutionLevel user
SetCompressor /SOLID lzma
ManifestDPIAware true

VIProductVersion "${VERSION}.0.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "FileDescription" "${APP} installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "CompanyName" "Harikanth Lingutla"
VIAddVersionKey "LegalCopyright" "MIT License"

!define MUI_ICON "utubmp3.ico"
!define MUI_UNICON "utubmp3.ico"
!define MUI_WELCOMEPAGE_TEXT "This installs utubmp3, which saves the audio of a YouTube video as a tagged MP3 from a button in Chrome or Edge.$\r$\n$\r$\nA small helper runs in the background and starts when you sign in. MP3s are saved to your Downloads folder.$\r$\n$\r$\nOnly download content you have the rights to."
!define MUI_FINISHPAGE_TITLE "Now add the extension to your browser"
!define MUI_FINISHPAGE_TEXT "The helper is running. To finish, add the extension once:$\r$\n$\r$\n1. Open chrome://extensions (or edge://extensions in Edge).$\r$\n2. Turn on Developer mode.$\r$\n3. Click Load unpacked and choose the extension folder (opened for you below).$\r$\n$\r$\nThen open any YouTube video and click $\"⬇ MP3$\"."
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Open the extension folder"
!define MUI_FINISHPAGE_RUN_FUNCTION OpenExtensionFolder
!define MUI_FINISHPAGE_NOREBOOTSUPPORT

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function OpenExtensionFolder
    ExecShell "open" "$INSTDIR\extension"
FunctionEnd

; Stops a running helper so its files can be replaced or removed.
!macro StopHelper
    nsExec::Exec '"$SYSDIR\taskkill.exe" /F /IM ${APP}.exe'
    Pop $0
    Sleep 500
!macroend

Section "Install"
    !insertmacro StopHelper
    SetOutPath "$INSTDIR"
    File "${STAGE}\${APP}.exe"
    File "${STAGE}\ffmpeg.exe"
    File "${STAGE}\qjs.exe"
    File "utubmp3.ico"
    ; Replace the extension folder wholesale so files removed in an update don't linger.
    ; Chrome keeps the loaded extension pointed at this same path.
    RMDir /r "$INSTDIR\extension"
    SetOutPath "$INSTDIR\extension"
    File /r "${STAGE}\extension\*.*"
    SetOutPath "$INSTDIR"

    WriteUninstaller "$INSTDIR\uninstall.exe"
    WriteRegStr HKCU "${RUN_KEY}" "${APP}" '"$INSTDIR\${APP}.exe" --background'

    CreateDirectory "$SMPROGRAMS\${APP}"
    CreateShortcut "$SMPROGRAMS\${APP}\${APP}.lnk" "$INSTDIR\${APP}.exe" "" "$INSTDIR\utubmp3.ico"
    CreateShortcut "$SMPROGRAMS\${APP}\${APP} extension folder.lnk" "$INSTDIR\extension"

    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP}"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "Harikanth Lingutla"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "https://github.com/harikanthl/utubmp3"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\utubmp3.ico"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" 20000

    Exec '"$INSTDIR\${APP}.exe" --background'
SectionEnd

Section "Uninstall"
    !insertmacro StopHelper
    DeleteRegValue HKCU "${RUN_KEY}" "${APP}"
    DeleteRegKey HKCU "${UNINSTALL_KEY}"
    RMDir /r "$SMPROGRAMS\${APP}"
    RMDir /r "$INSTDIR"
    ; yt-dlp and the log. Downloaded MP3s stay in Downloads.
    RMDir /r "$LOCALAPPDATA\${APP}"
SectionEnd
