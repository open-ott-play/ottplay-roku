sub Main()
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("MainScene")
    scene.ObserveField("persistState", port)
    scene.ObserveField("exitRequested", port)
    section = CreateObject("roRegistrySection", "ottplay.roku.v1")
    saved = ""
    if section.Exists("state") then saved = section.Read("state")
    screen.Show()
    scene.initialState = saved
    while true
        event = Wait(0, port)
        if Type(event) = "roSGScreenEvent"
            if event.IsScreenClosed() then return
        else if Type(event) = "roSGNodeEvent"
            if event.GetField() = "exitRequested" and event.GetData() = true then return
            if event.GetField() = "persistState"
                value = event.GetData()
                if Type(value) = "roString" or Type(value) = "String"
                    if Len(value) <= 24576
                        ok = section.Write("state", value)
                        if ok then ok = section.Flush()
                        scene.persistenceOk = ok
                    else
                        scene.persistenceOk = false
                    end if
                end if
            end if
        end if
    end while
end sub
