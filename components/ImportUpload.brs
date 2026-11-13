function uploadRaw(path as string, body as string) as object
    if body = invalid or body = "" then body = "[]"
    return httpRaw("POST", importUrl(path), body, true)
end function

function uploadFile(path as string, filePath as string) as object
    return httpFile("POST", importUrl(path), filePath, true)
end function

function fileEndsWithSquareBracket(path as string) as boolean
    fs = CreateObject("roFileSystem")
    info = fs.Stat(path)
    if info = invalid then return false
    size = asInt(info.size)
    if size <= 0 then return false
    n = 64
    if size < n then n = size
    bytes = CreateObject("roByteArray")
    if bytes.ReadFile(path, size - n, n) <> true then return false
    text = bytes.ToAsciiString()
    if text = invalid then return false
    i = Len(text)
    while i > 0
        ch = Mid(text, i, 1)
        if ch <> " " and ch <> Chr(10) and ch <> Chr(13) and ch <> Chr(9) then
            return ch = "]"
        end if
        i = i - 1
    end while
    return false
end function
