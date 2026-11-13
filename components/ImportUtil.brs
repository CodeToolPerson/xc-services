sub deleteCacheFile(path as string)
    fs = CreateObject("roFileSystem")
    if fs = invalid then return
    if fs.Exists(path) = true then fs.Delete(path)
end sub

function stripSlash(value as string) as string
    text = trimText(value)
    while Len(text) > 0 and Right(text, 1) = "/"
        text = Left(text, Len(text) - 1)
    end while
    return text
end function

function trimText(value as dynamic) as string
    if value = invalid then return ""
    text = ""
    valueType = type(value)
    if valueType = "String" or valueType = "roString" then
        text = value
    else if GetInterface(value, "ifToStr") <> invalid then
        text = value.toStr()
    else
        return ""
    end if
    while Len(text) > 0 and Left(text, 1) = " "
        text = Mid(text, 2)
    end while
    while Len(text) > 0 and Right(text, 1) = " "
        text = Left(text, Len(text) - 1)
    end while
    return text
end function

function asInt(value as dynamic) as integer
    if value = invalid then return 0
    if GetInterface(value, "ifInt") <> invalid then return value
    if GetInterface(value, "ifLongInt") <> invalid then return value
    if GetInterface(value, "ifFloat") <> invalid then return Int(value)
    if GetInterface(value, "ifString") <> invalid then
        if value = "" then return 0
        return Val(value)
    end if
    return 0
end function
