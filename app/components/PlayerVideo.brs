function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back"
        m.top.backRequested = true
        return true
    else if key = "options"
        m.top.optionsRequested = true
        return true
    end if
    ' Transport and seek keys retain native Video behavior.
    return false
end function
