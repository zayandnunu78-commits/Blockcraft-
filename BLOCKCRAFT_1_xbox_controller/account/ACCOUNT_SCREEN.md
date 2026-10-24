# Blockcraft account screen

This folder contains a reusable LÖVE/Lua account UI for Blockcraft 1. It is intentionally separate from gameplay, multiplayer, and save files.

It is now wired into the game: the title menu has an **Account** button, and the new `account` game state routes drawing, mouse, touch, keyboard, and text-input events to this screen. `Play Offline` returns to the existing local-world flow.

## Files

- `account_screen.lua` — responsive login/registration screen with desktop keyboard and mobile touch input.
- `auth_interface.lua` — validation and backend-neutral authentication adapter.
- `firebase_config.lua` — Firebase project settings; the supplied Realtime Database URL is already filled in.
- `firebase_rest.lua` — main-thread bridge that keeps callbacks and channels safe for the UI.
- `firebase_thread.lua` — background HTTPS worker for Firebase Authentication and Realtime Database.

## Integration

The existing integration is in `main.lua` and `menu.lua`. The game constructs `FirebaseRest`, wraps it with `AuthInterface`, and updates its response channel every frame. No gameplay, multiplayer, or save code needs to change.

Before testing online login, open `account/firebase_config.lua` and replace `PASTE_FIREBASE_WEB_API_KEY_HERE` with the **Web API key** from Firebase Console → Project settings → General → Your web app. The Realtime Database URL is already configured as:

```text
https://blockcraft-14000-default-rtdb.firebaseio.com
```

The key is a client identifier. Never put a Firebase service-account private key in the game.

Require the modules from the project root:

```lua
local AuthInterface = require("account.auth_interface")
local AccountScreen = require("account.account_screen")

local firebase = require("account.firebase_rest").new()
local auth = AuthInterface.new(firebase)
local account = AccountScreen.new{
  auth = auth,
  onAuthenticated = function(session)
    -- Store the returned Firebase ID token/session in a session manager.
    -- Then return to the normal Blockcraft menu.
    print("Logged in", session and session.uid)
  end,
  onOffline = function()
    -- Enter the existing offline/local flow. Do not create a fake account.
    print("Continuing offline")
  end,
}
```

Forward the screen from the host state that owns the account screen:

```lua
function love.update(dt)
  if account:isOpen() then account:update(dt) end
end

function love.draw()
  -- draw the normal background first
  if account:isOpen() then account:draw() end
end

function love.mousepressed(x, y, button)
  if account:isOpen() and button == 1 then
    account:pressed(x, y)
    return
  end
  -- existing Blockcraft mouse handling
end

function love.touchpressed(id, x, y)
  if account:isOpen() then
    account:pressed(x, y)
    return
  end
  -- existing Blockcraft touch handling
end

function love.textinput(text)
  if account:isOpen() then account:textinput(text); return end
end

function love.keypressed(key)
  if account:isOpen() then account:keypressed(key); return end
end
```

Open the screen from the normal menu with `account:openLogin()` or `account:openRegister()`. The screen calls `onAuthenticated` only after the injected adapter reports success. `Play Offline` calls `onOffline` and never pretends that an account login occurred.

## FastAPI/Firebase adapter contract

Keep Firebase credentials and privileged service-account keys on the FastAPI server, never in the game client. The client-side adapter should call the FastAPI endpoints and invoke the UI callback:

```lua
local backend = {}

function backend.login(payload, done)
  -- POST /auth/login with payload.username and payload.password.
  -- On HTTP 200: done(true, {uid = response.uid, idToken = response.idToken})
  -- On error:    done(false, response.message)
end

function backend.register(payload, done)
  -- POST /auth/register with username, email, password.
end

function backend.resetPassword(payload, done)
  -- POST /auth/forgot-password with payload.email.
end

local auth = AuthInterface.new(backend)
```

Recommended server behavior:

1. FastAPI receives the request over HTTPS.
2. Firebase Authentication creates or verifies the user.
3. The server returns only the minimum session/profile data needed by the game.
4. Blockcraft 1 and 2 use the same Firebase `uid`, while game-specific worlds and progression remain separated by `game_id`.
5. Validate the Firebase ID token on every protected world/multiplayer request.

The Firebase adapter uses `love.thread` so HTTPS work never blocks the game loop. It tries the `https` module first, then LuaSec's `ssl.https` fallback. LÖVE 12 includes `https`; LÖVE 11.4+ can use the separately compiled `lua-https` module (`https.so`/`https.dll`) or LuaSec. The game does not need LÖVE 12 installed inside a LÖVE 11 project.

### Mobile build requirement

The screenshot error means the mobile LÖVE runtime itself was built without an HTTPS module. The `.love` game archive cannot add native TLS support after the mobile runtime has been compiled. Rebuild the mobile LÖVE app with `lua-https` included (the module is compiled for the target platform), or use a LÖVE 12 runtime that already includes `https`. Do not replace Firebase HTTPS with plain `http`.

The adapter uses Firebase Authentication REST endpoints for email/password sign-in, registration, and password reset. Registration also writes `/users/{uid}` and `/usernames/{username}` to the Realtime Database. Configure database rules so authenticated users can only access their own records and so username lookup is supported by your chosen rules.

## Visual and input behavior

The screen uses the existing Blockcraft dark, brick-red, gold-highlighted visual language. Layout dimensions are calculated from the current window size, fields and buttons have large touch targets, `Tab` changes fields on desktop, `Enter` submits, and `Escape` closes the screen.
