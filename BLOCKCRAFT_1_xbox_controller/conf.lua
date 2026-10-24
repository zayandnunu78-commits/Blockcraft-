-- "love . --server" starts the multiplayer server: no window, no graphics.
function love.conf(t)
    local server = false
    for _, a in pairs(arg or {}) do
        if a == "--server" then server = true end
    end

    if server then
        t.identity = "blockcraft_server"
        t.window = nil
        for _, m in ipairs({"audio", "graphics", "image", "joystick", "keyboard", "mouse",
                            "physics", "sound", "touch", "video", "window"}) do
            t.modules[m] = false
        end
        return
    end

    t.window.title = "Blockcraft 1"
    t.window.width = 800
    t.window.height = 600
    t.window.depth = 24 -- Enables 3D rendering depth!
end
