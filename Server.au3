#include <Array.au3>
#include <NamedPipes.au3>
#include <WinAPI.au3>
#include <WinAPIProc.au3>
#include <WinAPIFiles.au3>
#include <Date.au3>
#include <String.au3>

Opt("WinWaitDelay", 10)
Opt("TCPTimeout", 10)
Opt("GUIOnEventMode", 1)

;# Enums used with the response of _HTTP_ParseHttpRequest method
Global Enum $HttpRequest_METHOD, $HttpRequest_URI, $HttpRequest_PROTOCOL, $HttpRequest_HEADERS, $HttpRequest_BODY
Global Enum $HttpUri_Scheme, $HttpUri_Path, $httpUri_Query, $HttpUri_Fragment

Global Const $FMFD_DEFAULT = 0x00000000
Global Const $FMFD_URLASFILENAME = 0x00000001
Global Const $FMFD_ENABLEMIMESNIFFING = 0x00000002
Global Const $FMFD_IGNOREMIMETEXTPLAIN = 0x00000004
Global Const $FMFD_SERVERMIME = 0x00000008
Global Const $FMFD_RESPECTTEXTPLAIN = 0x00000010
Global Const $FMFD_RETURNUPDATEDIMGMIMES = 0x00000020

Global Const $HTTP_STATUS_200 = "200 OK"
Global Const $HTTP_STATUS_403 = "403 Forbidden"

#Region // OPTIONS HERE //
	Local $sRootDir = @ScriptDir & "\www" ; The absolute path to the root directory of the server.
	;~ Local $sIP = @IPAddress1 ; ip address as defined by AutoIt
	;~ Local $sIP = "127.0.0.1"
	Local $sIP = IniRead("settings.ini", "core", "IP", "0.0.0.0");	http://localhost/ and more
	Local $iPort = Int(IniRead("settings.ini", "core", "Port", 80)); the listening port
	Local $sServerAddress = "http://" & $sIP & ":" & $iPort & "/"
	Local $iMaxUsers =  Int(IniRead("settings.ini", "core", "MaxUsers", 15)); Maximum number of users who can simultaneously get/post
	Local $sServerName = "AutoIt HTTP Server/0.1 (" & @OSVersion & ") AutoIt/" & @AutoItVersion
	Local $DirectoryIndex=IniRead("settings.ini", "core", "DirectoryIndex", "index.html")
	Local $bAllowIndexes=IniRead("settings.ini", "core", "AllowIndexes", False)

	Local $PHP_Path = IniRead("settings.ini", "PHP", "PHP_Path", "")
	Local $AU3_Path = IniRead("settings.ini", "AU3", "Path", "")
#EndRegion // END OF OPTIONS //

;TODO: add server gui

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

;TODO: php is no longer associated with doing indexing of folders
If IsString($bAllowIndexes) Then $bAllowIndexes=((StringLower($bAllowIndexes)=="true")?True : False)
;If $PHP_Path = "" Then $bAllowIndexes = False

Local $aSocket[$iMaxUsers] ; Creates an array to store all the possible users
Local $sBuffer[$iMaxUsers] ; All these users have buffers when sending/receiving, so we need a place to store those

For $x = 0 to UBound($aSocket)-1 ; Fills the entire socket array with -1 integers, so that the server knows they are empty.
	$aSocket[$x] = -1
Next

TCPStartup() ; AutoIt needs to initialize the TCP functions

$iMainSocket = TCPListen($sIP,$iPort, $iMaxUsers) ;create main listening socket
If @error Then ; if you fail creating a socket, exit the application
	MsgBox(0x20, "AutoIt Webserver", "Unable to create a socket on port " & $iPort & ".") ; notifies the user that the HTTP server will not run
	Exit ; if your server is part of a GUI that has nothing to do with the server, you'll need to remove the Exit keyword and notify the user that the HTTP server will not work.
EndIf

Debug("Server created on " & $sServerAddress)

