#include <NamedPipes.au3>
#include <WinAPIProc.au3>
#include <WinAPIFiles.au3>
#include <Date.au3>
#include <AutoItConstants.au3>

Opt("TCPTimeout", 10)

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

;Global server variables
Global $aRequest
Global $aHeaders
Global $aUri
Global $x ;FIXME: change to more unique variable name
Global $aSocket
Global $sLocalPath

#Region // DEFAULT OPTIONS HERE //
    Global $sRootDir = _WinAPI_GetFullPathName(IniRead("settings.ini", "core", "RootDir", '.\www\')); The absolute path to the root directory of the server.
    ;~ Global $sIP = @IPAddress1 ; ip address as defined by AutoIt
    ;~ Global $sIP = "127.0.0.1"
    Global $sIP = "0.0.0.0";	http://localhost/ and more
    Global $iPort = 80; the listening port
    Global $sServerAddress = "http://" & $sIP & ":" & $iPort & "/"
    Global $iMaxUsers = 15; Maximum number of users who can simultaneously get/post
    Global $sServerName = "AutoIt HTTP Server/0.1 (" & @OSVersion & ") AutoIt/" & @AutoItVersion
    Global $DirectoryIndex="index.html"
    Global $bAllowIndexes=False

    Global $PHP_Path = ""
    Global $AU3_Path = ""

    Global $_HTTP_Server_Request_Handler = _HTTP_Server_Request_Handle
#EndRegion // END OF DEFAULT OPTIONS //

Func _HTTP_Server_Start()
    ;Local $aSocket[$iMaxUsers] ; Creates an array to store all the possible users
    Global $aSocket[$iMaxUsers] ; Creates an array to store all the possible users
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
        Local $iNewSocket = TCPAccept($iMainSocket) ; Tries to accept incoming connections

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

            if (StringLen($sNewData)>0) Then Debug(VarGetType($sNewData)&"("&StringLen($sNewData)&"): "&$sNewData)
            $sBuffer[$x] &= $sNewData ;store it in the buffer

            If StringInStr(StringStripCR($sBuffer[$x]),@LF&@LF) Then ; if the request headers are ready ..
                Local $aRequest = _HTTP_ParseHttpRequest($sBuffer[$x])
                $aContentLength = StringRegExp($sBuffer[$x], "(?m)^Content-Length: ([0-9]+)$", 1)
                If @error = 0 And Not ($aContentLength[0] >= BinaryLen(StringToBinary($aRequest[$HttpRequest_BODY]))) Then ContinueLoop ; If we havent gotten the complete request body yet, we process other requests and try again later.
            Else
                ContinueLoop
            EndIf

            If (StringLen($sBuffer[$x])>0) Then Debug("Starting processing request on position: "&$x)

            Assign("x", $x, BitOR($ASSIGN_FORCEGLOBAL, $ASSIGN_EXISTFAIL)) ; NOTE $x is forced local, when used in For loop above. This gives issues when other functions need the $x value.
            $_HTTP_Server_Request_Handler($aSocket[$x], $sBuffer[$x])

            TCPCloseSocket($aSocket[$x])
            $aSocket[$x] = -1 ; the socket is closed so we reset the socket so that we may accept new clients
            $sBuffer[$x] = "" ; clears the buffer because we just used to buffer and did some actions based on them
        Next

        Sleep(10)
    WEnd
EndFunc

Func _HTTP_SendHeaders($hSocket, $headers = "", $status = $HTTP_STATUS_200)
    $headers = _HTTP_MergeHttpHeaders( _
        "HTTP/1.1 " & $status & @LF & _
        "Server: " & $sServerName & @LF & _
        "Connection: close" & @LF & _
        "Content-Type: text/plain; charset=UTF-8" & @LF, _
        $headers _
    )

    $headers = $headers & @LF

    _HTTP_SendContent($hSocket, $headers)
EndFunc

Func _HTTP_SendContent($hSocket, $bData)
    Local $a
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
    Local $bFileData = FileRead($hFile)
    FileClose($hFile)

    If $bLastModified Then $aFileLastModified = FileGetTime($sFileLoc, 0, 0)
    ;Debug($aFileLastModified)
    _HTTP_SendData($hSocket, $bFileData, $sMimeType, $sReply, $bLastModified?StringFormat("%s, %s %s %s %s:%s:%s GMT", $wDays[_DateToDayOfWeek($aFileLastModified[0], $aFileLastModified[1], $aFileLastModified[2])-1], $aFileLastModified[2], $months[$aFileLastModified[1]-1], $aFileLastModified[0], $aFileLastModified[3], $aFileLastModified[4], $aFileLastModified[5]):"")
EndFunc

#cs
# @deprecated
#ce
Func _HTTP_SendData($hSocket, $bData, $sMimeType, $sReply = $HTTP_STATUS_200, $sLastModified = ""); FIXME: currently no headers are sent!
    Local $a
    Local $sPacket = Binary("HTTP/1.1 " & $sReply & @LF & _
    "Server: " & $sServerName & @LF & _
    "Connection: close" & @LF & _
    "Content-Lenght: " & BinaryLen($bData) & @LF & _
    "Content-Type: " & $sMimeType & "; charset=UTF-8" & @LF & _
    (($sLastModified="")?"":"Last-Modified: "&$sLastModified&@LF)& _
    @LF)
    ;[set non-blocking mode] ;TODO: the blocking mode currently will result in the connection closing before the client getting all data. there is also a concern taht we don't check if the TCP buffer is full while pushing data. Until a good solution for this is found, async data transfer will be disabled.
    ;Local $aResult = DllCall("ws2_32.dll", 'int', 'ioctlsocket', 'int', $hSocket, 'long', 0x8004667E, 'ulong*', 1)
    ;Local $aResult = DllCall("ws2_32.dll", 'int', 'ioctlsocket', 'int', $hSocket, 'long', 0x4010, 'ulong*', 1);IPX_IMMEDIATESPXACK

    Local $tBuffer = DllStructCreate("BYTE[1000000]"); 1MB
    DllStructSetData($tBuffer, 1, $sPacket)

    Local $aResult = DllCall("ws2_32.dll", 'int', 'send', 'int', $hSocket, 'struct*', $tBuffer, 'int', BinaryLen($sPacket), 'int', 0)
    ;TCPSend($hSocket,$sPacket) ; Send start of packet

    While BinaryLen($bData) ; Send data in chunks (most code by Larry)
        DllStructSetData($tBuffer, 1, $bData)
        $aResult = DllCall("ws2_32.dll", 'int', 'send', 'int', $hSocket, 'struct*', $tBuffer, 'int', BinaryLen($bData)>DllStructGetSize($tBuffer)?DllStructGetSize($tBuffer):BinaryLen($bData), 'int', 0)
        ;$a = TCPSend($hSocket, $bData) ; TCPSend returns the number of bytes sent
        $a = $aResult[0]
        $bData = BinaryMid($bData, $a+1, BinaryLen($bData)-$a)
    WEnd

    ;[set blocking mode]
    ;$aResult = DllCall("ws2_32.dll", 'int', 'ioctlsocket', 'int', $hSocket, 'long', 0x8004667E, 'ulong*', 0)

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
    Local $aRelativeURI = StringRegExp($uri, $define&"((?&net_path)|(?&abs_path)|(?&rel_path))(?:\?((?&query)))?(\#(?&fragment))?", 1);relativeURI
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

#cs
# Parse HTTP status line
# @param string $headers The raw HTTP head
# @return string
#ce
Func _HTTP_ParseHttpStatusLine($headers)
    Local $aStatusLines = StringRegExp($headers, '(?m)^(HTTP\/[0-9](?:\.[0-9])? [0-9]{3} .*)$', 3)
    If @error <> 0 Then Return SetError(@error, @extended, '')
    Return UBound($aStatusLines, 1) > 0 ? SetExtended(UBound($aStatusLines, 1), $aStatusLines[UBound($aStatusLines, 1) - 1]) : SetExtended(0, '')
EndFunc

Func decodeURI($sString)
    Local $iLimit = 0
    Local $sPattern = "(?:%[0-9a-fA-F]{2})+"
    Local $iOffset = 1, $iDone = 0, $iMatchOffset

    Local $aRes, $sRet
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
    _HTTP_SendHeaders($hSocket, "Content-Type: text/html"&@CRLF&"Transfer-Encoding: chunked")
    Local $title = "Index of "&StringRegExpReplace(StringRegExpReplace(StringTrimLeft($dir, StringLen($sRootDir)), "\\", "/"), "/$", "")
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

Func _HTTP_CGI($sAppName, $sCommand = Null)
    local $stdinRd, $stdinWr
    Local $stdoutRd, $stdoutWr
    Local Static $stderr = _WinAPI_GetStdHandle(2)

    Local $STARTF_USESTDHANDLES = 0x100
    Local $STARTF_FORCEOFFFEEDBACK = 0x00000080
    Local $QUERY_STRING = $aUri[$httpUri_Query]
    ; Set up security attributes
    Local $tSecurity = DllStructCreate($tagSECURITY_ATTRIBUTES)
    DllStructSetData($tSecurity, "Length", DllStructGetSize($tSecurity))
    DllStructSetData($tSecurity, "InheritHandle", True)
    _NamedPipes_CreatePipe($stdinRd, $stdinWr, $tSecurity)
    _NamedPipes_CreatePipe($stdoutRd, $stdoutWr, $tSecurity)
    Local $tProcess = DllStructCreate($tagPROCESS_INFORMATION)
    Local $tStartup = DllStructCreate($tagSTARTUPINFO)
    DllStructSetData($tStartup, "Size", DllStructGetSize($tStartup))
    DllStructSetData($tStartup, "Flags", BitOR($STARTF_USESTDHANDLES, $STARTF_FORCEOFFFEEDBACK))
    DllStructSetData($tStartup, "StdInput", $stdinRd)
    DllStructSetData($tStartup, "StdOutput", $stdoutWr)
    DllStructSetData($tStartup, "StdError", $stderr)

    ; Local $tSockaddr = DllStructCreate("ushort sa_family;char sa_data[14];")
    Local $tSockaddr = DllStructCreate("short;ushort;uint;char[8]")
    Local $aRet = DllCall("Ws2_32.dll", "int", "getpeername", "int", $aSocket[$x], "ptr", DllStructGetPtr($tSockaddr), "int*", DllStructGetSize($tSockaddr))
    Local $aRet = DllCall("Ws2_32.dll", "str", "inet_ntoa", "int", DllStructGetData($tSockaddr, 3))
    Local $aPort = DllCall("Ws2_32.dll", "ushort", "htons", "ushort", DllStructGetData($tSockaddr, 2))

    Local Static $tEnv = GetEnvString()

    Local $sEnviroment = _
    "CONTENT_LENGTH="&StringLen($aRequest[$HttpRequest_BODY])&Chr(0)& _
    "CONTENT_TYPE=application/x-www-form-urlencoded"&Chr(0)& _
    "GATEWAY_INTERFACE=CGI/1.1"&Chr(0)& _
    "QUERY_STRING="&$QUERY_STRING&Chr(0)& _
    "REDIRECT_STATUS=200"&Chr(0)& _
    "REMOTE_ADDR="&$aRet[0]&Chr(0)& _
    "REQUEST_METHOD="&$aRequest[$HttpRequest_METHOD]&Chr(0)& _
    "REQUEST_URI="&$aUri[$HttpUri_Path]&Chr(0)& _
    "SCRIPT_NAME="&StringMid($sLocalPath,StringInStr($sLocalPath, "\", 0, -1)+1)&Chr(0)& _
    "SCRIPT_FILENAME="&$sLocalPath&Chr(0)& _
    "SERVER_ADDR="&$sIP&Chr(0)& _
    "SERVER_PROTOCOL=HTTP/1.1"&Chr(0)& _
    "SERVER_NAME=test"&Chr(0)& _
    "SERVER_SOFTWARE="&$sServerName&Chr(0)& _
    "DOCUMENT_ROOT="&_WinAPI_GetFullPathName($sRootDir & "\")&Chr(0)& _
    "HTTP_ACCEPT="&Chr(0)& _
    "HTTP_HOST="&Chr(0)& _
    "SERVER_PORT="&$iPort&Chr(0)& _
    "REMOTE_PORT="&$aPort[0]&Chr(0)& _
    Chr(0)

    Local $tEnviroment=DllStructCreate("WCHAR["&((DllStructGetSize($tEnv)/2)+StringLen($sEnviroment))&"]")
    CopyMemory(DllStructGetPtr($tEnviroment), DllStructGetPtr($tEnv), DllStructGetSize($tEnv))
    Local $tEnviroment2=DllStructCreate("WCHAR["&StringLen($sEnviroment)&"]", DllStructGetPtr($tEnviroment)+DllStructGetSize($tEnv))
    DllStructSetData($tEnviroment2, 1, $sEnviroment)

    _WinAPI_CreateProcess($sAppName, $sCommand, $tSecurity, Null, True, $CREATE_NO_WINDOW+$NORMAL_PRIORITY_CLASS+$CREATE_UNICODE_ENVIRONMENT, DllStructGetPtr($tEnviroment), $sRootDir, DllStructGetPtr($tStartup), DllStructGetPtr($tProcess))

    Local $hProcess = DllStructGetData($tProcess, "hProcess")
    _WinAPI_CloseHandle(DllStructGetData($tProcess, "hThread"))
        Local $tBuffer = DllStructCreate("char Text[4096]")
        Local $pBuffer = DllStructGetPtr($tBuffer)
        Local $iBytes
        Local $sBuffer = ""
        Local $bHeadersSent = False
        Local $i, $l

        local $Request_BODY = $aRequest[$HttpRequest_BODY]
        Local $Request_BODY_Length = StringLen($Request_BODY)
        Local $iToWrite = 4096
        Local $iWritten = 0

        While 1
            DllStructSetData($tBuffer, "Text", $Request_BODY)
            $iToWrite = $iToWrite <= $Request_BODY_Length ? $iToWrite : $Request_BODY_Length
            If Not _WinAPI_WriteFile($stdinWr, $pBuffer, $iToWrite, $iWritten) Then ExitLoop
            $Request_BODY = StringMid($Request_BODY, 1 + $iWritten)
            $Request_BODY_Length = StringLen($Request_BODY)
            if $Request_BODY_Length = 0 Then ExitLoop
        WEnd

        _WinAPI_CloseHandle($stdinRd)
        _WinAPI_CloseHandle($stdinWr)
        _WinAPI_CloseHandle($stdoutWr)
        While 1
            If Not _WinAPI_ReadFile($stdoutRd, $pBuffer, 4096, $iBytes) Then ExitLoop
            If $iBytes>0 Then
                If $bHeadersSent Then
                    _HTTP_SendChunk($aSocket[$x], StringLeft(DllStructGetData($tBuffer, "Text"), $iBytes))
                Else
                    $sBuffer &= StringLeft(DllStructGetData($tBuffer, "Text"), $iBytes)
                    If StringInStr(StringStripCR($sBuffer),@LF&@LF) Then ; if the response headers are ready ..
                        $bHeadersSent = True
                        $l = StringRegExp($sBuffer, "\r?\n\r?\n", 1)
                        $i = @extended
                        $l = StringLen($l[0])
                         _HTTP_SendHeaders($aSocket[$x], "Cache-Control: no-store, max-age=0"&@LF&"Transfer-Encoding: chunked"&@LF&StringLeft($sBuffer, $i-3))
                        if StringLen($sBuffer) > $i Then _HTTP_SendChunk($aSocket[$x], StringMid($sBuffer, $i))
                        $sBuffer = Null; to try and free up some space
                    EndIf
                EndIf
            EndIf
        WEnd

        _HTTP_EndChunk($aSocket[$x])
        TCPCloseSocket($aSocket[$x])
    _WinAPI_CloseHandle($hProcess)
    _WinAPI_CloseHandle($stdoutRd)
EndFunc

Func _HTTP_GCI_PHP()
    Return _HTTP_CGI($PHP_Path&"\php-cgi.exe")
EndFunc

Func _HTTP_GCI_AU3()
    Return _HTTP_CGI($AU3_Path&"\AutoIt3.exe", "/ErrorStdOut """ & $sLocalPath & """ >")
EndFunc

Func Debug($vLog, $nl = True, $ln = @ScriptLineNumber)
    Local Static $time = TimerInit()
    If @Compiled Then Return
    ConsoleWrite(StringFormat("(%04s) %s %+dms%s", $ln, $vLog, TimerDiff($time), $nl ? @CRLF : ""))
EndFunc

#cs
# Merge two header strings
#
# The header strings are allowed to contain the HTTP status line.
# Likewise this function also returns a header line, if one of the two headers contained one.
#
# @param string $headers1
# @param string $headers2
#
# @return string merged headers
#ce
Func _HTTP_MergeHttpHeaders($headers1, $headers2)
    Local $headers = ""
    ; NOTE: status line is not part of the "headers" directly, but part of head.
    Local $statusLine1 = _HTTP_ParseHttpStatusLine($headers1)
    Local $statusLine2 = _HTTP_ParseHttpStatusLine($headers2)
    $headers1 = _HTTP_ParseHttpHeaders($headers1)
    $headers2 = _HTTP_ParseHttpHeaders($headers2)
    For $i=0 To UBound($headers1, 1)-1 Step +2
        For $j=0 To UBound($headers2, 1)-1 Step +2
            If StringLower($headers1[$i]) = "set-cookie" Then ContinueLoop 1
            If StringLower($headers1[$i]) = StringLower($headers2[$j]) Then
                $headers &= StringFormat("%s: %s%s", $headers2[$j], $headers2[$j+1], @LF)
                ContinueLoop 2
            EndIf
            If StringLower($headers1[$i]) = "status" Then
                $statusLine1 = StringFormat("%s %s", 'HTTP/1.1', $headers1[$i+1])
                ContinueLoop 2
            EndIf
        Next
        $headers &= StringFormat("%s: %s%s", $headers1[$i], $headers1[$i+1], @LF)
    Next

    For $i=0 To UBound($headers2, 1)-1 Step +2
        For $j=0 To UBound($headers1, 1)-1 Step +2
            If StringLower($headers2[$i]) = "set-cookie" Then ContinueLoop 1
            If StringLower($headers1[$j]) = StringLower($headers2[$i]) Then ContinueLoop 2
            If StringLower($headers2[$i]) = "status" Then
                $statusLine2 = StringFormat("%s %s", 'HTTP/1.1', $headers2[$i+1])
                ContinueLoop 2
            EndIf
        Next
        $headers &= StringFormat("%s: %s%s", $headers2[$i], $headers2[$i+1], @LF)
    Next

    $statusLine2 = ($statusLine2 == "") ? $statusLine1 : $statusLine2
    $statusLine2 = ($statusLine2 == "") ? "HTTP/1.1 "&$HTTP_STATUS_200 : $statusLine2
    $headers = StringFormat('%s%s', $statusLine2, @LF) & $headers

    Return $headers
EndFunc

Func GetEnvString()
    Local $len = 0, $t
    Local $pEnv = GetEnvironmentStringsW()
    Local $pItem = $pEnv
    While 1
        $len = wcslen($pItem)
        If $len <= 0 Then ExitLoop
        $pItem = $pItem + $len * 2 + 2
    WEnd

    $len = int($pItem, 2)-int($pEnv, 2)
    local $tEnv = DllStructCreate("WCHAR["&($len/2)&"]")

    CopyMemory(DllStructGetPtr($tEnv, 1), $pEnv, $len)

    FreeEnvironmentStringsW($pEnv)

    Return $tEnv
EndFunc

Func GetEnvironmentStringsW()
    Local $aRet = DllCall('Kernel32.dll', 'ptr', 'GetEnvironmentStringsW')

    If @error <> 0 Then Return SetError(@error, @extended, 0)
    If $aRet[0] = 0 Then Return SetError(1, 0, 0)

    Return $aRet[0]
EndFunc

Func FreeEnvironmentStringsW($penv)
    Local $aRet = DllCall('Kernel32.dll', 'BOOLEAN', 'FreeEnvironmentStringsW', 'ptr', $penv)

    If @error <> 0 Then Return SetError(@error, @extended, 0)
    If $aRet[0] = 0 Then Return SetError(1, 0, 0)

    Return $aRet[0]
EndFunc

Func wcslen($pWString)
    Local $aCall = DllCall("ntdll.dll", "dword:cdecl", "wcslen", "ptr", $pWString)

    Return $aCall[0]
EndFunc

Func CopyMemory($destination, $source, $length)
    _MemMoveMemory($source, $destination, $length)

    If @error <> 0 Then Return SetError(@error, @extended, 0)

    Return 1
EndFunc

Func _HTTP_Server_Request_Handle($hSocket, $sRequest)
    $aRequest = _HTTP_ParseHttpRequest($sRequest)
    $aHeaders = _HTTP_ParseHttpHeaders($aRequest[$HttpRequest_HEADERS])
    $aUri = _HTTP_ParseURI($aRequest[$HttpRequest_URI])

    Debug("aUri[Path]: "&$aUri[$HttpUri_Path])
    ;Debug("aUri[Query]: "&$aUri[$httpUri_Query])
    ;Debug("LocalPath: " & _WinAPI_GetFullPathName($sRootDir & "\" & $aUri[$HttpUri_Path]))

    Switch $aRequest[$HttpRequest_METHOD]
        ;Case "HEAD"
            ;TODO
        Case "POST"
            ContinueCase
        Case "GET"
            $sRequest = $aUri[$HttpUri_Path]; let's see what file he actually wants
            ;FIXME: if codeblock below: disallows any dot files like .htaccess
            If StringInStr(StringReplace($sRequest,"\","/"), "/.") Then ; Disallow any attempts to go back a folder
                _HTTP_SendFileNotFoundError($aSocket[$x]) ; sends back an error
            Else
                $sLocalPath = _WinAPI_GetFullPathName($sRootDir & "\" & $sRequest);TODO: replace every instance of ($sRootDir & "\" & $sRequest) with $sLocalPath
                Select
                    Case StringInStr(FileGetAttrib($sLocalPath),"D")>0 ;user has requested a directory
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

                        If Not FileExists($sLocalPath&$sIndex) Then
                            If $bAllowIndexes Then;And FileExists(@ScriptDir & "\index.php") Then
                                _HTTP_IndexDir($aSocket[$x], $sLocalPath)
                            Else
                                _HTTP_SendHTML($aSocket[$x], "403 Forbidden", "403 Forbidden")
                            EndIf
                        Else
                            $sLocalPath = $sLocalPath&$sIndex
                            ContinueCase
                        EndIf
                    Case FileExists($sLocalPath) ; makes sure the file that the user wants exists
                        Local $iFileType = StringInStr($sLocalPath, ".", 0, -1)
                        Local $sFileType = $iFileType>0 ? StringMid($sLocalPath,$iFileType+1) : ""
                        If $sFileType = "php" And Not $PHP_Path = "" Then
                            _HTTP_GCI_PHP()
                        ElseIf $sFileType = "au3" And Not $AU3_Path = "" Then
                            _HTTP_GCI_AU3()
                        Else
                            _HTTP_SendFile($aSocket[$x], $sLocalPath, Default, "200 OK", True)
                        EndIf
                    Case Else
                        _HTTP_SendFileNotFoundError($aSocket[$x]) ; File does not exist, so we'll send back an error..
                EndSelect
            EndIf
        Case Else
            _HTTP_SendHTML($aSocket[$x], "", "501 Not Implemented")
    EndSwitch
EndFunc
