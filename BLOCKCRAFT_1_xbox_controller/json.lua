-- json.lua: the JSON library used by main.lua (only json.decode(string) is needed).
-- This is a small decoder that follows rxi/json.lua's API, so you can overwrite
-- this file with rxi's json.lua (https://github.com/rxi/json.lua) and nothing else changes.
return require "modsys.json"
