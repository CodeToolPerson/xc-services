sub init()
    m.top.functionName = "exec"
end sub

sub exec()
    playlistId = trimText(m.top.playlistId)
    serverUrl = trimText(m.top.serverUrl)
    username = trimText(m.top.username)
    password = trimText(m.top.password)
    m3uUrl = trimText(m.top.m3uUrl)
    force = (m.top.force = true)
    apiBaseUrl = stripSlash(m.top.apiBaseUrl)

    xcReady = (serverUrl <> "" and username <> "" and password <> "")
    if playlistId = "" or apiBaseUrl = "" or (m3uUrl = "" and xcReady <> true) then
        failImport(0, "Missing import parameters")
        return
    end if

    m.playlistId = playlistId
    m.serverUrl = stripSlash(serverUrl)
    m.username = username
    m.password = password
    m.m3uUrl = m3uUrl
    m.apiBaseUrl = apiBaseUrl
    m.authHeader = trimText(m.top.authHeader)
    m.deviceId = trimText(m.top.deviceId)
    m.kinds = ["live", "vod", "series"]
    m.cachePath = "tmp:/xc_" + playlistId + "_streams.json"
    if m3uUrl <> "" then m.cachePath = "tmp:/m3u_" + playlistId + ".m3u"
    m.transferTimeoutMs = 600000
    m.panelRetries = 2
    deleteCacheFile(m.cachePath)

    setProgress("start", "", "Starting import", 0, 0, 0, 0)

    if force = true then clearResume(playlistId)

    gen = 0
    kindIndex = 0
    catIndex = 0
    resume = loadResume(playlistId)
    if force <> true and resume <> invalid then
        gen = asInt(resume.import_gen)
        kindIndex = asInt(resume.kind_index)
        catIndex = asInt(resume.cat_index)
        if resume.live_progress <> invalid then m.top.liveProgress = asInt(resume.live_progress)
        if resume.vod_progress <> invalid then m.top.vodProgress = asInt(resume.vod_progress)
        if resume.series_progress <> invalid then m.top.seriesProgress = asInt(resume.series_progress)
    end if

    if gen <= 0 then
        started = beginImport()
        if started.ok <> true then
            failImport(started.code, started.message)
            return
        end if
        gen = started.gen
        kindIndex = 0
        catIndex = 0
        saveResume(playlistId, gen, 0, 0)
    end if

    while true
        result = runImport(gen, kindIndex, catIndex)
        if result.ok = true then
            clearResume(playlistId)
            m.top.counts = result.counts
            m.top.statusCode = 200
            m.top.errorMessage = ""
            setProgress("complete", "", "Import complete", 100, 100, 100, 100)
            m.top.done = true
            return
        end if
        if result.superseded = true then
            clearResume(playlistId)
            started = beginImport()
            if started.ok <> true then
                failImport(started.code, started.message)
                return
            end if
            gen = started.gen
            kindIndex = 0
            catIndex = 0
            saveResume(playlistId, gen, 0, 0)
        else
            saveResume(playlistId, gen, result.kindIndex, result.catIndex)
            failImport(result.code, result.message)
            return
        end if
    end while
end sub

function runImport(gen as integer, startKind as integer, startCat as integer) as object
    if m.m3uUrl <> "" then return runM3UImport(gen)
    kindIndex = startKind
    catIndex = startCat
    if kindIndex < 0 then kindIndex = 0
    if catIndex < 0 then catIndex = 0

    while kindIndex < m.kinds.count()
        kind = m.kinds[kindIndex]
        cats = ensureCategories(gen, kind, kindIndex)
        if cats.ok <> true then
            return failResult(cats.code, cats.message, kindIndex, 0, cats.superseded)
        end if

        bulk = importKindStreamsBulk(gen, kind, kindIndex)
        if bulk.ok <> true then
            return failResult(bulk.code, bulk.message, kindIndex, 0, bulk.superseded)
        end if
        markKindDone(kind)
        kindIndex = kindIndex + 1
        catIndex = 0
        saveResume(m.playlistId, gen, kindIndex, 0)
    end while

    setProgress("complete", "", "Finalizing import", 99, 100, 100, 100)
    finished = completeImport(gen)
    if finished.ok <> true then
        return failResult(finished.code, finished.message, m.kinds.count(), 0, finished.superseded)
    end if
    return {
        ok: true
        counts: finished.counts
        kindIndex: m.kinds.count()
        catIndex: 0
        code: 200
        message: ""
        superseded: false
    }
end function

function runM3UImport(gen as integer) as object
    path = m.cachePath
    setProgress("streams", "live", "Fetching M3U playlist", 10, 0, 0, 0)
    fetched = fetchM3UToFile(m.m3uUrl, path)
    if fetched.ok <> true then
        deleteCacheFile(path)
        return failResult(fetched.code, fetched.message, 0, 0, false)
    end if
    setProgress("upload", "live", "Uploading M3U playlist", 60, 0, 0, 0)
    uploaded = httpFile("POST", importUrl(importM3UPath(m.playlistId, gen)), path, true, "text/plain")
    deleteCacheFile(path)
    if uploaded.ok <> true then
        return failResult(uploaded.code, uploaded.message, 0, 0, uploaded.superseded)
    end if
    setKindProgress("live", 100)
    setKindProgress("vod", 100)
    setKindProgress("series", 100)
    setProgress("complete", "", "Finalizing import", 99, 100, 100, 100)
    finished = completeImport(gen)
    if finished.ok <> true then
        return failResult(finished.code, finished.message, 0, 0, finished.superseded)
    end if
    return { ok: true, counts: finished.counts, kindIndex: 0, catIndex: 0, code: 200, message: "", superseded: false }
