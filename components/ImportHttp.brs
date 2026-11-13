function fetchPanel(action as string, categoryId as string) as object
    return httpRawRetry("GET", panelUrl(action, categoryId), "", false)
end function

function fetchPanelToFile(action as string, categoryId as string, filePath as string) as object
    attempt = 0
    last = invalid
    while attempt < m.panelRetries
        attempt = attempt + 1
        deleteCacheFile(filePath)
        last = httpGetToFile(panelUrl(action, categoryId), filePath, false)
        if last.ok = true and fileEndsWithSquareBracket(filePath) <> true then
            print "[ImportTask] panel file truncated"
            last = transportFail("Incomplete panel file")
        end if
        if last.ok = true then return last
        print "[ImportTask] panel file retry="; attempt; " code="; last.code; " "; last.message
        sleep(600 * attempt)
    end while
    if last <> invalid then return last
    return transportFail("Bulk download failed")
end function

function fetchM3UToFile(url as string, filePath as string) as object
    attempt = 0
    last = invalid
    while attempt < m.panelRetries
        attempt = attempt + 1
        deleteCacheFile(filePath)
        last = httpGetToFile(url, filePath, false)
        if last.ok = true and fileStartsWithM3U(filePath) <> true then
            print "[ImportTask] m3u header missing"
            return transportFail("Invalid M3U file")
        end if
        if last.ok = true and last.length > 0 then
            info = CreateObject("roFileSystem").Stat(filePath)
            if info = invalid or asInt(info.size) <> last.length then
                print "[ImportTask] m3u file truncated"
                last = transportFail("Incomplete M3U file")
            end if
        end if
        if last.ok = true then return last
        print "[ImportTask] m3u retry="; attempt; " code="; last.code; " "; last.message
        sleep(600 * attempt)
    end while
    if last <> invalid then return last
    return transportFail("M3U download failed")
end function

function httpRawRetry(method as string, url as string, body as string, withAuth as boolean) as object
    attempt = 0
    last = invalid
    while attempt < m.panelRetries
        attempt = attempt + 1
        last = httpRaw(method, url, body, withAuth)
        if last.ok = true then return last
        if last.superseded = true then return last
        if withAuth = true and last.code >= 400 and last.code < 500 and last.code <> 408 then return last
        print "[ImportTask] retry="; attempt; " code="; last.code; " "; last.message
        sleep(400 * attempt)
    end while
    return last
end function

function panelUrl(action as string, categoryId as string) as string
    xfer = CreateObject("roUrlTransfer")
    userEsc = xfer.Escape(m.username)
    passEsc = xfer.Escape(m.password)
    url = m.serverUrl + "/player_api.php?username=" + userEsc + "&password=" + passEsc + "&action=" + action
    if categoryId <> invalid and categoryId <> "" then
        url = url + "&category_id=" + xfer.Escape(categoryId + "")
    end if
    return url
end function

function httpJson(method as string, url as string, body as string, withAuth as boolean) as object
    res = httpRaw(method, url, body, withAuth)
    if res.ok <> true then return res
    data = {}
    if res.parsed <> invalid and type(res.parsed) = "roAssociativeArray" then
        if res.parsed.data <> invalid then data = res.parsed.data
    end if
    res.data = data
    return res
end function

function httpRaw(method as string, url as string, body as string, withAuth as boolean) as object
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.EnableEncodings(true)
    xfer.RetainBodyOnError(true)
    xfer.AddHeader("Accept", "application/json")
    xfer.AddHeader("Content-Type", "application/json")
    if withAuth = true then applyAuth(xfer)
    xfer.SetRequest(method)
    xfer.SetUrl(url)

    print "[ImportTask] "; method; " "; logUrl(url)
    methodName = UCase(method)
    if methodName = "GET" or methodName = "DELETE" then
        sent = xfer.AsyncGetToString()
    else
        payload = body
        if payload = invalid then payload = ""
        sent = xfer.AsyncPostFromString(payload)
    end if
    if sent <> true then
        return transportFail("Unable to send request")
    end if
    return waitTransfer(xfer, port, false)
end function

