#AuotIt HTTP Server

My additions/modifications to [__jvanegmond__](https://www.autoitscript.com/forum/profile/10412-jvanegmond/)'s POST Server

The original source can be found [__here__](https://www.autoitscript.com/forum/topic/68851-powerful-http-server-in-pure-autoit/)

Added:

- GET variables are now supported, instead for being included as the file name
- PHP support
- More MIME types
- 404 status code when returning the 404 response
- Default index file if trying to access only folder path, not just on root
- Support for multiple index files, a bit like apatche's DirectoryIndex
- 403 status code if no index is found, instead of sending a stream of no file
- Removed double newline at end of "_HTTP_SendData" it appended to any file and seemed to not be needed.
- Added if statment with continue case in case the PHP path is not set or does not exist(when loading settings)

Looking into:

- gzip
- MySQL
- If-Modified-Since header
- 401 status code, possibly followed by a 403 status code
- server URI does not currently support space (%20) and other special characters
- HEAD Method support
- Maybe adding __FindFirstChangeNotification__ with server to watch __settings.ini__ file for change, to avoid restarting to apply the changes.