end function

function ensureCategories(gen as integer, kind as string, kindIndex as integer) as object
    setProgress("categories", kind, "Fetching " + kind + " categories", kindProgress(kindIndex, 0), progressFor("live"), progressFor("vod"), progressFor("series"))
    catsRaw = fetchPanel(kindCategoriesAction(kind), "")
    if catsRaw.ok <> true then
        return { ok: false, code: catsRaw.code, message: catsRaw.message, superseded: false }
    end if
    uploaded = uploadRaw(importCategoriesPath(m.playlistId, gen, kind), catsRaw.body)
    if uploaded.ok <> true then
        return { ok: false, code: uploaded.code, message: uploaded.message, superseded: uploaded.superseded }
    end if
    catsRaw.body = ""
    saveResume(m.playlistId, gen, kindIndex, 0)
    return { ok: true, code: 200, message: "", superseded: false }
end function

function importKindStreamsBulk(gen as integer, kind as string, kindIndex as integer) as object
    setProgress("streams", kind, "Fetching all " + kind + " streams", kindProgress(kindIndex, 10), progressFor("live"), progressFor("vod"), progressFor("series"))
    path = m.cachePath
    fetched = fetchPanelToFile(kindStreamsAction(kind), "", path)
    if fetched.ok <> true then
        deleteCacheFile(path)
        return { ok: false, code: fetched.code, message: fetched.message, superseded: false }
    end if
    setProgress("upload", kind, "Uploading all " + kind + " streams", kindProgress(kindIndex, 60), progressFor("live"), progressFor("vod"), progressFor("series"))
    uploaded = uploadFile(importStreamsPath(m.playlistId, gen, kind), path)
    deleteCacheFile(path)
    if uploaded.ok <> true then
        return { ok: false, code: uploaded.code, message: uploaded.message, superseded: uploaded.superseded }
    end if
    setKindProgress(kind, 100)
    setProgress("upload", kind, "Uploaded all " + kind + " streams", kindProgress(kindIndex, 100), progressFor("live"), progressFor("vod"), progressFor("series"))
    return { ok: true, code: 200, message: "", superseded: false }
end function

function beginImport() as object
    setProgress("begin", "", "Creating import session", 1, 0, 0, 0)
    res = httpJson("POST", importUrl(importBeginPath(m.playlistId)), "", true)
    if res.ok <> true then return res
    data = res.data
    gen = 0
    if data <> invalid then gen = asInt(data.import_gen)
    if gen <= 0 then
        return { ok: false, code: res.code, message: "Missing import_gen", gen: 0 }
    end if
    return { ok: true, code: res.code, message: "", gen: gen }
end function

function completeImport(gen as integer) as object
    res = httpJson("POST", importUrl(importCompletePath(m.playlistId, gen)), "", true)
    if res.ok <> true then return res
    counts = { live: 0, vod: 0, series: 0, catchup: 0 }
    data = res.data
    if data <> invalid then
        counts.live = asInt(data.live)
        counts.vod = asInt(data.vod)
        counts.series = asInt(data.series)
        counts.catchup = asInt(data.catchup)
    end if
    return { ok: true, code: res.code, message: "", counts: counts, superseded: false }
end function

function kindCategoriesAction(kind as string) as string
    if kind = "vod" then return "get_vod_categories"
    if kind = "series" then return "get_series_categories"
    return "get_live_categories"
end function

function kindStreamsAction(kind as string) as string
    if kind = "vod" then return "get_vod_streams"
    if kind = "series" then return "get_series"
    return "get_live_streams"
end function

function failResult(code as integer, message as string, kindIndex as integer, catIndex as integer, superseded as boolean) as object
    return {
        ok: false
        code: code
        message: message
        kindIndex: kindIndex
        catIndex: catIndex
        superseded: superseded
        counts: {}
    }
end function

sub failImport(code as integer, message as string)
    if message = invalid then message = "Import failed"
    m.top.statusCode = code
    m.top.errorMessage = message
    setProgress("error", m.top.kind, message, m.top.progress, m.top.liveProgress, m.top.vodProgress, m.top.seriesProgress)
    m.top.done = true
end sub

sub setProgress(phase as string, kind as string, message as string, progress as integer, liveP as integer, vodP as integer, seriesP as integer)
    m.top.phase = phase
    m.top.kind = kind
    m.top.message = message
    m.top.progress = progress
    m.top.liveProgress = liveP
    m.top.vodProgress = vodP
    m.top.seriesProgress = seriesP
    print "[ImportTask] "; phase; " "; kind; " "; message; " "; progress
end sub

sub markKindDone(kind as string)
    setKindProgress(kind, 100)
end sub

sub setKindProgress(kind as string, value as integer)
    if value < 0 then value = 0
    if value > 100 then value = 100
    if kind = "live" then m.top.liveProgress = value
    if kind = "vod" then m.top.vodProgress = value
    if kind = "series" then m.top.seriesProgress = value
end sub

function progressFor(kind as string) as integer
    if kind = "live" then return asInt(m.top.liveProgress)
    if kind = "vod" then return asInt(m.top.vodProgress)
    if kind = "series" then return asInt(m.top.seriesProgress)
    return 0
end function

function kindProgress(kindIndex as integer, within as integer) as integer
    base = kindIndex * 30
    if within < 0 then within = 0
    if within > 100 then within = 100
    value = base + Int(within * 0.3)
    if value > 99 then value = 99
    return value
end function
