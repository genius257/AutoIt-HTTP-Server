#include <Array.au3>
#include <NamedPipes.au3>
#include <WinAPI.au3>
#include <WinAPIProc.au3>
#include <WinAPIFiles.au3>

#Region // OPTIONS HERE //
Local $sRootDir = @ScriptDir & "\www" ; The absolute path to the root directory of the server.
;~ Local $sIP = @IPAddress1 ; ip address as defined by AutoIt
;~ Local $sIP = "127.0.0.1"
Local $sIP = "0.0.0.0";	http://localhost/ and more
Local $iPort = 80 ; the listening port
Local $sServerAddress = "http://" & $sIP & ":" & $iPort & "/"
Local $iMaxUsers =  Int(IniRead("settings.ini", "core", "MaxUsers", 15)); Maximum number of users who can simultaneously get/post
Local $sServerName = "AutoIt HTTP Server/0.1a (" & @OSVersion & ") AutoIt " & @AutoItVersion
Local $DirectoryIndex=IniRead("settings.ini", "core", "DirectoryIndex", "index.html")

Local $PHP_Path = IniRead("settings.ini", "PHP", "PHP_Path", "")
Local $bAllowIndexes=IniRead("settings.ini", "PHP", "AllowIndexes", False)
#EndRegion // END OF OPTIONS //

If $iMaxUsers<1 Then Exit MsgBox(0x10, "AutoIt HTTP Sever", "MaxUsers is less than one."&@CRLF&"The server will now close")
If $DirectoryIndex = "" Then $DirectoryIndex = "index.html"