function httpGetToFile(url as string, filePath as string, withAuth as boolean) as object
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.EnableEncodings(true)
    xfer.RetainBodyOnError(true)
    xfer.AddHeader("Accept", "application/json")
    if withAuth = true then applyAuth(xfer)
    xfer.SetRequest("GET")
    xfer.SetUrl(url)
    print "[ImportTask] GET-FILE "; logUrl(url)
    if xfer.AsyncGetToFile(filePath) <> true then
        return transportFail("Unable to download to cache")
    end if
    return waitTransfer(xfer, port, true)
end function

function httpFile(method as string, url as string, filePath as string, withAuth as boolean, contentType = "application/json" as string) as object
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.RetainBodyOnError(true)
    xfer.AddHeader("Accept", "application/json")
    xfer.AddHeader("Content-Type", contentType)
    if withAuth = true then applyAuth(xfer)
    xfer.SetRequest(method)
    xfer.SetUrl(url)
    print "[ImportTask] POST-FILE "; logUrl(url)
    if xfer.AsyncPostFromFile(filePath) <> true then
        return transportFail("Unable to upload cache file")
    end if
    return waitTransfer(xfer, port, false)
end function

function waitTransfer(xfer as object, port as object, fileOnly as boolean) as object
    msg = wait(m.transferTimeoutMs, port)
    if msg = invalid then
        xfer.AsyncCancel()
        return transportFail("Request timed out")
    end if
    if type(msg) <> "roUrlEvent" then
        return transportFail("Unexpected response")
    end if
    code = msg.GetResponseCode()
    raw = ""
    if fileOnly <> true then raw = msg.GetString()
    print "[ImportTask] status="; code
    superseded = false
    message = ""
    parsed = invalid
    if raw <> invalid and raw <> "" then
        parsed = ParseJson(raw)
        if parsed <> invalid and type(parsed) = "roAssociativeArray" then
            if parsed.message <> invalid then message = trimText(parsed.message)
        end if
    end if
    if code = 409 then
        if message = "" then message = "import_superseded"
        if Instr(1, LCase(message), "import_superseded") > 0 then superseded = true
    end if
    if code < 200 or code >= 300 then
        if message = "" then message = "Request failed (" + code.toStr() + ")"
        return { ok: false, code: code, message: message, superseded: superseded, body: raw, parsed: parsed }
    end if
    if fileOnly = true then
        return { ok: true, code: code, message: "", superseded: false, body: "", parsed: invalid, length: headerLength(msg) }
    end if
    if raw = invalid or raw = "" then raw = "[]"
    return { ok: true, code: code, message: "", superseded: false, body: raw, parsed: parsed }
end function

function headerLength(msg as object) as integer
    headers = msg.GetResponseHeaders()
    if headers = invalid then return 0
    for each key in headers
        if LCase(key) = "content-length" then return asInt(headers[key])
    end for
    return 0
end function

sub applyAuth(xfer as object)
    if m.authHeader <> "" then xfer.AddHeader("Authorization", m.authHeader)
    if m.deviceId <> "" then xfer.AddHeader("X-Device-Id", m.deviceId)
end sub

function importBeginPath(playlistId as string) as string
    return "/playlists/" + playlistId + "/import"
end function

function importCategoriesPath(playlistId as string, gen as integer, kind as string) as string
    return "/playlists/" + playlistId + "/import/" + gen.toStr() + "/categories/" + kind
end function

function importStreamsPath(playlistId as string, gen as integer, kind as string) as string
    return "/playlists/" + playlistId + "/import/" + gen.toStr() + "/streams/" + kind
end function

function importM3UPath(playlistId as string, gen as integer) as string
    return "/playlists/" + playlistId + "/import/" + gen.toStr() + "/m3u"
end function

function importCompletePath(playlistId as string, gen as integer) as string
    return "/playlists/" + playlistId + "/import/" + gen.toStr() + "/complete"
end function

function importUrl(path as string) as string
    return m.apiBaseUrl + path
end function

function logUrl(url as string) as string
    if url = invalid then return ""
    q = Instr(1, url, "?")
    if q < 1 then return url
    return Left(url, q - 1)
end function

function transportFail(message as string) as object
    return { ok: false, code: 0, message: message, superseded: false, body: "", parsed: invalid }
end function
