#include "Server.au3"

Opt("WinWaitDelay", 10)
Opt("GUIOnEventMode", 1)
Opt("TrayAutoPause", 0)
Opt("TrayOnEventMode", 1)
Opt("TrayMenuMode", 2+8)

;TODO: add server gui

LoadSettings()

;Setup tray menu items
Global Const $iTrayItemPause = 4
Global Const $iTrayItemExit = 3
Global Const $iTrayItemBrowser = TrayCreateItem("Open in browser")
Global Const $iTrayItemReload = TrayCreateItem("Reload settings")
TrayItemSetText($iTrayItemPause, "Pause")
TrayItemSetText($iTrayItemExit, "Exit")

TrayItemSetOnEvent($iTrayItemBrowser, "OpenInBrowser")
TrayItemSetOnEvent($iTrayItemReload, "LoadSettings")

Func OpenInBrowser()
    ShellExecute("http://localhost:"&$iPort&"/")
EndFunc

Func LoadSettings()
    $sIP = IniRead("settings.ini", "core", "IP", $sIP);	http://localhost/ and more
    $iPort = Int(IniRead("settings.ini", "core", "Port", $iPort)); the listening port
    $iMaxUsers =  Int(IniRead("settings.ini", "core", "MaxUsers", $iMaxUsers)); Maximum number of users who can simultaneously get/post
    $DirectoryIndex=IniRead("settings.ini", "core", "DirectoryIndex", $DirectoryIndex)
    $bAllowIndexes=IniRead("settings.ini", "core", "AllowIndexes", $bAllowIndexes)

    $PHP_Path = IniRead("settings.ini", "PHP", "Path", $PHP_Path)
    $AU3_Path = IniRead("settings.ini", "AU3", "Path", $AU3_Path)

    If $iMaxUsers<1 Then Exit MsgBox(0x10, "AutoIt HTTP Sever", "MaxUsers is less than one."&@CRLF&"The server will now close")
    If $DirectoryIndex = "" Then $DirectoryIndex = "index.html"

    If Not ($PHP_Path="") Then
        $PHP_Path=_WinAPI_GetFullPathName($PHP_Path&"\")
        If Not FileExists($PHP_Path&"php-cgi.exe") Then $PHP_Path=""
    EndIf

    If Not ($AU3_Path="") Then
        $AU3_Path=_WinAPI_GetFullPathName($AU3_Path&"\")
        If Not FileExists($AU3_Path&"AutoIt3.exe") Then $AU3_Path=""
    EndIf

    If IsString($bAllowIndexes) Then $bAllowIndexes=((StringLower($bAllowIndexes)=="true")?True : False)
EndFunc

_HTTP_Server_Start()
