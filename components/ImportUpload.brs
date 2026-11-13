function uploadRaw(path as string, body as string) as object
    if body = invalid or body = "" then body = "[]"
    return httpRaw("POST", importUrl(path), body, true)
end function

function uploadFile(path as string, filePath as string) as object
    return httpFile("POST", importUrl(path), filePath, true)
end function

function uploadStreamFile(apiPath as string, filePath as string) as object
    fs = CreateObject("roFileSystem")
    info = fs.Stat(filePath)
    size = 0
    if info <> invalid then size = asInt(info.size)
    if size < 16000000 then return uploadFile(apiPath, filePath)
    print "[ImportTask] split upload bytes="; size
    return splitAndUploadJsonArray(apiPath, filePath, size)
end function

' 整包 POST 会被截断。
function splitAndUploadJsonArray(apiPath as string, filePath as string, size as integer) as object
    ranges = jsonArrayPartRanges(filePath, size)
    if ranges = invalid then return transportFail("Unable to read cache file")
    if ranges.Count() = 0 then return uploadFile(apiPath, filePath)
    partPath = "tmp:/xc_" + m.playlistId + "_part.json"
    index = 0
    for each span in ranges
        index = index + 1
        deleteCacheFile(partPath)
        if writeJsonPart(partPath, filePath, asInt(span.from), asInt(span.to)) <> true then
            deleteCacheFile(partPath)
            return transportFail("Unable to write upload part")
        end if
        print "[ImportTask] upload part "; index; "/"; ranges.Count()
        uploaded = uploadFile(apiPath, partPath)
        deleteCacheFile(partPath)
        if uploaded.ok <> true then return uploaded
    end for
    return { ok: true, code: 200, message: "", superseded: false }
end function

function jsonArrayPartRanges(filePath as string, size as integer) as object
    ranges = []
    depth = 0
    inString = false
    escape = false
    startPos = -1
    filePos = 0
    while filePos < size
        n = 65536
        if filePos + n > size then n = size - filePos
        buf = CreateObject("roByteArray")
        if buf.ReadFile(filePath, filePos, n) <> true then return invalid
        count = buf.Count()
        i = 0
        while i < count
            b = buf[i]
            absIndex = filePos + i
            i = i + 1
            if inString = true then
                if escape = true then
                    escape = false
                else if b = 92 then
                    escape = true
                else if b = 34 then
                    inString = false
                end if
            else if b = 34 then
                inString = true
            else if b = 91 or b = 123 then
                if depth = 1 and b = 123 and startPos < 0 then startPos = absIndex
                depth = depth + 1
            else if b = 93 or b = 125 then
                depth = depth - 1
                if depth = 1 and b = 125 and startPos >= 0 and (absIndex + 1 - startPos) > 8000000 then
                    ranges.Push({ from: startPos, to: absIndex + 1 })
                    startPos = -1
                else if depth = 0 and b = 93 and startPos >= 0 then
                    ranges.Push({ from: startPos, to: absIndex })
                    startPos = -1
                end if
            end if
        end while
        filePos = filePos + n
        if (filePos mod 10485760) = 0 then print "[ImportTask] scan "; filePos
    end while
    return ranges
end function

function writeJsonPart(partPath as string, filePath as string, fromPos as integer, toPos as integer) as boolean
    length = toPos - fromPos
    if length < 0 then return false
    if length > 0 then
        lastByte = CreateObject("roByteArray")
        if lastByte.ReadFile(filePath, toPos - 1, 1) = true and lastByte.Count() = 1 and lastByte[0] = 44 then
            length = length - 1
        end if
    end if
    part = CreateObject("roByteArray")
    part.FromAsciiString("[")
    if length > 0 then
        body = CreateObject("roByteArray")
        if body.ReadFile(filePath, fromPos, length) <> true then return false
        part.Append(body)
    end if
    tail = CreateObject("roByteArray")
    tail.FromAsciiString("]")
    part.Append(tail)
    return part.WriteFile(partPath) = true
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
