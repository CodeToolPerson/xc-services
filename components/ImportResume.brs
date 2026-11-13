function importRegistry() as object
    return CreateObject("roRegistrySection", "xc_import")
end function

function loadResume(playlistId as string) as object
    raw = importRegistry().Read(playlistId)
    if raw = invalid or raw = "" then return invalid
    parsed = ParseJson(raw)
    if parsed = invalid or type(parsed) <> "roAssociativeArray" then return invalid
    return parsed
end function

sub saveResume(playlistId as string, gen as integer, kindIndex as integer, catIndex as integer)
    record = {
        import_gen: gen
        kind_index: kindIndex
        cat_index: catIndex
        live_progress: asInt(m.top.liveProgress)
        vod_progress: asInt(m.top.vodProgress)
        series_progress: asInt(m.top.seriesProgress)
    }
    json = FormatJson(record)
    if json = invalid or json = "" then return
    registry = importRegistry()
    registry.Write(playlistId, json)
    registry.Flush()
end sub

sub clearResume(playlistId as string)
    registry = importRegistry()
    registry.Delete(playlistId)
    registry.Flush()
end sub