If Not ($PHP_Path="") Then
	$PHP_Path=_WinAPI_GetFullPathName($PHP_Path&"\")
	If Not FileExists($PHP_Path&"php-cgi.exe") Then $PHP_Path=""
EndIf
If IsString($bAllowIndexes) Then $bAllowIndexes=((StringLower($bAllowIndexes)=="true")?True : False)
If $PHP_Path = "" Then $bAllowIndexes = False

Local $aSocket[$iMaxUsers] ; Creates an array to store all the possible users
Local $sBuffer[$iMaxUsers] ; All these users have buffers when sending/receiving, so we need a place to store those

For $x = 0 to UBound($aSocket)-1 ; Fills the entire socket array with -1 integers, so that the server knows they are empty.
    $aSocket[$x] = -1
Next

TCPStartup() ; AutoIt needs to initialize the TCP functions

$iMainSocket = TCPListen($sIP,$iPort) ;create main listening socket
If @error Then ; if you fail creating a socket, exit the application
    MsgBox(0x20, "AutoIt Webserver", "Unable to create a socket on port " & $iPort & ".") ; notifies the user that the HTTP server will not run
    Exit ; if your server is part of a GUI that has nothing to do with the server, you'll need to remove the Exit keyword and notify the user that the HTTP server will not work.
EndIf

ConsoleWrite( "Server created on " & $sServerAddress & @CRLF) ; If you're in SciTE,

While 1
    $iNewSocket = TCPAccept($iMainSocket) ; Tries to accept incoming connections

    If $iNewSocket >= 0 Then ; Verifies that there actually is an incoming connection
        For $x = 0 to UBound($aSocket)-1 ; Attempts to store the incoming connection
            If $aSocket[$x] = -1 Then
                $aSocket[$x] = $iNewSocket ;store the new socket
                ExitLoop
            EndIf
        Next
    EndIf

    For $x = 0 to UBound($aSocket)-1 ; A big loop to receive data from everyone connected
        If $aSocket[$x] = -1 Then ContinueLoop ; if the socket is empty, it will continue to the next iteration, doing nothing
        $sNewData = TCPRecv($aSocket[$x],1024) ; Receives a whole lot of data if possible
        If @error Then ; Client has disconnected
            $aSocket[$x] = -1 ; Socket is freed so that a new user may join
            ContinueLoop ; Go to the next iteration of the loop, not really needed but looks oh so good
        Else ; data received
            $sBuffer[$x] &= $sNewData ;store it in the buffer
            If StringInStr(StringStripCR($sBuffer[$x]),@LF&@LF) Then ; if the request has ended ..
                $sFirstLine = StringLeft($sBuffer[$x],StringInStr($sBuffer[$x],@LF)) ; helps to get the type of the request
                $sRequestType = StringLeft($sFirstLine,StringInStr($sFirstLine," ")-1) ; gets the type of the request
                If $sRequestType = "HEAD" Then
					;TODO
				ElseIf $sRequestType = "GET" Then ; user wants to download a file or whatever ..
                    $sRequest = StringTrimRight(StringTrimLeft($sFirstLine,4),11) ; let's see what file he actually wants
					If StringInStr(StringReplace($sRequest,"\","/"), "/.") Then ; Disallow any attempts to go back a folder
						_HTTP_SendFileNotFoundError($aSocket[$x]) ; sends back an error
					Else
						$sRequest = _URIDecode($sRequest)

						$QUERY_STRING = StringInStr($sRequest, "?")>0 ? StringMid($sRequest, StringInStr($sRequest, "?")+1) : ""
						$sRequest = StringMid($sRequest, 1, StringInStr($sRequest, "?")-1)
;~ 						If $sRequest = "/" Then ; user has requested the root
						$sLocalPath = _WinAPI_GetFullPathName($sRootDir & "\" & StringReplace($sRequest,"/","\"));TODO: replace every instance of ($sRootDir & "\" & $sRequest) with $sLocalPath
						ConsoleWrite($sLocalPath&@CRLF)
						If StringInStr(FileGetAttrib($sRootDir & "\" & StringReplace($sRequest,"/","\")),"D")>0 Then ; user has requested a directory
							Local $iStart=1
							Local $iEnd=StringInStr($DirectoryIndex, ",")-$iStart
							Local $sIndex
							Local $_sRequest=StringReplace($sRequest,"/","\")
							If Not (StringRight($_sRequest, 1)="\") Then $_sRequest &= "\"
							While 1
								$sIndex=StringMid($DirectoryIndex, $iStart, $iEnd)
								If FileExists($sRootDir & "\" & $_sRequest & $sIndex ) Then ExitLoop
								If $iEnd<1 Then ExitLoop
								$iStart=$iStart+$iEnd+1
								$iEnd=StringInStr($DirectoryIndex, ",", 0, 1, $iStart)
								$iEnd=$iEnd>0?$iEnd-$iStart:$iEnd-1
							WEnd
;~ 							$sRequest = "/index.html" ; instead of root we'll give him the index page
;~ 							$sRequest = "/"&$sIndex
;~ 							$_sRequest  & "\" & $sIndex
;~ 							$sRequest = $_sRequest & "\" & $sIndex
							$sRequest = $_sRequest & $sIndex
							If Not FileExists($sRootDir & "\" & $sRequest) Then
								If $bAllowIndexes And FileExists(@ScriptDir & "\index.php") Then
									Local $hReadPipe, $hWritePipe
									Local $STARTF_USESTDHANDLES = 0x100
									; Set up security attributes
									$tSecurity = DllStructCreate($tagSECURITY_ATTRIBUTES)
									DllStructSetData($tSecurity, "Length", DllStructGetSize($tSecurity))
									DllStructSetData($tSecurity, "InheritHandle", True)
									_NamedPipes_CreatePipe($hReadPipe, $hWritePipe, $tSecurity)
									$tProcess = DllStructCreate($tagPROCESS_INFORMATION)
									$tStartup = DllStructCreate($tagSTARTUPINFO)
									DllStructSetData($tStartup, "Size", DllStructGetSize($tStartup))
									DllStructSetData($tStartup, "Flags", $STARTF_USESTDHANDLES)
									DllStructSetData($tStartup, "StdOutput", $hWritePipe)
									DllStructSetData($tStartup, "StdError", $hWritePipe)

;~ 									Local $tSockaddr = DllStructCreate("ushort sa_family;char sa_data[14];")
									Local $tSockaddr = DllStructCreate("short;ushort;uint;char[8]")
									Local $aRet = DllCall("Ws2_32.dll", "int", "getpeername", "int", $aSocket[$x], "ptr", DllStructGetPtr($tSockaddr), "int*", DllStructGetSize($tSockaddr))
									Local $aRet = DllCall("Ws2_32.dll", "str", "inet_ntoa", "int", DllStructGetData($tSockaddr, 3))

									$sEnviroment="SCRIPT_NAME="&StringMid($sRequest,StringInStr($sRequest, "\", 0, -1)+1)&Chr(0)& _
									"REMOTE_ADDR="&$aRet[0]&Chr(0)& _
									"REQUESTED_METHOD=GET"&Chr(0)& _
									"REQUEST_URI="&StringTrimRight(StringTrimLeft($sFirstLine,4),11)&Chr(0)& _
									"QUERY_STRING="&Chr(0)& _
									Chr(0);missing: USER_AGENT, REFERER, SERVER_PROTOCOL
									$tEnviroment=DllStructCreate("WCHAR["&StringLen($sEnviroment)&"]")
									DllStructSetData($tEnviroment, 1, $sEnviroment)
									ConsoleWrite($sRootDir&@CRLF)
									_WinAPI_CreateProcess(@ScriptDir&"\php-7.2.0RC4-nts-Win32-VC15-x86\php-cgi.exe", " -f """ & @ScriptDir & "\index.php" & """", Null, Null, True, $CREATE_NO_WINDOW+$NORMAL_PRIORITY_CLASS+$CREATE_UNICODE_ENVIRONMENT, DllStructGetPtr($tEnviroment), $sRootDir, DllStructGetPtr($tStartup), DllStructGetPtr($tProcess))

									Local $hProcess = DllStructGetData($tProcess, "hProcess")
									_WinAPI_CloseHandle(DllStructGetData($tProcess, "hThread"))
;~ 										Local $tBuffer = DllStructCreate("wchar Text[4096]")
										Local $tBuffer = DllStructCreate("char Text[4096]")
										Local $pBuffer = DllStructGetPtr($tBuffer)
										Local $iBytes
										Local $bData
										Local $a
										Local $STILL_ACTIVE = 0x103

										Local $sPacket = Binary("HTTP/1.1 200 OK" & @CRLF & _
											"Server: " & $sServerName & @CRLF & _
											"Connection: close" & @CRLF & _
											"Content-Type: text/html; charset=UTF-8" & @CRLF & _
											"Transfer-Encoding: chunked" & @CRLF & @CRLF )
											TCPSend($aSocket[$x],$sPacket) ; Send start of packet

										_WinAPI_CloseHandle($hWritePipe)
										While 1
											If Not _WinAPI_ReadFile($hReadPipe, $pBuffer, 4096, $iBytes) Then ExitLoop
											If $iBytes>0 Then
;~ 												$bData = Binary(StringRegExpReplace(Hex($iBytes), "^0+", "")&@CRLF& StringLeft(DllStructGetData($tBuffer, "Text"), $iBytes / 2) &@CRLF)
												$bData = Binary(StringRegExpReplace(Hex($iBytes), "^0+", "")&@CRLF& StringLeft(DllStructGetData($tBuffer, "Text"), $iBytes) &@CRLF)
												While BinaryLen($bData) ; Send data in chunks (most code by Larry)
													$a = TCPSend($aSocket[$x], $bData) ; TCPSend returns the number of bytes sent
													$bData = BinaryMid($bData, $a+1, BinaryLen($bData)-$a)
												WEnd
											EndIf
										WEnd
										$sPacket = Binary("0"&@CRLF&@CRLF) ; Finish the packet
										TCPSend($aSocket[$x],$sPacket)
										TCPCloseSocket($aSocket[$x])
									_WinAPI_CloseHandle($hProcess)
									_WinAPI_CloseHandle($hReadPipe)
								Else
									_HTTP_SendHTML($aSocket[$x], "403 Forbidden", "403 Forbidden")
								EndIf
								$sBuffer[$x] = "" ; clears the buffer because we just used to buffer and did some actions based on them
								$aSocket[$x] = -1 ; the socket is automatically closed so we reset the socket so that we may accept new clients
								ContinueLoop
							EndIf
;~ 							ConsoleWrite($_sRequest & "\" & $sIndex)
						EndIf
						$sRequest = StringReplace($sRequest,"/","\") ; convert HTTP slashes to windows slashes, not really required because windows accepts both
						If FileExists($sRootDir & "\" & $sRequest) Then ; makes sure the file that the user wants exists
;~ 							$sFileType = StringRight($sRequest,4) ; determines the file type, so that we may choose what mine type to use
							$iFileType = StringInStr($sRequest, ".", 0, -1)
							$sFileType = $iFileType>0 ? StringMid($sRequest,$iFileType+1) : ""
							Switch $sFileType
								Case "html", "htm" ; in case of normal HTML files
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "text/html")
								Case "css" ; in case of style sheets
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "text/css")
								Case "jpg", "jpeg" ; for common images
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "image/jpeg")
								Case "png" ; another common image format
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "image/png")
								Case "ico"
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "image/ico")
								Case "gif"
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "image/gif")
								Case "bmp"
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "image/bmp")
								Case "css"
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "text/css")
								Case "js"
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "text/javascript")
								Case "json"
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "application/json")
								Case "txt"
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "text/plain")
								Case "php"
									If $PHP_Path = "" Then ContinueCase;if php path is not set, it will default to the "Case Else"
									Local $hReadPipe, $hWritePipe
									Local $STARTF_USESTDHANDLES = 0x100
									; Set up security attributes
									$tSecurity = DllStructCreate($tagSECURITY_ATTRIBUTES)
									DllStructSetData($tSecurity, "Length", DllStructGetSize($tSecurity))
									DllStructSetData($tSecurity, "InheritHandle", True)
									_NamedPipes_CreatePipe($hReadPipe, $hWritePipe, $tSecurity)
									$tProcess = DllStructCreate($tagPROCESS_INFORMATION)
									$tStartup = DllStructCreate($tagSTARTUPINFO)
									DllStructSetData($tStartup, "Size", DllStructGetSize($tStartup))
									DllStructSetData($tStartup, "Flags", $STARTF_USESTDHANDLES)
									DllStructSetData($tStartup, "StdOutput", $hWritePipe)
									DllStructSetData($tStartup, "StdError", $hWritePipe)

;~ 									Local $tSockaddr = DllStructCreate("ushort sa_family;char sa_data[14];")
									Local $tSockaddr = DllStructCreate("short;ushort;uint;char[8]")
									Local $aRet = DllCall("Ws2_32.dll", "int", "getpeername", "int", $aSocket[$x], "ptr", DllStructGetPtr($tSockaddr), "int*", DllStructGetSize($tSockaddr))
									Local $aRet = DllCall("Ws2_32.dll", "str", "inet_ntoa", "int", DllStructGetData($tSockaddr, 3))

									$sEnviroment="SCRIPT_NAME="&StringMid($sRequest,StringInStr($sRequest, "\", 0, -1)+1)&Chr(0)& _
									"REMOTE_ADDR="&$aRet[0]&Chr(0)& _
									"REQUESTED_METHOD=GET"&Chr(0)& _
									"REQUEST_URI="&StringTrimRight(StringTrimLeft($sFirstLine,4),11)&Chr(0)& _
									"QUERY_STRING="&$QUERY_STRING&Chr(0)& _
									Chr(0);missing: USER_AGENT, REFERER, SERVER_PROTOCOL
									$tEnviroment=DllStructCreate("WCHAR["&StringLen($sEnviroment)&"]")
									DllStructSetData($tEnviroment, 1, $sEnviroment)
									_WinAPI_CreateProcess(@ScriptDir&"\php-7.2.0RC4-nts-Win32-VC15-x86\php-cgi.exe", " -f """ & $sRootDir & $sRequest & """ " & $QUERY_STRING, Null, Null, True, $CREATE_NO_WINDOW+$NORMAL_PRIORITY_CLASS+$CREATE_UNICODE_ENVIRONMENT, DllStructGetPtr($tEnviroment), $sRootDir, DllStructGetPtr($tStartup), DllStructGetPtr($tProcess))

									Local $hProcess = DllStructGetData($tProcess, "hProcess")
									_WinAPI_CloseHandle(DllStructGetData($tProcess, "hThread"))
;~ 										Local $tBuffer = DllStructCreate("wchar Text[4096]")
										Local $tBuffer = DllStructCreate("char Text[4096]")
										Local $pBuffer = DllStructGetPtr($tBuffer)
										Local $iBytes
										Local $bData
										Local $a
										Local $STILL_ACTIVE = 0x103

										Local $sPacket = Binary("HTTP/1.1 200 OK" & @CRLF & _
											"Server: " & $sServerName & @CRLF & _
											"Connection: close" & @CRLF & _
											"Content-Type: text/html; charset=UTF-8" & @CRLF & _
											"Transfer-Encoding: chunked" & @CRLF & @CRLF )
											TCPSend($aSocket[$x],$sPacket) ; Send start of packet

										_WinAPI_CloseHandle($hWritePipe)
										While 1
											If Not _WinAPI_ReadFile($hReadPipe, $pBuffer, 4096, $iBytes) Then ExitLoop
											If $iBytes>0 Then
;~ 												$bData = Binary(StringRegExpReplace(Hex($iBytes), "^0+", "")&@CRLF& StringLeft(DllStructGetData($tBuffer, "Text"), $iBytes / 2) &@CRLF)
												$bData = Binary(StringRegExpReplace(Hex($iBytes), "^0+", "")&@CRLF& StringLeft(DllStructGetData($tBuffer, "Text"), $iBytes) &@CRLF)
												While BinaryLen($bData) ; Send data in chunks (most code by Larry)
													$a = TCPSend($aSocket[$x], $bData) ; TCPSend returns the number of bytes sent
													$bData = BinaryMid($bData, $a+1, BinaryLen($bData)-$a)
												WEnd
											EndIf
										WEnd
										$sPacket = Binary("0"&@CRLF&@CRLF) ; Finish the packet
										TCPSend($aSocket[$x],$sPacket)
										TCPCloseSocket($aSocket[$x])
									_WinAPI_CloseHandle($hProcess)
									_WinAPI_CloseHandle($hReadPipe)
								Case Else ; this is for .exe, .zip, or anything else that is not supported is downloaded to the client using a application/octet-stream
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "application/octet-stream")
							EndSwitch
						Else
;~ 							ConsoleWrite("404: "&$sRequest&@CRLF)
							_HTTP_SendFileNotFoundError($aSocket[$x]) ; File does not exist, so we'll send back an error..
						EndIf
					EndIf
                ElseIf $sRequestType = "POST" Then ; user has come to us with data, we need to parse that data and based on that do something special
					;TODO
;~ 					ConsoleWrite("$sBuffer[$x]: "&$sBuffer[$x]&@CRLF)

                    $aPOST = _HTTP_GetPost($sBuffer[$x]) ; parses the post data

                    $sComment = _HTTP_POST("wintext",$aPOST) ; Like PHPs _POST, but it requires the second parameter to be the return value from _Get_Post

                    _HTTP_ConvertString($sComment) ; Needs to convert the POST HTTP string into a normal string

;~                     ConsoleWrite($sComment)

					$data = FileRead($sRootDir & "\template.html")
					$data = StringReplace($data, "<?au3 Replace me ?>", $sComment)

					$h = FileOpen($sRootDir & "\index.html", 2)
                    FileWrite($h, $data)
					FileClose($h)

					$h = FileOpen($sRootDir & "\clean.html", 2)
					FileWrite($h, $sComment)
					FileClose($h)

                    _HTTP_SendFile($aSocket[$x], $sRootDir & "\index.html", "text/html") ; Sends back the new file we just created
				Else
;~ 					ConsoleWrite("501"&@CRLF)
					_HTTP_SendHTML($aSocket[$x], "", "501 Not Implemented")
                EndIf

                $sBuffer[$x] = "" ; clears the buffer because we just used to buffer and did some actions based on them
                $aSocket[$x] = -1 ; the socket is automatically closed so we reset the socket so that we may accept new clients

            EndIf
        EndIf
    Next

    Sleep(10)
WEnd

Func _HTTP_ConvertString(ByRef $sInput) ; converts any characters like %20 into space 8)
    $sInput = StringReplace($sInput, '+', ' ')
    StringReplace($sInput, '%', '')
    For $t = 0 To @extended
        $Find_Char = StringLeft( StringTrimLeft($sInput, StringInStr($sInput, '%')) ,2)
        $sInput = StringReplace($sInput, '%' & $Find_Char, Chr(Dec($Find_Char)))
    Next
EndFunc

Func _HTTP_SendHTML($hSocket, $sHTML, $sReply = "200 OK") ; sends HTML data on X socket
    _HTTP_SendData($hSocket, Binary($sHTML), "text/html", $sReply)
EndFunc

Func _HTTP_SendFile($hSocket, $sFileLoc, $sMimeType, $sReply = "200 OK") ; Sends a file back to the client on X socket, with X mime-type
    Local $hFile, $sImgBuffer, $sPacket, $a

    $hFile = FileOpen($sFileLoc,16)
    $bFileData = FileRead($hFile)
    FileClose($hFile)

    _HTTP_SendData($hSocket, $bFileData, $sMimeType, $sReply)
EndFunc

Func _HTTP_SendData($hSocket, $bData, $sMimeType, $sReply = "200 OK")
	$sPacket = Binary("HTTP/1.1 " & $sReply & @CRLF & _
    "Server: " & $sServerName & @CRLF & _
	"Connection: close" & @CRLF & _
	"Content-Lenght: " & BinaryLen($bData) & @CRLF & _
    "Content-Type: " & $sMimeType & "; charset=UTF-8" & @CRLF & _
    @CRLF)
    TCPSend($hSocket,$sPacket) ; Send start of packet

    While BinaryLen($bData) ; Send data in chunks (most code by Larry)
        $a = TCPSend($hSocket, $bData) ; TCPSend returns the number of bytes sent
        $bData = BinaryMid($bData, $a+1, BinaryLen($bData)-$a)
    WEnd

;~     $sPacket = Binary(@CRLF & @CRLF) ; Finish the packet
;~     TCPSend($hSocket,$sPacket)

	TCPCloseSocket($hSocket)
EndFunc

Func _HTTP_SendFileNotFoundError($hSocket) ; Sends back a basic 404 error
	Local $s404Loc = $sRootDir & "\404.html"
	If (FileExists($s404Loc)) Then
		_HTTP_SendFile($hSocket, $s404Loc, "text/html")
	Else
		_HTTP_SendHTML($hSocket, "404 Error: " & @CRLF & @CRLF & "The file you requested could not be found.", "404 Not Found")
	EndIf
EndFunc

Func _HTTP_GetPost($s_Buffer) ; parses incoming POST data
    Local $sTempPost, $sLen, $sPostData, $sTemp

    ; Get the lenght of the data in the POST
    $sTempPost = StringTrimLeft($s_Buffer,StringInStr($s_Buffer,"Content-Length:"))
    $sLen = StringTrimLeft($sTempPost,StringInStr($sTempPost,": "))

    ; Create the base struck
    $sPostData = StringSplit(StringRight($s_Buffer,$sLen),"&")

    Local $sReturn[$sPostData[0]+1][2]

    For $t = 1 To $sPostData[0]
        $sTemp = StringSplit($sPostData[$t],"=")
        If $sTemp[0] >= 2 Then
            $sReturn[$t][0] = $sTemp[1]
            $sReturn[$t][1] = $sTemp[2]
        EndIf
    Next

    Return $sReturn
EndFunc

Func _HTTP_Post($sName,$sArray) ; Returns a POST variable like a associative array.
    For $i = 1 to UBound($sArray)-1
        If $sArray[$i][0] = $sName Then
            Return $sArray[$i][1]
        EndIf
    Next
    Return ""
EndFunc

Func _URIEncode($sData)
    ; Prog@ndy
    Local $aData = StringSplit(BinaryToString(StringToBinary($sData,4),1),"")
    Local $nChar
    $sData=""
    For $i = 1 To $aData[0]
        ; ConsoleWrite($aData[$i] & @CRLF)
        $nChar = Asc($aData[$i])
        Switch $nChar
            Case 45, 46, 48 To 57, 65 To 90, 95, 97 To 122, 126
                $sData &= $aData[$i]
            Case 32
                $sData &= "+"
            Case Else
                $sData &= "%" & Hex($nChar,2)
        EndSwitch
    Next
    Return $sData
EndFunc;https://www.autoitscript.com/forum/topic/95850-url-encoding/?do=findComment&comment=689060
Func _URIDecode($sData)
    ; Prog@ndy
    Local $aData = StringSplit(StringReplace($sData,"+"," ",0,1),"%")
    $sData = ""
    For $i = 2 To $aData[0]
        $aData[1] &= Chr(Dec(StringLeft($aData[$i],2))) & StringTrimLeft($aData[$i],2)
    Next
    Return BinaryToString(StringToBinary($aData[1],1),4)
EndFunc;https://www.autoitscript.com/forum/topic/95850-url-encoding/?do=findComment&comment=689060