' Pure file-info adapter. No SceneGraph, roFileSystem or network calls.
' roFileSystem.Stat() is documented to return an associative array, but during
' an async transfer it can come back without a populated size; comparing that
' invalid value against a number raises a runtime Type Mismatch.
function statSize(info as dynamic) as dynamic
    if info = invalid then return invalid
    size = info.size
    if size = invalid then return invalid
    if Type(size) <> "Integer" and Type(size) <> "LongInteger" then return invalid
    if size < 0 then return invalid
    return size
end function
