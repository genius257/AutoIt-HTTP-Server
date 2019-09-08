# AutoIt HTTP Server

This server does not have security as a priority, therefore it is NOT advised to use this for anything but local hosting!

[![](https://img.shields.io/github/license/genius257/AutoIt-HTTP-Server.svg?style=flat-square)](LICENSE)

My additions/modifications to [__jvanegmond__](https://www.autoitscript.com/forum/profile/10412-jvanegmond/)'s POST Server

The original source can be found [__here__](https://www.autoitscript.com/forum/topic/68851-powerful-http-server-in-pure-autoit/)

Added:

- Query strings are now supported, instead for being included as the file name/path
- PHP support
- More MIME types
- 404 status code when returning the 404 response
- Default index file if trying to access only folder path, not just on root
- Support for multiple index files, a bit like apatche's DirectoryIndex
- 403 status code if no index is found, instead of sending a stream of no file
- Removed double newline at end of "_HTTP_SendData" it appended to any file and seemed to not be needed.
- Added [If...Then](https://www.autoitscript.com/autoit3/docs/keywords/If.htm) statment with [ContinueCase](https://www.autoitscript.com/autoit3/docs/keywords/ContinueCase.htm) in case required PHP files is not present
- Server URI does now support percent encoding
- AU3 CGI support

Looking into:

- gzip
- MySQL
- If-Modified-Since header
- 401 status code, possibly followed by a 403 status code
- HEAD Method support
- Maybe adding [FindFirstChangeNotification](https://www.autoitscript.com/autoit3/docs/libfunctions/_WinAPI_FindFirstChangeNotification.htm) with server to watch __settings.ini__ file for changes, to avoid restarting to apply the changes.