While 1
	$iNewSocket = TCPAccept($iMainSocket) ; Tries to accept incoming connections

	If $iNewSocket <> -1 Then ; Verifies that there actually is an incoming connection
		For $x = 0 to UBound($aSocket)-1 ; Attempts to store the incoming connection
			If $aSocket[$x] = -1 Then
				$aSocket[$x] = $iNewSocket ;store the new socket
				Debug("Accepted new request on position: "&$x)
				ExitLoop
			EndIf
		Next
		If $aSocket[$x] = -1 Then TCPCloseSocket($iNewSocket); No room for socket
	EndIf

	For $x = 0 to UBound($aSocket)-1 ; A big loop to receive data from everyone connected
		If $aSocket[$x] = -1 Then ContinueLoop ; if the socket is empty, it will continue to the next iteration, doing nothing

		Debug("("&$aSocket[$x]&")Getting request information on position: "&$x)

		$sNewData = TCPRecv($aSocket[$x], 1024, 1) ; Receives a whole lot of data if possible
		If @error <> 0 Or @extended<>0 Then ; Client has disconnected
			TCPCloseSocket($aSocket[$x])
			Debug("Client has disconnected on position: "&$x)
			$aSocket[$x] = -1 ; Socket is freed so that a new user may join
			$sBuffer[$x] = ""
			ContinueLoop ; Go to the next iteration of the loop, not really needed but looks oh so good
		EndIf

		$sNewData = BinaryToString($sNewData) ; Receives a whole lot of data if possible

		Debug(VarGetType($sNewData)&"("&StringLen($sNewData)&"): "&$sNewData)
		$sBuffer[$x] &= $sNewData ;store it in the buffer

		If StringInStr(StringStripCR($sBuffer[$x]),@LF&@LF) Then ; if the request headers are ready ..
			$aRequest = _HTTP_ParseHttpRequest($sBuffer[$x])
			$aContentLength = StringRegExp($sBuffer[$x], "(?m)^Content-Length: ([0-9]+)$", 1)
			If @error = 0 And Not ($aContentLength[0] = BinaryLen(StringToBinary($aRequest[$HttpRequest_BODY]))) Then ContinueLoop
		Else
			ContinueLoop
		EndIf

		Debug("Starting processing request on position: "&$x)

		$sFirstLine = "";StringLeft($sBuffer[$x],StringInStr($sBuffer[$x],@LF)) ; helps to get the type of the request
		
		$aRequest = _HTTP_ParseHttpRequest($sBuffer[$x])
		$aHeaders = _HTTP_ParseHttpHeaders($aRequest[$HttpRequest_HEADERS])
		$aUri = _HTTP_ParseURI($aRequest[$HttpRequest_URI])

		Debug("aUri[Path]: "&$aUri[$HttpUri_Path])
		;Debug("aUri[Query]: "&$aUri[$httpUri_Query])
		;Debug("LocalPath: " & _WinAPI_GetFullPathName($sRootDir & "\" & $aUri[$HttpUri_Path]))

		Switch $aRequest[$HttpRequest_METHOD]
			Case "HEAD"
				;TODO
			Case "GET"
				$sRequest = $aUri[$HttpUri_Path]; StringTrimRight(StringTrimLeft($sFirstLine,4),11) ; let's see what file he actually wants
				;FIXME: if codeblock below: disallows any dot files like .htaccess
				If StringInStr(StringReplace($sRequest,"\","/"), "/.") Then ; Disallow any attempts to go back a folder
					_HTTP_SendFileNotFoundError($aSocket[$x]) ; sends back an error
				Else
					$sLocalPath = _WinAPI_GetFullPathName($sRootDir & "\" & $sRequest);TODO: replace every instance of ($sRootDir & "\" & $sRequest) with $sLocalPath
					If StringInStr(FileGetAttrib($sLocalPath),"D")>0 Then ; user has requested a directory
						Local $iStart=1
						Local $iEnd=StringInStr($DirectoryIndex, ",")-$iStart
						Local $sIndex
						If Not (StringRight($sLocalPath, 1)="\") Then $sLocalPath &= "\"
						While 1
							$sIndex=StringMid($DirectoryIndex, $iStart, $iEnd)
							If FileExists($sLocalPath & $sIndex ) Then ExitLoop
							If $iEnd<1 Then ExitLoop
							$iStart=$iStart+$iEnd+1
							$iEnd=StringInStr($DirectoryIndex, ",", 0, 1, $iStart)
							$iEnd=$iEnd>0?$iEnd-$iStart:$iEnd-1
						WEnd

						;$sLocalPath = $sLocalPath & $sIndex
						If Not FileExists($sLocalPath&$sIndex) Then
							If $bAllowIndexes Then;And FileExists(@ScriptDir & "\index.php") Then
								_HTTP_IndexDir($aSocket[$x], $sLocalPath)
							Else
								_HTTP_SendHTML($aSocket[$x], "403 Forbidden", "403 Forbidden")
							EndIf
							;$sBuffer[$x] = "" ; clears the buffer because we just used to buffer and did some actions based on them
							;$aSocket[$x] = -1 ; the socket is automatically closed so we reset the socket so that we may accept new clients
							;ContinueLoop
						EndIf

						$sLocalPath = $sLocalPath&$sIndex
					ElseIf FileExists($sLocalPath) Then ; makes sure the file that the user wants exists
						$iFileType = StringInStr($sLocalPath, ".", 0, -1)
						$sFileType = $iFileType>0 ? StringMid($sLocalPath,$iFileType+1) : ""
						Switch $sFileType
							Case "php"
								If $PHP_Path = "" Then ContinueCase;if php path is not set, it will default to the "Case Else"
								_HTTP_GCI_PHP()
							Case "au3"
								If $AU3_Path = "" Then ContinueCase;if au3 path is not set, it will default to the "Case Else"
								_HTTP_GCI_AU3()
							Case Else
								_HTTP_SendFile($aSocket[$x], $sLocalPath, Default, "200 OK", True)
						EndSwitch
					Else
						_HTTP_SendFileNotFoundError($aSocket[$x]) ; File does not exist, so we'll send back an error..
					EndIf
				EndIf
			Case "POST" ; user has come to us with data, we need to parse that data and based on that do something special
				_HTTP_SendFile($aSocket[$x], $sRootDir & "\index.html", "text/html") ; Sends back the new file we just created
			Case Else
				_HTTP_SendHTML($aSocket[$x], "", "501 Not Implemented")
		EndSwitch

		TCPCloseSocket($aSocket[$x])
		$aSocket[$x] = -1 ; the socket is closed so we reset the socket so that we may accept new clients
		$sBuffer[$x] = "" ; clears the buffer because we just used to buffer and did some actions based on them
	Next

	Sleep(10)
WEnd

Func _HTTP_SendHeaders($hSocket, $headers = "", $status = $HTTP_STATUS_200)
	$headers = _HTTP_MergeHttpHeaders( _
		"Server: " & $sServerName & @LF & _
		"Connection: Keep-Alive" & @LF & _
		"Content-Type: text/html; charset=UTF-8" & @LF, _
		$headers _
	)

	$headers = "HTTP/1.1 " & $status & @LF & $headers & @LF

	_HTTP_SendContent($hSocket, $headers)
EndFunc

Func _HTTP_SendContent($hSocket, $bData)
	If Not IsBinary($bData) Then $bData = Binary($bData)
	While BinaryLen($bData) ; Send data in chunks (most code by Larry)
		$a = TCPSend($hSocket, $bData) ; TCPSend returns the number of bytes sent
		$bData = BinaryMid($bData, $a+1, BinaryLen($bData)-$a)
	WEnd
EndFunc

Func _HTTP_SendChunk($hSocket, $bData)
	If IsBinary($bData) Then $bData = BinaryToString($bData)
	_HTTP_SendContent($hSocket, StringRegExpReplace(Hex(BinaryLen($bData)), "^0+", "")&@CRLF&$bData&@CRLF)
EndFunc

Func _HTTP_EndChunk($hSocket)
	_HTTP_SendContent($hSocket, "0"&@CRLF&@CRLF)
EndFunc

Func _HTTP_SendHTML($hSocket, $sHTML, $sReply = "200 OK") ; sends HTML data on X socket
	_HTTP_SendData($hSocket, Binary($sHTML), "text/html", $sReply)
EndFunc

Func _HTTP_SendFile($hSocket, $sFileLoc, $sMimeType = Default, $sReply = "200 OK", $bLastModified=False) ; Sends a file back to the client on X socket, with X mime-type
	Local $hFile, $aFileLastModified
	Local Static $wDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], $months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	If $sMimeType==Default Then
		Local $aRet = DllCall("urlmon.dll", "long", "FindMimeFromData", "ptr", 0, "wstr", $sFileLoc, "ptr", 0, "DWORD", 0, "ptr", 0, "DWORD", 0, "wstr*", 0, "DWORD", $FMFD_URLASFILENAME + $FMFD_RETURNUPDATEDIMGMIMES)
		$sMimeType = ((@error <> 0) Or ($aRet[7]=='0')) ? 'application/octet-stream' : $aRet[7]
	EndIf

	$hFile = FileOpen($sFileLoc,16)
	$bFileData = FileRead($hFile)
	FileClose($hFile)

	If $bLastModified Then $aFileLastModified = FileGetTime($sFileLoc, 0, 0)
	;Debug($aFileLastModified)
	_HTTP_SendData($hSocket, $bFileData, $sMimeType, $sReply, $bLastModified?StringFormat("%s, %s %s %s %s:%s:%s GMT", $wDays[_DateToDayOfWeek($aFileLastModified[0], $aFileLastModified[1], $aFileLastModified[2])-1], $aFileLastModified[2], $months[$aFileLastModified[1]-1], $aFileLastModified[0], $aFileLastModified[3], $aFileLastModified[4], $aFileLastModified[5]):"")
EndFunc

Func _HTTP_SendData($hSocket, $bData, $sMimeType, $sReply = $HTTP_STATUS_200, $sLastModified = ""); FIXME: currently no headers are sent!
	Local $a
	Local $sPacket = Binary("HTTP/1.1 " & $sReply & @CRLF & _
	"Server: " & $sServerName & @CRLF & _
	"Connection: Keep-Alive" & @CRLF & _
	"Content-Lenght: " & BinaryLen($bData) & @CRLF & _
	"Content-Type: " & $sMimeType & "; charset=UTF-8" & @CRLF & _
	(($sLastModified="")?"":"Last-Modified: "&$sLastModified&@CRLF)& _
	@CRLF)
	;[set non-blocking mode]
    Local $aResult = DllCall("ws2_32.dll", 'int', 'ioctlsocket', 'int', $hSocket, 'long', 0x8004667E, 'ulong*', 1)
    Local $aResult = DllCall("ws2_32.dll", 'int', 'ioctlsocket', 'int', $hSocket, 'long', 0x4010, 'ulong*', 1);IPX_IMMEDIATESPXACK

	$tBuffer = DllStructCreate("BYTE[1024]")
	DllStructSetData($tBuffer, 1, $sPacket)

	$aResult = DllCall("ws2_32.dll", 'int', 'send', 'int', $hSocket, 'struct*', $tBuffer, 'int', BinaryLen($sPacket), 'int', 0)
	;TCPSend($hSocket,$sPacket) ; Send start of packet

	While BinaryLen($bData) ; Send data in chunks (most code by Larry)
		DllStructSetData($tBuffer, 1, $bData)
		$aResult = DllCall("ws2_32.dll", 'int', 'send', 'int', $hSocket, 'struct*', $tBuffer, 'int', BinaryLen($bData)>DllStructGetSize($tBuffer)?DllStructGetSize($tBuffer):BinaryLen($bData), 'int', 0)
		;$a = TCPSend($hSocket, $bData) ; TCPSend returns the number of bytes sent
		$a = $aResult[0]
		$bData = BinaryMid($bData, $a+1, BinaryLen($bData)-$a)
	WEnd

	;[set blocking mode]
    $aResult = DllCall("ws2_32.dll", 'int', 'ioctlsocket', 'int', $hSocket, 'long', 0x8004667E, 'ulong*', 0)

	;$sPacket = Binary(@CRLF & @CRLF) ; Finish the packet
	;TCPSend($hSocket,$sPacket)
EndFunc

Func _HTTP_SendFileNotFoundError($hSocket) ; Sends back a basic 404 error
	Local $s404Loc = $sRootDir & "\404.html"
	If (FileExists($s404Loc)) Then
		_HTTP_SendFile($hSocket, $s404Loc, "text/html", "404 Not Found")
	Else
		_HTTP_SendHTML($hSocket, "404 Error: " & @CRLF & @CRLF & "The file you requested could not be found.", "404 Not Found")
	EndIf
EndFunc

#cs
# Parse URI into segments
#
# @param string $uri The URI string to parse.
#
# @return array
#ce
Func _HTTP_ParseURI($uri, $decode = True)
	Local Static $define = "(?(DEFINE)(?<URIreference>(?:(?&absoluteURI)|(?&relativeURI))?(?:\#(?&fragment))?)(?<absoluteURI>(?&scheme)\:(?:(?&hier_part)|(?&opaque_part)))(?<relativeURI>(?:(?&net_path)|(?&abs_path)|(?&rel_path))(?:\?(?&query))?)(?<hier_part>(?:(?&net_path)|(?&abs_path))(?:\?(?&query))?)(?<opaque_part>(?&uric_no_slash)(?&uric)*)(?<uric_no_slash>(?&unreserved)|(?&escaped)|[;?:@&=+$,])(?<net_path>\/\/(?&authority)(?&abs_path)?)(?<abs_path>\/(?&path_segments))(?<rel_path>(?&rel_segment)(?&abs_path)?)(?<rel_segment>(?:(?&unreserved)|(?&escaped)|[;@&=+$,])+)(?<scheme>(?&alpha)((?&alpha)|(?&digit)|[+-.])*)(?<authority>(?&server)|(?&reg_name))(?<reg_name>(?:(?&unreserved)|(?&escaped)|[$,;:@&=+])+)(?<server>(?:(?:(?&userinfo)\@)?(?&hostport))?)(?<userinfo>(?:(?&unreserved)|(?&escaped)|[;:&=+$,])*)(?<hostport>(?&host)(?:\:(?&port))?)(?<host>(?:(?&hostname)|(?&IPv4address)))(?<hostname>(?:(?&domainlabel)\.)*(?&toplabel)\.?)(?<domainlabel>(?:(?&alphanum)|(?&alphanum)(?:(?&alphanum)|\-)*(?&alphanum)))(?<toplabel>(?&alpha)|(?&alpha)((?&alphanum)|-)*(?&alphanum))(?<IPv4address>(?&digit)+\.(?&digit)+\.(?&digit)+\.(?&digit)+)(?<port>(?&digit)*)(?<path>((?&abs_path)|(?&opaque_part))?)(?<path_segments>(?&segment)(?:\/(?&segment))*)(?<segment>(?&pchar)*(?:;(?&param))*)(?<param>(?&pchar)*)(?<pchar>(?&unreserved)|(?&escaped)|[:@&=+$,])(?<query>(?&uric)*)(?<fragment>(?&uric)*)(?<uric>(?&reserved)|(?&unreserved)|(?&escaped))(?<reserved>[;\/?:@&=+$,])(?<unreserved>(?&alphanum)|(?&mark))(?<mark>[-_.!~*'()])(?<escaped>\%(?&hex)(?&hex))(?<hex>(?&digit)|[A-Fa-f])(?<alphanum>(?&alpha)|(?&digit))(?<alpha>(?&lowalpha)|(?&upalpha))(?<lowalpha>[a-z])(?<upalpha>[A-Z])(?<digit>[0-9]))"
	;FIXME: add support for absoluteURI (currently having propblems around the <hostname> -> <domainlabel> with the uri "http://www.ics.uci.edu/Test/a/x", following http://www.ietf.org/rfc/rfc2396.txt)
	;Local $aURI = StringRegExp($uri, $define&"");absoluteURI
	Local $aRelativeURI = StringRegExp($uri, $define&"((?&net_path)|(?&abs_path)|(?&rel_path))(\?(?&query))?(\#(?&fragment))?", 1);relativeURI
	If @error <> 0 Then Return SetError(@error, @extended, Default)
	;_ArrayDisplay($aRelativeURI)
	Local $aURI = ["", $aRelativeURI[43], UBound($aRelativeURI)>44?$aRelativeURI[44]:"", UBound($aRelativeURI)>45?$aRelativeURI[45]:""];NOTE: bug where non capturing groups are returned from RegExp @see https://www.autoitscript.com/trac/autoit/ticket/2696
	If $decode Then
		$aURI[$HttpUri_Path] = decodeURI($aURI[$HttpUri_Path])
		$aURI[$httpUri_Query] = decodeURI(StringRegExpReplace($aURI[$httpUri_Query], "\+", " "))
	EndIf
	Return $aURI
EndFunc

#cs
# Parse HTTP request
#
# @param string $request The raw HTTP request string.
#
# @return array
#ce
Func _HTTP_ParseHttpRequest($request)
	Local $requestInfo = StringRegExp($request, "^([A-Z]+) ([^\x0D\x0A\x20]+) ([^\x0A]+)\x0A(?m)((?:^[A-Za-z\-]+\: [^\x0A]+$\x0D?\x0A)*\x0D?\x0A)(?s-m)(.*)$", 1)
	If @error <> 0 Then Return SetError(@error, @extended, Default)
	Return $requestInfo
EndFunc

#cs
# Parse HTTP headers
#
# @param string $headers The raw HTTP headers
#
# @return array
#ce
Func _HTTP_ParseHttpHeaders($headers)
	Local $aHeaders = StringRegExp($headers, "(?m)^([A-Za-z\-]+)\: (.+)$", 3)
	If @error <> 0 Then Return SetError(@error, @extended, Default)
	Return $aHeaders
EndFunc

Func decodeURI($sString)
	Local $iLimit = 0
	Local $sPattern = "(?:%[0-9a-fA-F]{2})+"
	Local $iOffset = 1, $iDone = 0, $iMatchOffset

    While True
        $aRes = StringRegExp($sString, $sPattern, 2, $iOffset)
        If @error Then ExitLoop

        $sRet = Call("UTF8ToString", $aRes[0])
        If @error Then Return SetError(@error, $iDone, $sString)

        $iOffset = StringInStr($sString, $aRes[0], 1, 1, $iOffset)
        $sString = StringLeft($sString, $iOffset - 1) & $sRet & StringMid($sString, $iOffset + StringLen($aRes[0]))
        $iOffset += StringLen($sRet)

        $iDone += 1
        If $iDone = $iLimit Then ExitLoop
    WEnd

    Return SetExtended($iDone, $sString)
EndFunc

Func UTF8ToString($utf8)
	Local $parts = StringRegExp($utf8, "%([0-9a-fA-F]{2})", 3)
	Local $char2, $char3
	Local $i = 0
	Local $len = UBound($parts)
	Local $out = ""
	Local $c
	While $i < $len
		$c = Dec($parts[$i], 1)
		$i+=1
		Switch BitShift($c, 4)
			Case 0 To 7
				; 0xxxxxxx
				$out &= ChrW($c)
			Case 12 To 13
				; 110x xxxx   10xx xxxx
				$char2 = Dec($parts[$i], 1)
				$i+=1
				$out &= ChrW(BitOR(BitShift(BitAND($c, 0x1F), -6), BitAND($char2, 0x3F)))
			Case 14
				; 1110 xxxx  10xx xxxx  10xx xxxx
				$char2 = Dec($parts[$i], 1)
				$i+=1
				$char3 = Dec($parts[$i], 1)
				$i+=1
				$out &= ChrW(BitOR(BitShift(BitAND($c, 0x0F), -12), BitShift(BitAND($char2, 0x3F), -6), BitShift(BitAND($char3, 0x3F), 0)))
		EndSwitch
	WEnd
	return $out
EndFunc

Func _HTTP_IndexDir($hSocket, $dir)
	_HTTP_SendHeaders($hSocket, "Transfer-Encoding: chunked")
	$title = "Index of "&StringRegExpReplace(StringRegExpReplace(StringTrimLeft($dir, StringLen($sRootDir)), "\\", "/"), "/$", "")
	_HTTP_SendChunk($hSocket, '<!DOCTYPE html><html><head><title>'&$title&'</title>')
	_HTTP_SendChunk($hSocket, "<style>th {text-align:left;} .d, .f {background-size:contain;background-repeat:no-repeat;background-position:center;min-width:15px;min-height:15px;} .d{background-image: url('data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA3MiA1NSI+PHN0eWxlPjwhW0NEQVRBWy5BLC5CLC5De3N0cm9rZTojNDM0MjQyO3N0cm9rZS13aWR0aDoxLjI1O3N0cm9rZS1taXRlcmxpbWl0OjEwfV1dPjwvc3R5bGU+PGxpbmVhckdyYWRpZW50IGlkPSJBIiBncmFkaWVudFVuaXRzPSJ1c2VyU3BhY2VPblVzZSIgeDE9IjM1Ljk0MyIgeTE9Ii43OSIgeDI9IjM1Ljk0MyIgeTI9IjE4LjMzNiI+PHN0b3Agb2Zmc2V0PSIwIiBzdG9wLWNvbG9yPSIjZmNmY2ZkIi8+PHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjZmZmIi8+PC9saW5lYXJHcmFkaWVudD48cGF0aCBjbGFzcz0iQSIgZD0iTTIuNiAxOC4zVjIuNWMwLS45LjctMS43IDEuNy0xLjdoMjMuM2w2LjcgNWgzMy4zYy45IDAgMS43LjggMS43IDEuN3YxMC45SDIuNnoiIGZpbGw9InVybCgjQSkiLz48bGluZWFyR3JhZGllbnQgaWQ9IkIiIGdyYWRpZW50VW5pdHM9InVzZXJTcGFjZU9uVXNlIiB4MT0iMzUuOTQzIiB5MT0iNTQuMjYzIiB4Mj0iMzUuOTQzIiB5Mj0iOS45ODEiPjxzdG9wIG9mZnNldD0iLjEwOSIgc3RvcC1jb2xvcj0iI2RlYmUwMCIvPjxzdG9wIG9mZnNldD0iLjUzMiIgc3RvcC1jb2xvcj0iI2NmYWQwNCIvPjxzdG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iI2EwNzgwMiIvPjwvbGluZWFyR3JhZGllbnQ+PHBhdGggY2xhc3M9IkIiIGQ9Ik00LjMgNTQuM2g2My4zYy45IDAgMS42LS44IDEuNy0xLjdMNzEgMTEuN2MwLS45LS43LTEuNy0xLjctMS43aC0yNWwtNi43IDVoLTM1Yy0uOSAwLTEuNy44LTEuNyAxLjdsMS43IDM1LjljLjEuOS44IDEuNyAxLjcgMS43eiIgZmlsbD0idXJsKCNCKSIvPjxwYXRoIGNsYXNzPSJDIiBkPSJNNy42IDQuMWgxOC4zYy45IDAgMS43LjggMS43IDEuN3MtLjcgMS43LTEuNyAxLjdINy42Yy0uOSAwLTEuNy0uOC0xLjctMS43cy44LTEuNyAxLjctMS43eiIgZmlsbD0iIzQzNDI0MiIvPjwvc3ZnPg==');} .f{background-image:url('data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA3MiAxMDAiPjxsaW5lYXJHcmFkaWVudCBpZD0iQSIgZ3JhZGllbnRVbml0cz0idXNlclNwYWNlT25Vc2UiIHgxPSIzNiIgeTE9Ijk5IiB4Mj0iMzYiIHkyPSIxIj48c3RvcCBvZmZzZXQ9IjAiIHN0b3AtY29sb3I9IiNjOGQ0ZGIiLz48c3RvcCBvZmZzZXQ9Ii4xMzkiIHN0b3AtY29sb3I9IiNkOGUxZTYiLz48c3RvcCBvZmZzZXQ9Ii4zNTkiIHN0b3AtY29sb3I9IiNlYmYwZjMiLz48c3RvcCBvZmZzZXQ9Ii42MTciIHN0b3AtY29sb3I9IiNmOWZhZmIiLz48c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29sb3I9IiNmZmYiLz48L2xpbmVhckdyYWRpZW50PjxwYXRoIGQ9Ik00NSAxbDI3IDI2LjdWOTlIMFYxaDQ1eiIgZmlsbD0idXJsKCNBKSIvPjxwYXRoIGQ9Ik00NSAxbDI3IDI2LjdWOTlIMFYxaDQ1eiIgZmlsbC1vcGFjaXR5PSIwIiBzdHJva2U9IiM3MTkxYTEiIHN0cm9rZS13aWR0aD0iMiIvPjxsaW5lYXJHcmFkaWVudCBpZD0iQiIgZ3JhZGllbnRVbml0cz0idXNlclNwYWNlT25Vc2UiIHgxPSI0NS4wNjgiIHkxPSIyNy43OTYiIHgyPSI1OC41NjgiIHkyPSIxNC4yOTUiPjxzdG9wIG9mZnNldD0iMCIgc3RvcC1jb2xvcj0iI2ZmZiIvPjxzdG9wIG9mZnNldD0iLjM1IiBzdG9wLWNvbG9yPSIjZmFmYmZiIi8+PHN0b3Agb2Zmc2V0PSIuNTMyIiBzdG9wLWNvbG9yPSIjZWRmMWY0Ii8+PHN0b3Agb2Zmc2V0PSIuNjc1IiBzdG9wLWNvbG9yPSIjZGRlNWU5Ii8+PHN0b3Agb2Zmc2V0PSIuNzk5IiBzdG9wLWNvbG9yPSIjYzdkM2RhIi8+PHN0b3Agb2Zmc2V0PSIuOTA4IiBzdG9wLWNvbG9yPSIjYWRiZGM3Ii8+PHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjOTJhNWIwIi8+PC9saW5lYXJHcmFkaWVudD48cGF0aCBkPSJNNDUgMWwyNyAyNi43SDQ1VjF6IiBmaWxsPSJ1cmwoI0IpIi8+PHBhdGggZD0iTTQ1IDFsMjcgMjYuN0g0NVYxeiIgZmlsbC1vcGFjaXR5PSIwIiBzdHJva2U9IiM3MTkxYTEiIHN0cm9rZS13aWR0aD0iMiIgc3Ryb2tlLWxpbmVqb2luPSJiZXZlbCIvPjwvc3ZnPg==');}</style>")
	_HTTP_SendChunk($hSocket, "</head><body><h1>"&$title&'</h1><table><tr><th></th><th>Name</th><th>Size</th></tr><tr><td class="d"></td><td><a href="..">..</a></td></tr>');TODO: replace special charaters in $title within the h1 element with HTML escaped charaters
	Local $tData = DllStructCreate($tagWIN32_FIND_DATA)
	Local $sFile
	Local $hSearch = _WinAPI_FindFirstFile($dir&'*', $tData)
	While @error = 0
		$sFile = DllStructGetData($tData, 'cFileName')
		Switch $sFile
			Case '.', '..'
			Case Else
				If Not BitAND(DllStructGetData($tData, 'dwFileAttributes'), $FILE_ATTRIBUTE_DIRECTORY) Then
					_HTTP_SendChunk($hSocket, '<tr><td class="f"></td><td><a href="./'&$sFile&'">'&$sFile&'</a></td><td>'&FileSizeForHumans(_WinAPI_MakeQWord(DllStructGetData($tData, 'nFileSizeLow'), DllStructGetData($tData, 'nFileSizeHigh')))&'</td></tr>')
				Else
					_HTTP_SendChunk($hSocket, '<tr><td class="d"></td><td><a href="./'&$sFile&'/">'&$sFile&'</a></td><td></td></tr>')
				EndIf
		EndSwitch
		_WinAPI_FindNextFile($hSearch, $tData)
	WEnd
	_WinAPI_FindClose($hSearch)
	_HTTP_SendChunk($hSocket, '<tr><td colspan="3">Icons used are from the <a href="https://github.com/dmhendricks/file-icon-vectors">File Icon Images</a></td></tr></table></body></html>')
	_HTTP_EndChunk($hSocket)
EndFunc

Func FileSizeForHumans($iSize)
	Local $iSizeGroup = Log($iSize) / log(1024)
	Local $iSizeGroupBase = Floor($iSizeGroup)
	Local $suffix
	Switch ($iSizeGroupBase)
		Case 0
			$suffix = "B"
		Case 1
			$suffix = "KiB"
		Case 2
			$suffix = "MiB"
		Case 3
			$suffix = "GiB"
		Case 4
			$suffix = "TiB"
		Case 5
			$suffix = "PiB"
		Case 6
			$suffix = "EiB"
		case 7
			$suffix = "ZiB"
		Case 8
			$suffix = "YiB"
		Case Else
			$suffix = "?"
	EndSwitch

	return StringFormat("%.2f %s", $iSize/1024^$iSizeGroupBase, $suffix)
EndFunc

;FIXME: add parameters for use with the function
Func _HTTP_GCI_PHP()
	Local $hReadPipe, $hWritePipe
	Local $STARTF_USESTDHANDLES = 0x100
	Local $QUERY_STRING = "";FIXME import from request through parameters
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

	; Local $tSockaddr = DllStructCreate("ushort sa_family;char sa_data[14];")
	Local $tSockaddr = DllStructCreate("short;ushort;uint;char[8]")
	Local $aRet = DllCall("Ws2_32.dll", "int", "getpeername", "int", $aSocket[$x], "ptr", DllStructGetPtr($tSockaddr), "int*", DllStructGetSize($tSockaddr))
	Local $aRet = DllCall("Ws2_32.dll", "str", "inet_ntoa", "int", DllStructGetData($tSockaddr, 3))

	$sEnviroment="SCRIPT_NAME="&StringMid($sLocalPath,StringInStr($sLocalPath, "\", 0, -1)+1)&Chr(0)& _
	"REMOTE_ADDR="&$aRet[0]&Chr(0)& _
	"REQUESTED_METHOD=GET"&Chr(0)& _
	"REQUEST_URI="&StringTrimRight(StringTrimLeft($sFirstLine,4),11)&Chr(0)& _
	"QUERY_STRING="&$QUERY_STRING&Chr(0)& _
	Chr(0);missing: USER_AGENT, REFERER, SERVER_PROTOCOL
	$tEnviroment=DllStructCreate("WCHAR["&StringLen($sEnviroment)&"]")
	DllStructSetData($tEnviroment, 1, $sEnviroment)
	_WinAPI_CreateProcess($PHP_Path&"\php-cgi.exe", "-f """ & $sLocalPath & """ " & $QUERY_STRING, Null, Null, True, $CREATE_NO_WINDOW+$NORMAL_PRIORITY_CLASS+$CREATE_UNICODE_ENVIRONMENT, DllStructGetPtr($tEnviroment), $sRootDir, DllStructGetPtr($tStartup), DllStructGetPtr($tProcess))

	Local $hProcess = DllStructGetData($tProcess, "hProcess")
	_WinAPI_CloseHandle(DllStructGetData($tProcess, "hThread"))
		Local $tBuffer = DllStructCreate("char Text[4096]")
		Local $pBuffer = DllStructGetPtr($tBuffer)
		Local $iBytes
		Local $bData
		Local $a
		Local $STILL_ACTIVE = 0x103

		;FIXME: move start of packet down and merge headers with php CGI output
		Local $sPacket = Binary("HTTP/1.1 200 OK" & @CRLF & _
			"Server: " & $sServerName & @CRLF & _
			"Connection: Keep-Alive" & @CRLF & _
			"Content-Type: text/html; charset=UTF-8" & @CRLF & _
			"Transfer-Encoding: chunked" & @CRLF & @CRLF )
			TCPSend($aSocket[$x],$sPacket) ; Send start of packet

		_WinAPI_CloseHandle($hWritePipe)
		While 1
			If Not _WinAPI_ReadFile($hReadPipe, $pBuffer, 4096, $iBytes) Then ExitLoop
			If $iBytes>0 Then
				;$bData = Binary(StringRegExpReplace(Hex($iBytes), "^0+", "")&@CRLF& StringLeft(DllStructGetData($tBuffer, "Text"), $iBytes / 2) &@CRLF)
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
EndFunc

Func _HTTP_GCI_AU3()
	Local $hReadPipe, $hWritePipe
	Local $STARTF_USESTDHANDLES = 0x100
	Local $QUERY_STRING = "";FIXME import from request through parameters
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

	; Local $tSockaddr = DllStructCreate("ushort sa_family;char sa_data[14];")
	Local $tSockaddr = DllStructCreate("short;ushort;uint;char[8]")
	Local $aRet = DllCall("Ws2_32.dll", "int", "getpeername", "int", $aSocket[$x], "ptr", DllStructGetPtr($tSockaddr), "int*", DllStructGetSize($tSockaddr))
	Local $aRet = DllCall("Ws2_32.dll", "str", "inet_ntoa", "int", DllStructGetData($tSockaddr, 3))

	$sEnviroment="SCRIPT_NAME="&StringMid($sLocalPath,StringInStr($sLocalPath, "\", 0, -1)+1)&Chr(0)& _
	"REMOTE_ADDR="&$aRet[0]&Chr(0)& _
	"REQUESTED_METHOD=GET"&Chr(0)& _
	"REQUEST_URI="&StringTrimRight(StringTrimLeft($sFirstLine,4),11)&Chr(0)& _
	"QUERY_STRING="&$QUERY_STRING&Chr(0)& _
	Chr(0);missing: USER_AGENT, REFERER, SERVER_PROTOCOL
	$tEnviroment=DllStructCreate("WCHAR["&StringLen($sEnviroment)&"]")
	DllStructSetData($tEnviroment, 1, $sEnviroment)
	_WinAPI_CreateProcess($AU3_Path&"\AutoIt3.exe", "/ErrorStdOut """ & $sLocalPath & """ >", Null, Null, True, $CREATE_NO_WINDOW+$NORMAL_PRIORITY_CLASS+$CREATE_UNICODE_ENVIRONMENT, DllStructGetPtr($tEnviroment), $sRootDir, DllStructGetPtr($tStartup), DllStructGetPtr($tProcess))

	Local $hProcess = DllStructGetData($tProcess, "hProcess")
	_WinAPI_CloseHandle(DllStructGetData($tProcess, "hThread"))
		Local $tBuffer = DllStructCreate("char Text[4096]")
		Local $pBuffer = DllStructGetPtr($tBuffer)
		Local $iBytes
		Local $bData
		Local $a
		Local $STILL_ACTIVE = 0x103

		;FIXME: move start of packet down and merge headers with php CGI output
		Local $sPacket = Binary("HTTP/1.1 200 OK" & @CRLF & _
			"Server: " & $sServerName & @CRLF & _
			"Connection: Keep-Alive" & @CRLF & _
			"Content-Type: text/html; charset=UTF-8" & @CRLF & _
			"Transfer-Encoding: chunked" & @CRLF & @CRLF )
			TCPSend($aSocket[$x],$sPacket) ; Send start of packet

		_WinAPI_CloseHandle($hWritePipe)
		While 1
			If Not _WinAPI_ReadFile($hReadPipe, $pBuffer, 4096, $iBytes) Then ExitLoop
			If $iBytes>0 Then
				;$bData = Binary(StringRegExpReplace(Hex($iBytes), "^0+", "")&@CRLF& StringLeft(DllStructGetData($tBuffer, "Text"), $iBytes / 2) &@CRLF)
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
EndFunc

Func Debug($vLog, $nl = True, $ln = @ScriptLineNumber)
	Local Static $time = TimerInit()
	If @Compiled Then Return
	ConsoleWrite(StringFormat("(%04s) %s %+dms%s", $ln, $vLog, TimerDiff($time), $nl ? @CRLF : ""))
EndFunc

#cs
# Merge two header strings
#
# @param string $headers1
# @param string $headers2
#
# @return string merged headers
#ce
Func _HTTP_MergeHttpHeaders($headers1, $headers2)
    Local $headers = ""
    $headers1 = _HTTP_ParseHttpHeaders($headers1)
    $headers2 = _HTTP_ParseHttpHeaders($headers2)
    For $i=0 To UBound($headers1, 1)-1 Step +2
        For $j=0 To UBound($headers2, 1)-1 Step +2
            If StringLower($headers1[$i]) = "set-cookie" Then ContinueLoop 1
            If StringLower($headers1[$i]) = StringLower($headers2[$j]) Then
                $headers &= StringFormat("%s: %s%s", $headers2[$j], $headers2[$j+1], @LF)
                ContinueLoop 2
            EndIf
        Next
        $headers &= StringFormat("%s: %s%s", $headers1[$i], $headers1[$i+1], @LF)
    Next

    For $i=0 To UBound($headers2, 1)-1 Step +2
        For $j=0 To UBound($headers1, 1)-1 Step +2
            If StringLower($headers2[$i]) = "set-cookie" Then ContinueLoop 1
            If StringLower($headers1[$j]) = StringLower($headers2[$i]) Then ContinueLoop 2
        Next
        $headers &= StringFormat("%s: %s%s", $headers2[$i], $headers2[$i+1], @LF)
    Next

    Return $headers
EndFunc
