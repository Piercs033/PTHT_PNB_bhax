-- =======================================================================
-- PIERS BOT: NATIVE BOTHAX CONTROLLER (PC & MOBILE OPTIMIZED)
-- =======================================================================

-- [0. BOTHAX & GROWLAUNCHER HOOK SHIM]
local _native_addHook = addHook or AddHook
local _native_removeHook = removeHook or RemoveHooks

local function wrap_variant_hook(func)
    return function(var, pkt)
        local ok, res = pcall(function()
            if type(var) == "table" and not var[0] then
                setmetatable(var, {
                    __index = function(t, k)
                        if k == 0 then return t.v1 end
                        if k == 1 then return t.v2 end
                        if k == 2 then return t.v3 end
                        if k == 3 then return t.v4 end
                        if k == 4 then return t.v5 end
                        return rawget(t, k)
                    end
                })
            end
            return func(var, pkt)
        end)
        if ok and res ~= nil then
            return res
        end
    end
end

function RegisterBothaxHook(ev_name, fn)
    local ev = string.lower(ev_name)
    if addHook then
        if ev == 'ondraw' or ev == 'ondrawimgui' then
            addHook(fn, 'ondrawimgui')
        elseif ev == 'onvariant' then
            addHook(wrap_variant_hook(fn), 'onvariant')
        else
            addHook(fn, ev)
        end
    elseif AddHook then
        if ev == 'ondraw' or ev == 'ondrawimgui' then
            AddHook("OnDraw", "piers_ondraw_gui", fn)
            AddHook("OnDrawImGui", "piers_ondrawimgui", fn)
        elseif ev == 'onvariant' then
            AddHook("OnVariant", "piers_onvar_hook", wrap_variant_hook(fn))
        else
            AddHook(ev_name, "piers_custom_hook", fn)
        end
    end
end

-- [1. PENGATURAN UMUM / DEFAULTS (BISA DIUBAH LANGSUNG DARI GUI)]
local TARGET_WORLD      = ""       -- Nama world target (Kosong = Otomatis mendeteksi world saat ini)
local PTHT_START_X      = 190      -- Kolom awal menanam (190)
local PTHT_END_X        = 0        -- Kolom akhir menanam (0)
local PTHT_START_Y      = 188      -- Baris Y awal (Bawah: 188 / PlantY)
local PTHT_END_Y        = 0        -- Baris Y akhir (Atas: 0)
local PTHT_MAG_BG       = 11858    -- Background ID tempat Magplant SEED ditaruh
local PNB_MAG_BG        = 12840    -- Background ID tempat Magplant BLOCK ditaruh
local TELEPHONE_NUMBER  = "53785"  -- Nomor Telepon Converter DL/BGL
local SEED_ITEM_ID      = 16707    -- Item ID Bibit (Default: 16707 Pot O' Gems Seed)
local BLOCK_ITEM_ID     = 16706    -- Item ID Blok (Default: 16706 Pot O' Gems Block)
local DISCORD_WEBHOOK_URL = ""     -- URL Webhook Discord untuk pelaporan

local REMOTE_ID         = 5640     -- Magplant Remote
local MAGPLANT_ID       = 5638     -- Magplant 5000
local PUNCH_VALUE       = 18       -- Punch Block ID

local DelayPlant        = 90       -- Jeda tembak bibit aman (default: 90ms)
local DelayHarvest      = 140      -- Jeda punch panen baris aman (default: 140ms)
local DelayFindPath     = 85       -- Kecepatan gerak TelePath aman (default: 85ms)
local DelayStepPath     = 85       -- Sinkronisasi step gerak aman (default: 85ms)
local PlantFar          = 10       -- Jangkauan MRAY (10 tile per kolom)
local AutoAdaptSpeed    = true     -- Auto-downgrade kecepatan jika ter-kick
local need_buy_cheat    = false    -- Flag pemicu beli cheat in-game
local last_buycheat_time = 0       -- Anti-spam cooldown timer buycheat (detik)
local CONFIG_FILE_NAME  = "piers_pnb_default.json"

-- [2. STATE KONTROL GUI]
local CURRENT_MODE          = "IDLE"   -- "IDLE", "PTHT", "PNB"
local PNB_LOCK_X            = 0        -- Koordinat X PNB terkunci
local PNB_LOCK_Y            = 0        -- Koordinat Y PNB terkunci
local TEL_X                 = 0        -- Koordinat X Telepon Converter (internal, otomatis scan)
local TEL_Y                 = 0        -- Koordinat Y Telepon Converter (internal, otomatis scan)
local AutoBuyDL_Checked     = false    -- Default: FALSE (Tidak dicentang di awal)
local need_buy_dl_now       = false    -- Pemicu beli DL instan realtime dari GUI
local SprayUWS_Checked      = false    -- Default: FALSE (Checkbox Semprot UWS)
local PlantReverse_Checked  = false    -- Default: FALSE (Maju: 0 -> 190) = Akun 1. TRUE (Mundur: 190 -> 0) = Akun 2
local IS_GHOST_ON           = nil      -- Status riil fisik Ghost dari server (nil = belum sinkron di awal)
local pnb_initialized       = false
local current_mag_idx       = 1
local captured_dialog       = ""
local is_mag_empty          = false
local ptht_seed_remote_verified = false
local last_radio_off_time   = 0        -- Cooldown timer anti-spam /radio
local last_ghost_toggle_time = 0       -- Cooldown anti-spam /ghost
local promo_dialog_shown = false  -- Flag: dialog promo hanya muncul sekali per session
local silent_profile_probe  = false    -- Flag: hanya blokir dialog jika dipicu oleh probe internal bot
local ALL_SEED_MAGS         = {}
local ALL_BLOCK_MAGS        = {}
local cycle_counter         = 0
local DelayUWS              = 3000     -- Jeda semprot UWS (3 detik)
local last_activity_time    = os and os.time and os.time() or 0
local last_recorded_gems    = 0

function MarkActivity()
    last_activity_time = os and os.time and os.time() or 0
end

function CheckWatchdogStuck(timeout_sec)
    timeout_sec = timeout_sec or 15
    local now = os and os.time and os.time() or 0
    return (now - last_activity_time) >= timeout_sec
end

function Log(msg)
    LogToConsole("`6[Bothax-GUI] `0" .. tostring(msg))
end

-- =======================================================================
-- SISTEM LISENSI JARAK JAUH (REMOTE WHITELIST UID & GLOBAL KILL-SWITCH)
-- =======================================================================
local LICENSE_SERVER_URL = "https://raw.githubusercontent.com/aidris23/PTHT_PNB/main/license.json"
local GITHUB_API_LICENSE_URL = "https://api.github.com/repos/aidris23/PTHT_PNB/contents/license.json"
local IS_LICENSE_VERIFIED = false

-- Fungsi dekoder base64 ringan bawaan untuk respon GitHub API
local function decode_b64(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('..', function(cc)
        local c1, c2 = cc:sub(1,1), cc:sub(2,2)
        local v1, v2 = b:find(c1)-1, b:find(c2)-1
        return string.char((v1*4) + math.floor(v2/16))
    end))
end

function CheckLicenseAuth()
    if not InWorld() then return false end
    if not MakeRequest then
        IS_LICENSE_VERIFIED = true
        return true
    end

    local pl = nil
    pcall(function() pl = GetLocal and GetLocal() end)
    if not pl then return false end

    local raw_name = pl.name and tostring(pl.name):gsub("`.", ""):match("%S+") or "Player"
    local user_id  = (pl.userid and tostring(pl.userid)) or (pl.netid and tostring(pl.netid)) or ""

    Log("`3[AUTH] Memeriksa lisensi akses UID secara real-time...`0")
    if TextOverlay then pcall(function() TextOverlay("Memeriksa Lisensi UID: " .. tostring(user_id)) end) end

    -- Jalur 1: Menggunakan GitHub REST API (100% INSTAN 0 DETIK, BEBAS DARI CACHE RAW)
    local raw_res = ""
    local ok_api, res_api = pcall(function()
        return MakeRequest(GITHUB_API_LICENSE_URL, "GET", {
            ["User-Agent"] = "Bothax-License/1.0",
            ["Accept"] = "application/vnd.github.v3.raw" -- Meminta isi file mentah langsung secara instan!
        })
    end)

    if ok_api and res_api then
        if type(res_api) == "table" then
            raw_res = tostring(res_api.content or res_api.body or res_api[1] or "")
        else
            raw_res = tostring(res_api)
        end
    end

    -- Jalur 2 (Fallback jika API limit/gagal): Raw GitHub dengan parameter detik
    if raw_res == "" or string.find(raw_res, "API rate limit") then
        local cache_url = LICENSE_SERVER_URL .. "?nocache=" .. tostring(os and os.time and os.time() or 0)
        local ok_raw, res_raw = pcall(function()
            return MakeRequest(cache_url, "GET", {["User-Agent"] = "Bothax/1.0"})
        end)
        if ok_raw and res_raw then
            if type(res_raw) == "table" then
                raw_res = tostring(res_raw.content or res_raw.body or res_raw[1] or "")
            else
                raw_res = tostring(res_raw)
            end
        end
    end

    if raw_res == "" then
        Log("`6[AUTH] Server lisensi tidak merespon/offline. Memberikan akses cadangan.`0")
        IS_LICENSE_VERIFIED = true
        return true
    end

    -- 1. Periksa Saklar Utama (Global Kill-Switch)
    local status = string.match(raw_res, '"status"%s*:%s*"([^"]*)"') or "ACTIVE"
    local maint_msg = string.match(raw_res, '"maintenance_message"%s*:%s*"([^"]*)"') or "Script sedang dinonaktifkan oleh developer."

    if status:upper() ~= "ACTIVE" then
        Log("`4========================================================`0")
        Log("`4[AKSES DITUTUP] " .. maint_msg .. "`0")
        Log("`4========================================================`0")
        if TextOverlay then pcall(function() TextOverlay("AKSES DITUTUP: " .. maint_msg) end) end
        CURRENT_MODE = "IDLE"
        GUI_open = false
        IS_LICENSE_VERIFIED = false
        return false
    end

    -- 2. Periksa Whitelist Khusus User ID (UID Angka)
    -- Jika di dalam daftar whitelist ada tanda bintang "*", maka mode PUBLIK aktif (semua orang bisa pakai!)
    local is_whitelisted = false
    local whitelist_block = raw_res:match('"whitelist"%s*:%s*%[([^%]]*)%]') or raw_res
    if string.find(whitelist_block, '"%*"') or string.find(whitelist_block, "'%*'") then
        is_whitelisted = true
    else
        for uid_entry in string.gmatch(whitelist_block, '"([%d]+)"') do
            if uid_entry == user_id then
                is_whitelisted = true
                break
            end
        end
    end

    if is_whitelisted then
        IS_LICENSE_VERIFIED = true
        Log(string.format("`2[AUTH BERHASIL] UID %s (%s) terverifikasi aktif!`0", user_id, raw_name))
        if TextOverlay then pcall(function() TextOverlay(string.format("Lisensi Aktif (UID: %s)", user_id)) end) end
        return true
    else
        Log("`4========================================================`0")
        Log(string.format("`4[AKSES DITOLAK] Akun '%s' dengan UID %s belum terdaftar!`0", raw_name, user_id))
        Log("`4Salin UID kamu di atas dan berikan ke Admin Piers Store.`0")
        Log("`4========================================================`0")
        if TextOverlay then pcall(function() TextOverlay("AKSES DITOLAK: UID " .. user_id .. " Belum Terdaftar!") end) end
        CURRENT_MODE = "IDLE"
        GUI_open = false
        IS_LICENSE_VERIFIED = false
        return false
    end
end

function InWorld()
    local w = GetWorld()
    return w ~= nil and w.name ~= nil and w.name ~= "" and w.name ~= "EXIT"
end

function EnsureTargetWorld()
    -- Jika bot sedang IDLE / STOP / STANDBY, jangan pernah auto-warp/paksa masuk world
    if CURRENT_MODE == "IDLE" or CURRENT_MODE == "STANDBY" or CURRENT_MODE == "STOP" then
        return true
    end

    if not TARGET_WORLD or TARGET_WORLD == "" then
        local w = GetWorld()
        if w and w.name and w.name ~= "" and w.name ~= "EXIT" then TARGET_WORLD = w.name end
        return true
    end

    local w = GetWorld()
    local cur_name = (w and w.name) and w.name or ""
    if cur_name == "" or cur_name == "EXIT" or cur_name:upper() ~= TARGET_WORLD:upper() then
        Log(string.format("`4[AUTO-WARP] Di luar world '%s', masuk kembali...`0", TARGET_WORLD))
        if RequestJoinWorld then pcall(function() RequestJoinWorld(TARGET_WORLD) end) end
        SendPacket(3, "action|join_request\nname|" .. TARGET_WORLD .. "\ninvitedWorld|0")
        Sleep(4000)
        ALL_SEED_MAGS = {}
        ALL_BLOCK_MAGS = {}
        ptht_seed_remote_verified = false
        pnb_initialized = false
        WHITE_DOOR_X = nil
        WHITE_DOOR_Y = nil
        return false
    end
    return true
end

-- =======================================================================
-- KICK & RESPAWN RECOVERY GUARD (DETEKSI & PEMULIHAN SAAT TERKICK)
-- =======================================================================
local WHITE_DOOR_X = nil
local WHITE_DOOR_Y = nil

function FindWhiteDoor()
    if not InWorld() or not GetTile then return nil, nil end
    local max_w = GetTile(199, 0) and 199 or 99
    -- Optimasi: Pindai area spawn (biasanya X=0..10 dan Y=0..40) terlebih dahulu
    for y = 0, 40 do
        for x = 0, math.min(15, max_w) do
            local t = GetTile(x, y)
            if t and t.fg == 6 then return x, y end
        end
    end
    -- Fallback scan jika pintu ditaruh di tempat lain
    for y = 0, 60 do
        for x = 0, max_w do
            local t = GetTile(x, y)
            if t and t.fg == 6 then return x, y end
        end
    end
    return nil, nil
end

function CheckIfKickedToSpawn(expected_x, expected_y)
    if not InWorld() then return true end
    local pl = GetLocal and GetLocal()
    if not pl or not pl.pos then return false end

    local cx = math.floor(pl.pos.x / 32)
    local cy = math.floor(pl.pos.y / 32)

    if not WHITE_DOOR_X or not WHITE_DOOR_Y then
        local wx, wy = FindWhiteDoor()
        if wx and wy then
            WHITE_DOOR_X = wx
            WHITE_DOOR_Y = wy
        end
    end

    -- Jika kita tahu letak White Door dan bot mendadak berada di radius 2 blok White Door
    -- padahal seharusnya sedang berada jauh di tempat kerja (selisih > 8 blok):
    if WHITE_DOOR_X and WHITE_DOOR_Y and expected_x and expected_y then
        local dist_to_target = math.abs(cx - expected_x) + math.abs(cy - expected_y)
        local dist_to_door   = math.abs(cx - WHITE_DOOR_X) + math.abs(cy - WHITE_DOOR_Y)

        if dist_to_door <= 2 and dist_to_target > 8 then
            Log(string.format("`4[KICK DETECTED] Karakter terlempar ke White Door (%d, %d)! Target kerja: (%d, %d)`0", cx, cy, expected_x, expected_y))
            if TextOverlay then pcall(function() TextOverlay("KICK TERDETEKSI: Cooldown Pemulihan...") end) end
            
            -- Auto-Adaptive Speed: Turunkan kecepatan secara bertahap jika terkena kick
            if AutoAdaptSpeed then
                local old_dp = DelayPlant
                DelayPlant = math.min(120, DelayPlant + 15)
                DelayFindPath = math.min(100, DelayFindPath + 10)
                DelayStepPath = math.min(110, DelayStepPath + 10)
                Log(string.format("`6[AUTO-SPEED] Kecepatan diturunkan otomatis: DelayPlant %dms -> %dms agar aman dari kick!`0", old_dp, DelayPlant))
            end

            -- Rem total selama 3.5 detik agar anticheat server reda
            Sleep(3500)
            
            -- Pulihkan Modfly
            if ChangeValue then
                pcall(function()
                    ChangeValue("[C] Modfly", true)
                    ChangeValue("[C] Modfly v2", true)
                end)
            end
            return true
        end
    end
    return false
end

function GetInvAmount(item_id)
    if not GetInventory then return 0 end
    local inv = nil
    pcall(function() inv = GetInventory() end)
    if not inv or type(inv) ~= "table" then return 0 end
    for _, item in pairs(inv) do
        if item and item.id == item_id then return item.amount or 0 end
    end
    return 0
end

function HasRemote()
    return GetInvAmount(REMOTE_ID) > 0
end

-- =======================================================================
-- SISTEM SIMPAN & MUAT KONFIGURASI (SAVE / LOAD PROFILE CROSS-PLATFORM)
-- =======================================================================
local function GetConfigSearchPaths(filename)
    filename = filename or CONFIG_FILE_NAME
    if not filename:find("%.json$") then filename = filename .. ".json" end

    local paths = {}
    -- 1. Path di Android / Termux / Growtopia Bothax
    table.insert(paths, "/storage/emulated/0/Android/media/com.rtsoft.growtopia/scripts/" .. filename)
    table.insert(paths, "/sdcard/Android/media/com.rtsoft.growtopia/scripts/" .. filename)
    table.insert(paths, "storage/emulated/0/Android/media/com.rtsoft.growtopia/scripts/" .. filename)

    -- 2. Path di Windows PC (Local AppData Bothax / Growtopia)
    local ok_win, win_app = pcall(function() return os and os.getenv and os.getenv("LOCALAPPDATA") end)
    if ok_win and win_app and win_app ~= "" then
        table.insert(paths, win_app .. "\\Growtopia\\scripts\\" .. filename)
    end

    -- 3. Path relatif saat ini & subfolder scripts
    table.insert(paths, filename)
    table.insert(paths, "scripts/" .. filename)
    table.insert(paths, "./" .. filename)

    return paths
end

function SaveConfigToFile(filename)
    filename = filename or CONFIG_FILE_NAME
    if not filename:find("%.json$") then filename = filename .. ".json" end

    local cfg_str = string.format([[
{
  "TARGET_WORLD": "%s",
  "PTHT_START_X": %d,
  "PTHT_END_X": %d,
  "PTHT_START_Y": %d,
  "PTHT_END_Y": %d,
  "PTHT_MAG_BG": %d,
  "PNB_MAG_BG": %d,
  "TELEPHONE_NUMBER": "%s",
  "SEED_ITEM_ID": %d,
  "BLOCK_ITEM_ID": %d,
  "DelayPlant": %d,
  "DelayHarvest": %d,
  "DelayFindPath": %d,
  "DelayStepPath": %d,
  "PNB_LOCK_X": %d,
  "PNB_LOCK_Y": %d,
  "TEL_X": %d,
  "TEL_Y": %d,
  "AutoBuyDL_Checked": %s,
  "SprayUWS_Checked": %s,
  "PlantReverse_Checked": %s,
  "AutoAdaptSpeed": %s,
  "DISCORD_WEBHOOK_URL": "%s"
}
]],
        tostring(TARGET_WORLD or ""),
        tonumber(PTHT_START_X or 190),
        tonumber(PTHT_END_X or 0),
        tonumber(PTHT_START_Y or 188),
        tonumber(PTHT_END_Y or 0),
        tonumber(PTHT_MAG_BG or 11858),
        tonumber(PNB_MAG_BG or 12840),
        tostring(TELEPHONE_NUMBER or "53785"),
        tonumber(SEED_ITEM_ID or 16707),
        tonumber(BLOCK_ITEM_ID or 16706),
        tonumber(DelayPlant or 90),
        tonumber(DelayHarvest or 140),
        tonumber(DelayFindPath or 85),
        tonumber(DelayStepPath or 85),
        tonumber(PNB_LOCK_X or 0),
        tonumber(PNB_LOCK_Y or 0),
        tonumber(TEL_X or 0),
        tonumber(TEL_Y or 0),
        tostring(AutoBuyDL_Checked and true or false),
        tostring(SprayUWS_Checked and true or false),
        tostring(PlantReverse_Checked and true or false),
        tostring(AutoAdaptSpeed and true or false),
        tostring(DISCORD_WEBHOOK_URL or "")
    )

    local target_paths = GetConfigSearchPaths(filename)
    local last_err = nil

    for _, path in ipairs(target_paths) do
        local ok, f = pcall(function() return io.open(path, "w+") end)
        if ok and f then
            local write_ok, write_err = pcall(function()
                f:write(cfg_str)
                f:close()
            end)
            if write_ok then
                Log("`2[CONFIG] Berhasil menyimpan konfigurasi ke: " .. tostring(path) .. "!`0")
                if TextOverlay then pcall(function() TextOverlay("Config Tersimpan: " .. filename) end) end
                return true
            else
                last_err = tostring(write_err)
            end
        else
            last_err = tostring(f)
        end
    end

    Log("`4[CONFIG] Gagal menyimpan file: " .. tostring(filename) .. " (" .. tostring(last_err) .. ")!`0")
    if TextOverlay then pcall(function() TextOverlay("Gagal Simpan Config: " .. tostring(filename)) end) end
    return false
end

function LoadConfigFromFile(filename)
    filename = filename or CONFIG_FILE_NAME
    if not filename:find("%.json$") then filename = filename .. ".json" end

    local target_paths = GetConfigSearchPaths(filename)
    local content = nil
    local loaded_from = nil

    for _, path in ipairs(target_paths) do
        local ok, f = pcall(function() return io.open(path, "r") end)
        if ok and f then
            local read_ok, data = pcall(function()
                local c = f:read("*a")
                f:close()
                return c
            end)
            if read_ok and data and data ~= "" then
                content = data
                loaded_from = path
                break
            end
        end
    end

    if not content then
        Log("`6[CONFIG] File " .. tostring(filename) .. " belum ada di folder scripts, menggunakan konfigurasi saat ini.`0")
        return false
    end

    local function get_str(k) return content:match('"' .. k .. '"%s*:%s*"([^"]*)"') end
    local function get_num(k) return tonumber(content:match('"' .. k .. '"%s*:%s*([%-%d%.]+)')) end
    local function get_bool(k)
        local val = content:match('"' .. k .. '"%s*:%s*([%a]+)')
        return val == "true"
    end

    if get_str("TARGET_WORLD") then TARGET_WORLD = get_str("TARGET_WORLD") end
    if get_num("PTHT_START_X") then PTHT_START_X = get_num("PTHT_START_X") end
    if get_num("PTHT_END_X") then PTHT_END_X = get_num("PTHT_END_X") end
    if get_num("PTHT_START_Y") then PTHT_START_Y = get_num("PTHT_START_Y") end
    if get_num("PTHT_END_Y") then PTHT_END_Y = get_num("PTHT_END_Y") end
    if get_num("PTHT_MAG_BG") then PTHT_MAG_BG = get_num("PTHT_MAG_BG") end
    if get_num("PNB_MAG_BG") then PNB_MAG_BG = get_num("PNB_MAG_BG") end
    if get_str("TELEPHONE_NUMBER") then TELEPHONE_NUMBER = get_str("TELEPHONE_NUMBER") end
    if get_num("SEED_ITEM_ID") then SEED_ITEM_ID = get_num("SEED_ITEM_ID") end
    if get_num("BLOCK_ITEM_ID") then BLOCK_ITEM_ID = get_num("BLOCK_ITEM_ID") end
    if get_num("DelayPlant") then DelayPlant = get_num("DelayPlant") end
    if get_num("DelayHarvest") then DelayHarvest = get_num("DelayHarvest") end
    if get_num("DelayFindPath") then DelayFindPath = get_num("DelayFindPath") end
    if get_num("DelayStepPath") then DelayStepPath = get_num("DelayStepPath") end
    if get_num("PNB_LOCK_X") then PNB_LOCK_X = get_num("PNB_LOCK_X") end
    if get_num("PNB_LOCK_Y") then PNB_LOCK_Y = get_num("PNB_LOCK_Y") end
    if get_num("TEL_X") then TEL_X = get_num("TEL_X") end
    if get_num("TEL_Y") then TEL_Y = get_num("TEL_Y") end
    if content:find('"AutoBuyDL_Checked"') then AutoBuyDL_Checked = get_bool("AutoBuyDL_Checked") end
    if content:find('"SprayUWS_Checked"') then SprayUWS_Checked = get_bool("SprayUWS_Checked") end
    if content:find('"PlantReverse_Checked"') then PlantReverse_Checked = get_bool("PlantReverse_Checked") end
    if content:find('"AutoAdaptSpeed"') then AutoAdaptSpeed = get_bool("AutoAdaptSpeed") end
    if get_str("DISCORD_WEBHOOK_URL") then DISCORD_WEBHOOK_URL = get_str("DISCORD_WEBHOOK_URL") end

    Log("`2[CONFIG] Berhasil memuat konfigurasi dari: " .. tostring(loaded_from) .. "!`0")
    if TextOverlay then pcall(function() TextOverlay("Config Dimuat: " .. filename) end) end
    return true
end

-- =======================================================================
-- INTEGRASI DISCORD WEBHOOK DENGAN BRANDING PIERS STORE
-- =======================================================================
local PIERS_BRAND_LOGO = "https://media.discordapp.net/attachments/1275660383322898454/1561424299636560093/Luxury_Gaming_Emblem_1.png?ex=6ad64d32&is=6ad4fbb2&hm=49d214fe84e111cd1f5b6bdb013024fd6c0b65a6e6742612fbd495c45e77f8ed&=&format=webp&quality=lossless&width=1024&height=1024"

function SendPiersWebhook(event_title, description, color_code, cycle_duration_sec)
    if not DISCORD_WEBHOOK_URL or DISCORD_WEBHOOK_URL == "" then return end
    if not MakeRequest then return end

    local pl = nil
    pcall(function() pl = GetLocal() end)
    local pname = pl and pl.name and tostring(pl.name):gsub("`.", ""):match("%S+") or "Piers"

    local w = nil
    pcall(function() w = GetWorld() end)
    local wname = (w and w.name and w.name ~= "") and w.name or (TARGET_WORLD ~= "" and TARGET_WORLD or "World")

    local gems = 0
    if GetPlayerInfo then pcall(function() gems = GetPlayerInfo().gems or 0 end) end
    if gems == 0 and getGems then pcall(function() gems = getGems() or 0 end) end

    local dl = GetInvAmount(1796)
    local bgl = GetInvAmount(7188)

    local dur_str = "-"
    if cycle_duration_sec and cycle_duration_sec > 0 then
        local dm = math.floor(cycle_duration_sec / 60)
        local ds = cycle_duration_sec % 60
        dur_str = string.format("%dm %ds", dm, ds)
    end

    local payload = string.format([[
{
  "username": "PIERS STORE",
  "avatar_url": "%s",
  "embeds": [
    {
      "title": "%s",
      "description": "%s",
      "color": %d,
      "fields": [
        {"name": "👤 Player / Avatar", "value": "`%s`", "inline": true},
        {"name": "🌍 World", "value": "`%s`", "inline": true},
        {"name": "🔄 Siklus PTHT", "value": "`#%d`", "inline": true},
        {"name": "💎 Saldo Gems", "value": "`%s Gems`", "inline": true},
        {"name": "💰 Saldo DL / BGL", "value": "`%d DL` | `%d BGL`", "inline": true},
        {"name": "⏱️ Durasi Panen (1x)", "value": "`%s`", "inline": true}
      ],
      "footer": {
        "text": "Piers Store | Growtopia Automation Script",
        "icon_url": "%s"
      }
    }
  ]
}
]],
        PIERS_BRAND_LOGO,
        event_title or "🌾 PTHT Cycle Completed",
        description or "Putaran penanaman dan panen telah selesai dieksekusi dengan sempurna.",
        color_code or 5763719,
        pname,
        wname,
        cycle_counter or 0,
        tostring(gems):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,",""),
        dl,
        bgl,
        dur_str,
        PIERS_BRAND_LOGO
    )

    pcall(function()
        MakeRequest(DISCORD_WEBHOOK_URL, "POST", {["Content-Type"] = "application/json"}, payload)
    end)
end

local GUI_open = true

-- =======================================================================
-- NATIVE BOTHAX IMGUI WINDOW (OVERLAY ASLI BOTHAX PC)
-- =======================================================================
function RenderBothaxImGui()
    if not ImGui then return end
    if not GUI_open then return end
    if not IS_LICENSE_VERIFIED then return end

    -- ImGui Window dengan flag default & tombol minimize/close bawaan
    local ok = ImGui.Begin("PIERS BOT | PNB BFG v1.0")
    if not ok then
        ImGui.End()
        return
    end

    ImGui.Text("=== MONITOR STATUS UTAMA ===")
    ImGui.Text("Status Mode  : " .. tostring(CURRENT_MODE))
    
    local pos_label = (PNB_LOCK_X ~= 0 and PNB_LOCK_Y ~= 0) and string.format("(%d, %d)", PNB_LOCK_X, PNB_LOCK_Y) or "Belum Diset (Otomatis Titik Berdiri)"
    ImGui.Text("Posisi PNB   : " .. pos_label)
    
    local ghost_label = (IS_GHOST_ON == true) and "AKTIF (Ghost Mode ON)" or "MATI (Normal Body)"
    ImGui.Text("Mode Ghost   : " .. ghost_label)
    ImGui.Separator()

    -- 1. Tombol Pemilihan Mode Operasi (Utama)
    ImGui.Text("=== KONTROL MODE KERJA ===")
    if ImGui.Button("  Start Mode PNB BFG  ") then
        if CURRENT_MODE == "PTHT" then CheatTurnOff() end
        CURRENT_MODE = "PNB"
        pnb_initialized = false
        ptht_seed_remote_verified = false
        current_mag_idx = 1 -- Selalu mulai dari Magplant paling kiri
        ALL_SEED_MAGS = {}
        ALL_BLOCK_MAGS = {}
        -- Pastikan Ghost Mode langsung aktif saat tombol dipencet
        if IS_GHOST_ON ~= true then
            SendPacket(2, "action|input\n|text|/ghost")
            last_ghost_toggle_time = os and os.time and os.time() or 0
            IS_GHOST_ON = true
            Log("`2[ImGui] Ghost Mode diaktifkan seketika saat Start PNB!`0")
        end
        Log("`1[ImGui] Mode PNB BFG Dimulai via Bothax GUI!`0")
        if TextOverlay then pcall(function() TextOverlay("Mode: PNB Started (Ghost ON)") end) end
    end

    ImGui.SameLine()

    if ImGui.Button("  STOP / STANDBY  ") then
        CURRENT_MODE = "IDLE"
        pnb_initialized = false
        ptht_seed_remote_verified = false
        CheatTurnOff()
        Log("`4[ImGui] Bot Berhasil Dihentikan (STANDBY).`0")
        if TextOverlay then pcall(function() TextOverlay("Mode: STOP / STANDBY") end) end
    end

    ImGui.Separator()

    -- 2. Tombol Set Posisi PNB & Titik Mulai PTHT
    ImGui.Text("=== PENGATURAN LOKASI POSISI ===")
    local pl = nil
    pcall(function() pl = GetLocal and GetLocal() end)
    local cur_x = 0
    local cur_y = 0
    if pl then
        cur_x = pl.posX and math.floor(pl.posX / 32) or (pl.pos and math.floor(pl.pos.x / 32)) or 0
        cur_y = pl.posY and math.floor(pl.posY / 32) or (pl.pos and math.floor(pl.pos.y / 32)) or 0
    end

    local ch_px, new_px = ImGui.InputInt("Posisi PNB X", PNB_LOCK_X or 0)
    if ch_px then PNB_LOCK_X = new_px; pnb_initialized = false end

    local ch_py, new_py = ImGui.InputInt("Posisi PNB Y", PNB_LOCK_Y or 0)
    if ch_py then PNB_LOCK_Y = new_py; pnb_initialized = false end

    if ImGui.Button(string.format("  Kunci Titik PNB di Posisi Berdiri Saat Ini (%d, %d)  ", cur_x, cur_y)) then
        if cur_x ~= 0 or cur_y ~= 0 then
            PNB_LOCK_X = cur_x
            PNB_LOCK_Y = cur_y
            pnb_initialized = false
            Log(string.format("`2[ImGui] Posisi PNB BERHASIL DIKUNCI di (%d, %d)!`0", PNB_LOCK_X, PNB_LOCK_Y))
            if TextOverlay then pcall(function() TextOverlay(string.format("Posisi PNB Terkunci: (%d, %d)", PNB_LOCK_X, PNB_LOCK_Y)) end) end
        else
            Log("`4[ImGui] Gagal membaca posisi karakter! Pastikan sudah masuk world.`0")
        end
    end

    ImGui.Separator()

    -- 3. Pengaturan General (Item ID & Background Magplant)
    ImGui.Text("=== KONFIGURASI ITEM & MAGPLANT ===")
    local ch_world, new_world = ImGui.InputText("Target World", TARGET_WORLD or "", 32)
    if ch_world then TARGET_WORLD = new_world end

    ImGui.SameLine()

    if ImGui.Button("  Go / Join World  ") then
        if TARGET_WORLD and TARGET_WORLD ~= "" then
            Log("`2[WARP] Menghubungkan manual ke world: " .. TARGET_WORLD .. "...`0")
            if RequestJoinWorld then pcall(function() RequestJoinWorld(TARGET_WORLD) end) end
            SendPacket(3, "action|join_request\nname|" .. TARGET_WORLD .. "\ninvitedWorld|0")
        else
            Log("`4[WARP] Harap isi nama Target World terlebih dahulu!`0")
        end
    end

    local ch_bg_block, new_bg_block = ImGui.InputInt("BG Magplant BLOCK (PNB)", PNB_MAG_BG or 12840)
    if ch_bg_block then
        PNB_MAG_BG = new_bg_block
        ALL_BLOCK_MAGS = {}
    end

    local ch_block_id, new_block_id = ImGui.InputInt("Block Item ID (PNB)", BLOCK_ITEM_ID or 16706)
    if ch_block_id then BLOCK_ITEM_ID = new_block_id end

    local ch_tel, new_tel = ImGui.InputText("Nomor Telepon Converter", TELEPHONE_NUMBER or "53785", 16)
    if ch_tel then TELEPHONE_NUMBER = new_tel end

    ImGui.Separator()

    -- 4. Fitur Otomatis & Kecepatan Adaptif
    ImGui.Text("=== FITUR OTOMATIS & SPEED ===")
    local ch_adapt, new_adapt = ImGui.Checkbox("Auto-Adaptive Speed (Turunkan Kecepatan Jika Ter-kick)", AutoAdaptSpeed == nil and true or AutoAdaptSpeed)
    if ch_adapt then AutoAdaptSpeed = new_adapt end

    local changed_dl, new_dl = ImGui.Checkbox("Auto-Buy Diamond Lock via Telepon", AutoBuyDL_Checked == nil and false or AutoBuyDL_Checked)
    if changed_dl then
        AutoBuyDL_Checked = new_dl
        local st = AutoBuyDL_Checked and "DIAKTIFKAN" or "DINONAKTIFKAN"
        Log("`6[ImGui] Auto-Buy DL di Telepon " .. st .. "!`0")
        if TextOverlay then pcall(function() TextOverlay("Auto-Buy DL: " .. st) end) end
        if AutoBuyDL_Checked then
            need_buy_dl_now = true
        end
    end

    ImGui.SameLine()

    if ImGui.Button("  Beli DL Sekarang (Telepon)  ") then
        Log("`2[ImGui] Tombol Beli DL Ditekan! Langsung memproses penukaran DL via telepon...`0")
        need_buy_dl_now = true
    end

    ImGui.SameLine()

    local changed_gh, new_gh = ImGui.Checkbox("Ghost Mode (/ghost)", (IS_GHOST_ON == true))
    if changed_gh then
        local now = os and os.time and os.time() or 0
        if (now - last_ghost_toggle_time) >= 3.0 then
            last_ghost_toggle_time = now
            IS_GHOST_ON = new_gh
            SendPacket(2, "action|input\n|text|/ghost")
            Log("`3[ImGui] Toggle Ghost Mode diklik: Mengirim /ghost ke server...`0")
        else
            local sisa = math.ceil(3.0 - (now - last_ghost_toggle_time))
            Log(string.format("`4[ANTI-SPAM] Harap tunggu cooldown %d detik sebelum toggle /ghost lagi!`0", sisa))
            if TextOverlay then pcall(function() TextOverlay(string.format("Cooldown Ghost %ds!", sisa)) end) end
        end
    end

    ImGui.Separator()

    -- 5. Webhook Discord & Profil Simpan / Muat
    ImGui.Text("=== DISCORD WEBHOOK & PROFIL CONFIG ===")
    local ch_webhook, new_webhook = ImGui.InputText("Discord Webhook URL", DISCORD_WEBHOOK_URL or "", 128)
    if ch_webhook then DISCORD_WEBHOOK_URL = new_webhook end

    ImGui.SameLine()
    if ImGui.Button("  Tes Webhook  ") then
        if DISCORD_WEBHOOK_URL and DISCORD_WEBHOOK_URL ~= "" then
            SendPiersWebhook("🔔 Tes Koneksi Webhook", "Webhook berhasil terhubung ke Piers Universal Controller!", 5763719)
            Log("`2[WEBHOOK] Pesan tes telah dikirim ke Discord!`0")
        else
            Log("`4[WEBHOOK] Harap isi Discord Webhook URL terlebih dahulu!`0")
        end
    end

    local ch_cfgname, new_cfgname = ImGui.InputText("Nama File Profil (.json)", CONFIG_FILE_NAME or "piers_config_default.json", 32)
    if ch_cfgname then CONFIG_FILE_NAME = new_cfgname end

    if ImGui.Button("  Simpan Profil  ") then
        SaveConfigToFile(CONFIG_FILE_NAME)
    end

    ImGui.SameLine()

    if ImGui.Button("  Muat Profil  ") then
        LoadConfigFromFile(CONFIG_FILE_NAME)
    end

    -- Tombol Cepat Pilihan Profil Populer (Tinggal 1x Klik)
    ImGui.Text("Pilihan Profil Cepat:")
    if ImGui.Button("Akun 1") then
        CONFIG_FILE_NAME = "akun_1.json"
        LoadConfigFromFile(CONFIG_FILE_NAME)
    end
    ImGui.SameLine()
    if ImGui.Button("Akun 2") then
        CONFIG_FILE_NAME = "akun_2.json"
        LoadConfigFromFile(CONFIG_FILE_NAME)
    end
    ImGui.SameLine()
    if ImGui.Button("Akun 3") then
        CONFIG_FILE_NAME = "akun_3.json"
        LoadConfigFromFile(CONFIG_FILE_NAME)
    end
    ImGui.SameLine()
    if ImGui.Button("Default") then
        CONFIG_FILE_NAME = "piers_pnb_default.json"
        LoadConfigFromFile(CONFIG_FILE_NAME)
    end

    ImGui.Separator()
    ImGui.Text("Tips: Klik tanda [-] di pojok kanan atas jendela untuk melipat.")
    ImGui.End()
end

-- Daftarkan Hook Render ImGui Resmi Bothax secara kompatibel
if addHook then
    addHook(function()
        pcall(RenderBothaxImGui)
    end, "ondrawimgui")
else
    AddHook("OnDraw", "piers_ondraw_gui", function() pcall(RenderBothaxImGui) end)
end

-- =======================================================================
-- NAVIGASI PERGERAKAN BOTHAX (TELEPATH AMAN ANTI-KICK)
-- =======================================================================
function GoPath(t, s, v, x, y)
    if not InWorld() then return end
    SendPacketRaw(false, {type = t or 0, state = s or 0, value = v or 0, px = x, py = y, x = x * 32, y = y * 32})
    SendVariantList({[0] = "OnSetPos", [1] = {x = x * 32, y = y * 32}}, GetLocal().netid)
end

function gOgOPath(x, y)
    GoPath(0, 0, 0, x, y)
end

local function sign(v) return (v > 0 and 1) or (v < 0 and -1) or 0 end

function TelePath(tx, ty)
    if not InWorld() then return end
    local pl = GetLocal()
    if not pl or not pl.pos then return end

    local cx = math.floor(pl.pos.x / 32)
    local cy = math.floor(pl.pos.y / 32)
    if cx == tx and cy == ty then return end

    -- Pastikan Native Modfly selalu aktif saat bergerak
    if ChangeValue then
        pcall(function()
            ChangeValue("[C] Modfly", true)
            ChangeValue("[C] Modfly v2", true)
        end)
    end

    local dist = math.abs(cx - tx) + math.abs(cy - ty)
    if dist <= 2 then
        GoPath(nil, nil, nil, tx, ty)
        Sleep(85)
        return
    end

    local steps = 0
    local max_steps = 300
    local step_size = 2

    while (cx ~= tx or cy ~= ty) and InWorld() and steps < max_steps do
        steps = steps + 1
        local dx = tx - cx
        local dy = ty - cy
        local nx, ny = cx, cy

        if math.abs(dx) >= math.abs(dy) then
            local step = math.min(step_size, math.abs(dx))
            nx = cx + sign(dx) * step
        else
            local step = math.min(step_size, math.abs(dy))
            ny = cy + sign(dy) * step
        end

        gOgOPath(nx, ny)
        Sleep(DelayFindPath)

        local try = 0
        while try < 3 and InWorld() do
            Sleep(DelayStepPath)
            local p2 = GetLocal()
            if p2 and p2.pos and math.floor(p2.pos.x / 32) == nx and math.floor(p2.pos.y / 32) == ny then break end
            try = try + 1
        end

        local p_cur = GetLocal()
        if p_cur and p_cur.pos then
            local actual_x = math.floor(p_cur.pos.x / 32)
            local actual_y = math.floor(p_cur.pos.y / 32)
            local displacement = math.abs(actual_x - nx) + math.abs(actual_y - ny)
            if displacement > 4 then
                Log(string.format("`4[KICK TERDETEKSI] Karakter terlempar ke (%d, %d)! Berhenti sejenak untuk pemulihan...`0", actual_x, actual_y))
                CheatTurnOff()
                if TextOverlay then pcall(function() TextOverlay("KICK TERDETEKSI: Cooldown Pemulihan 3s...") end) end
                Sleep(3000)
                if ChangeValue then
                    pcall(function()
                        ChangeValue("[C] Modfly", true)
                        ChangeValue("[C] Modfly v2", true)
                    end)
                end
                local p_after = GetLocal()
                if p_after and p_after.pos then
                    actual_x = math.floor(p_after.pos.x / 32)
                    actual_y = math.floor(p_after.pos.y / 32)
                end
            end
            cx = actual_x
            cy = actual_y
        else
            cx, cy = nx, ny
        end
    end
    Sleep(40)
end

-- TelePath Khusus PNB: Berjalan santai 1-tile agar tidak terkena kick anticheat
function TelePathPNB(tx, ty)
    if not InWorld() then return end
    local pl = GetLocal()
    if not pl or not pl.pos then return end

    local cx = math.floor(pl.pos.x / 32)
    local cy = math.floor(pl.pos.y / 32)
    if cx == tx and cy == ty then return end

    -- Matikan pukulan autofarm/BFG saat berjalan di PNB agar tidak memukul sembarangan
    if ChangeValue then
        pcall(function()
            ChangeValue("[C] Autofarm", false)
            ChangeValue("[C] BFG", false)
            ChangeValue("[C] Fast Punch", false)
            ChangeValue("[C] Modfly", true)
            ChangeValue("[C] Modfly v2", true)
        end)
    end

    local dist = math.abs(cx - tx) + math.abs(cy - ty)
    if dist <= 2 then
        GoPath(nil, nil, nil, tx, ty)
        Sleep(120)
        return
    end

    local steps = 0
    local max_steps = 300

    while (cx ~= tx or cy ~= ty) and InWorld() and steps < max_steps do
        steps = steps + 1
        local dx = tx - cx
        local dy = ty - cy
        local nx, ny = cx, cy

        -- Jalan responsif lincah: 2 tile jika jarak jauh (misal saat DC/respawn), 1 tile saat mendekati target (<4 tile)
        local remaining_dist = math.abs(dx) + math.abs(dy)
        local step_size = (remaining_dist > 4) and 2 or 1

        if math.abs(dx) >= math.abs(dy) then
            local step = math.min(step_size, math.abs(dx))
            nx = cx + sign(dx) * step
        else
            local step = math.min(step_size, math.abs(dy))
            ny = cy + sign(dy) * step
        end

        gOgOPath(nx, ny)
        Sleep(75)

        local try = 0
        while try < 3 and InWorld() do
            Sleep(65)
            local p2 = GetLocal()
            if p2 and p2.pos and math.floor(p2.pos.x / 32) == nx and math.floor(p2.pos.y / 32) == ny then break end
            try = try + 1
        end

        local p_cur = GetLocal()
        if p_cur and p_cur.pos then
            local actual_x = math.floor(p_cur.pos.x / 32)
            local actual_y = math.floor(p_cur.pos.y / 32)
            local displacement = math.abs(actual_x - nx) + math.abs(actual_y - ny)
            if displacement > 4 then
                Log(string.format("`4[KICK TERDETEKSI] Karakter terlempar ke (%d, %d)! Berhenti sejenak untuk pemulihan...`0", actual_x, actual_y))
                CheatTurnOff()
                if TextOverlay then pcall(function() TextOverlay("KICK TERDETEKSI: Cooldown Pemulihan 3s...") end) end
                Sleep(3000)
                if ChangeValue then
                    pcall(function()
                        ChangeValue("[C] Modfly", true)
                        ChangeValue("[C] Modfly v2", true)
                    end)
                end
                local p_after = GetLocal()
                if p_after and p_after.pos then
                    actual_x = math.floor(p_after.pos.x / 32)
                    actual_y = math.floor(p_after.pos.y / 32)
                end
            end
            cx = actual_x
            cy = actual_y
        else
            cx, cy = nx, ny
        end
    end
    Sleep(80)
end

-- =======================================================================
-- EKSTRAKSI STOK & REMOTE MAGPLANT
-- =======================================================================
local function ExtractMagStock(dialog_text)
    if not dialog_text or dialog_text == "" then return 0 end
    local count = dialog_text:match("[Hh]olds.-(%d+).-of") or dialog_text:match("[Hh]olds.-(%d+)") or dialog_text:match("(%d+)%s+of")
    if count then return tonumber(count) or 0 end
    for num in dialog_text:gmatch("(%d+)") do
        local n = tonumber(num)
        if n and n >= 50 and n <= 5000 and n ~= 5638 and n ~= 5640 and n ~= 16707 and n ~= 189 then return n end
    end
    return 0
end

function GetMagTilesByBg(bg_id)
    local list = {}
    local max_width = GetTile(199, 0) and 199 or 99
    for y = 0, 199 do
        for x = 0, max_width do
            local t = GetTile(x, y)
            if t and t.fg == MAGPLANT_ID and (not bg_id or bg_id == 0 or t.bg == bg_id) then
                table.insert(list, {x = x, y = y})
            end
        end
    end
    -- Wajib urutkan dari Magplant yang paling kiri di world (koordinat X terkecil)
    table.sort(list, function(a, b)
        if a.x ~= b.x then
            return a.x < b.x
        else
            return a.y < b.y
        end
    end)
    return list
end

function FastRespawn()
    if not InWorld() then return end
    Log("`3[RESPAWN] Fast Respawn ke pintu / Magplant...`0")
    SendPacket(2, "action|respawn\n")
    Sleep(2200)
end

function TakeRemoteNextSeedMag()
    if #ALL_SEED_MAGS == 0 then
        ALL_SEED_MAGS = GetMagTilesByBg(PTHT_MAG_BG)
        if #ALL_SEED_MAGS == 0 then ALL_SEED_MAGS = GetMagTilesByBg(0) end
    end
    if #ALL_SEED_MAGS == 0 then
        Log("`4[PTHT] Tidak ditemukan Magplant Seed di world!`0")
        return false
    end

    local total = #ALL_SEED_MAGS
    local checked = 0
    while checked < total do
        if not InWorld() then return false end

        if current_mag_idx > total then current_mag_idx = 1 end
        local mag = ALL_SEED_MAGS[current_mag_idx]

        -- Berdiri 1 tile di atas Magplant agar tidak berimpitan saat wrench
        local stand_y = (mag.y > 0) and (mag.y - 1) or mag.y
        TelePath(mag.x, stand_y)
        Sleep(200)

        captured_dialog = ""
        SendPacketRaw(false, {type = 3, state = 32, value = 32, px = mag.x, py = mag.y, x = mag.x * 32, y = mag.y * 32})
        local wait_count = 0
        while wait_count < 6 and captured_dialog == "" and InWorld() do
            Sleep(100)
            wait_count = wait_count + 1
        end

        local diag_lower = string.lower(captured_dialog)
        local is_disabled = string.find(diag_lower, "disabled") or string.find(diag_lower, "the machine is disabled")
        local is_block = string.find(diag_lower, "block") or string.find(captured_dialog, tostring(BLOCK_ITEM_ID)) or string.find(captured_dialog, "16706")
        local is_seed = not is_disabled and not is_block and (string.find(diag_lower, "seed") or string.find(captured_dialog, tostring(SEED_ITEM_ID)) or string.find(captured_dialog, "16707"))
        local stock = ExtractMagStock(captured_dialog)

        if not is_disabled and is_seed and stock >= 100 then
            Log(string.format("`2[TERVERIFIKASI SEED] Mag #%d di (%d,%d) stok: %d! Mengambil Remote...", current_mag_idx, mag.x, mag.y, stock))
            SendPacket(2, string.format("action|dialog_return\ndialog_name|magplant_edit\nx|%d|\ny|%d|\nbuttonClicked|getRemote\n", mag.x, mag.y))
            Sleep(500)
            return true
        else
            Log(string.format("`6[LEWATI MAG] Mag #%d di (%d,%d) KOSONG / stok %d (< 100). Skip ke Mag berikutnya...`0", current_mag_idx, mag.x, mag.y, stock))
            current_mag_idx = current_mag_idx + 1
            checked = checked + 1
            Sleep(100)
        end
    end
    return HasRemote()
end

function TakeRemoteNextBlockMag()
    if #ALL_BLOCK_MAGS == 0 then
        ALL_BLOCK_MAGS = GetMagTilesByBg(PNB_MAG_BG)
        if #ALL_BLOCK_MAGS == 0 then ALL_BLOCK_MAGS = GetMagTilesByBg(0) end
    end
    if #ALL_BLOCK_MAGS == 0 then
        Log("`4[PNB] Tidak ditemukan Magplant Block di world!`0")
        return false
    end

    local total = #ALL_BLOCK_MAGS
    local checked = 0
    while checked < total do
        if current_mag_idx > total then current_mag_idx = 1 end
        local mag = ALL_BLOCK_MAGS[current_mag_idx]

        local stand_y = (mag.y > 0) and (mag.y - 1) or mag.y
        TelePathPNB(mag.x, stand_y)
        Sleep(200)

        captured_dialog = ""
        SendPacketRaw(false, {type = 3, state = 32, value = 32, px = mag.x, py = mag.y, x = mag.x * 32, y = mag.y * 32})
        local wait_count = 0
        while wait_count < 6 and captured_dialog == "" and InWorld() do
            Sleep(100)
            wait_count = wait_count + 1
        end

        local diag_lower = string.lower(captured_dialog)
        local is_disabled = string.find(diag_lower, "disabled") or string.find(diag_lower, "the machine is disabled")
        local is_seed = string.find(diag_lower, "seed") or string.find(captured_dialog, tostring(SEED_ITEM_ID)) or string.find(captured_dialog, "16707")
        local is_block = not is_disabled and not is_seed and (string.find(diag_lower, "block") or string.find(captured_dialog, tostring(BLOCK_ITEM_ID)))
        local stock = ExtractMagStock(captured_dialog)

        if not is_disabled and is_block and stock >= 50 then
            Log(string.format("`2[TERVERIFIKASI BLOCK] Mag #%d di (%d,%d) stok: %d! Mengambil Remote...", current_mag_idx, mag.x, mag.y, stock))
            SendPacket(2, string.format("action|dialog_return\ndialog_name|magplant_edit\nx|%d|\ny|%d|\nbuttonClicked|getRemote\n", mag.x, mag.y))
            Sleep(500)
            return true
        else
            Log(string.format("`6[LEWATI MAG] Mag Block #%d di (%d,%d) KOSONG / stok %d (< 50). Skip ke Mag berikutnya...`0", current_mag_idx, mag.x, mag.y, stock))
            current_mag_idx = current_mag_idx + 1
            checked = checked + 1
            Sleep(100)
        end
    end
    return false
end

-- =======================================================================
-- FITUR AUTO BUY DL VIA TELEPON CONVERTER (53785)
-- =======================================================================
function FindTelephoneTile()
    if TEL_X and TEL_Y and (TEL_X ~= 0 or TEL_Y ~= 0) then
        return TEL_X, TEL_Y
    end

    local pl = GetLocal and GetLocal()
    local px = (pl and pl.pos) and math.floor(pl.pos.x / 32) or (PNB_LOCK_X ~= 0 and PNB_LOCK_X or 0)
    local py = (pl and pl.pos) and math.floor(pl.pos.y / 32) or (PNB_LOCK_Y ~= 0 and PNB_LOCK_Y or 0)

    -- 1. Scan di sekitar posisi berdiri bot (radius 3 tile)
    if px ~= 0 and py ~= 0 and GetTile then
        for dy = -3, 3 do
            for dx = -3, 3 do
                local t = GetTile(px + dx, py + dy)
                if t and (t.fg == 3898 or t.fg == 3494 or t.fg == 700 or t.fg == 702 or t.fg == 9436 or t.fg == 9438) then
                    return px + dx, py + dy
                end
            end
        end
    end

    -- 2. Jika tidak ada di radius 3 tile, cari telepon terdekat di seluruh world
    local best_x, best_y = 0, 0
    local min_dist = 999999
    local max_width = (GetTile and GetTile(199, 0)) and 199 or 99
    if GetTile then
        for y = 0, 199 do
            for x = 0, max_width do
                local t = GetTile(x, y)
                if t and (t.fg == 3898 or t.fg == 3494 or t.fg == 700 or t.fg == 702 or t.fg == 9436 or t.fg == 9438) then
                    local dist = math.abs(x - px) + math.abs(y - py)
                    if dist < min_dist then
                        min_dist = dist
                        best_x, best_y = x, y
                    end
                end
            end
        end
    end

    if best_x ~= 0 or best_y ~= 0 then
        return best_x, best_y
    end

    return 47, 192
end

function CheckAndBuyDiamondLock(force)
    if not force and not AutoBuyDL_Checked then return end

    local cur_gems = 0
    if GetPlayerInfo then pcall(function() cur_gems = GetPlayerInfo().gems or 0 end) end
    if cur_gems == 0 and getGems then pcall(function() cur_gems = getGems() or 0 end) end

    -- Kompres WL ke DL otomatis jika punya 100+ WL
    local wl_count = GetInvAmount(242)
    if wl_count >= 100 then
        Log("`2[AUTO DL] World Lock mencapai " .. tostring(wl_count) .. "! Mengompres menjadi Diamond Lock...`0")
        SendPacketRaw(false, {type = 10, value = 242})
        Sleep(200)
    end

    if cur_gems >= 200000 then
        local tx, ty = FindTelephoneTile()
        Log(string.format("`2[BUY DL] Saldo %d Gems! Menukar 1 Diamond Lock via telepon %s di (%d, %d)...`0", cur_gems, TELEPHONE_NUMBER or "53785", tx, ty))
        if TextOverlay then pcall(function() TextOverlay(string.format("Menukar 1 DL di Telepon (%d,%d)", tx, ty)) end) end

        SendPacket(2, string.format("action|dialog_return\ndialog_name|telephone\nnum|%s|\nx|%d|\ny|%d|\nbuttonClicked|dlconvert\n", TELEPHONE_NUMBER or "53785", tx, ty))
        Sleep(250)

        local dl_count = GetInvAmount(1796)
        if dl_count >= 100 then
            Log("`2[AUTO BGL] DL mencapai 100! Mengkonversi menjadi BGL...`0")
            SendPacket(2, string.format("action|dialog_return\ndialog_name|telephone\nnum|%s|\nx|%d|\ny|%d|\nbuttonClicked|bglconvert\n", TELEPHONE_NUMBER or "53785", tx, ty))
            Sleep(300)
        end

        -- Selaraskan saldo gems terkini agar Watchdog tidak mendeteksi freeze palsu
        local new_gems = 0
        if GetPlayerInfo then pcall(function() new_gems = GetPlayerInfo().gems or 0 end) end
        if new_gems == 0 and getGems then pcall(function() new_gems = getGems() or 0 end) end
        last_recorded_gems = new_gems
        MarkActivity()
    else
        if force then
            Log(string.format("`4[BUY DL] Saldo gems belum cukup untuk beli DL! (Saat ini: %d gems, butuh minimal 200,000 gems per DL)`0", cur_gems))
            if TextOverlay then pcall(function() TextOverlay(string.format("Gems Kurang: %d / 200k", cur_gems)) end) end
        end
    end
end

-- =======================================================================
-- ENGINE PTHT (VERTIKAL MURNI: SELESAIKAN 1 KOLOM Y DARI ATAS-BAWAH, LALU GESER KE KOLOM BERIKUTNYA)
-- =======================================================================
function GetPTHTFarmTiles(is_harvest)
    local tiles = {}
    local max_w = GetTile(199, 0) and 199 or 99
    local target_start_x = math.max(0, math.min(PTHT_START_X, max_w))
    local target_end_x   = math.max(0, math.min(PTHT_END_X,   max_w))

    -- Pilihan C: Smart Start berdasarkan posisi berdiri karakter (Y)
    local pl = GetLocal()
    local cur_y = (pl and pl.pos) and math.floor(pl.pos.y / 32) or 188
    local start_from_bottom = (cur_y >= 94)

    -- Bangun daftar kolom X secara konsisten sesuai pengaturan Reverse (190 -> 0 atau 0 -> 190)
    local lanes = {}
    local step = (target_start_x > target_end_x) and -PlantFar or PlantFar
    for x = target_start_x, target_end_x, step do
        table.insert(lanes, x)
    end
    if #lanes == 0 then table.insert(lanes, target_start_x) end

    local col_index = 0
    for _, x in ipairs(lanes) do
        col_index = col_index + 1
        local col_tiles = {}

        local start_check_x = math.min(x, x + PlantFar - 1)
        local end_check_x   = math.max(x, x + PlantFar - 1)

        local min_y = math.min(PTHT_START_Y, PTHT_END_Y)
        local max_y = math.max(PTHT_START_Y, PTHT_END_Y)
        for y = min_y, max_y, 2 do
            local under = GetTile(x, y + 1)
            if under and under.fg ~= 0 then
                local need_plant = false
                for cx = math.max(0, start_check_x), math.min(max_w, end_check_x) do
                    local chk = GetTile(cx, y)
                    if chk and chk.fg == 0 then
                        need_plant = true
                        break
                    end
                end
                if need_plant then
                    table.insert(col_tiles, {x = x, y = y})
                end
            end
        end

        -- ZIGZAG VERTIKAL SMART START (PILIHAN C):
        -- Jika bot di bawah (cur_y >= 94):
        --   Kolom 1: Bawah -> Atas (naik)
        --   Kolom 2: Atas -> Bawah (turun)
        -- Jika bot di atas (cur_y < 94):
        --   Kolom 1: Atas -> Bawah (turun)
        --   Kolom 2: Bawah -> Atas (naik)
        local go_bottom_to_top = (start_from_bottom and (col_index % 2 == 1)) or (not start_from_bottom and (col_index % 2 == 0))
        if go_bottom_to_top then
            table.sort(col_tiles, function(a, b) return a.y > b.y end)
        else
            table.sort(col_tiles, function(a, b) return a.y < b.y end)
        end

        for _, t in ipairs(col_tiles) do
            table.insert(tiles, t)
        end
    end
    return tiles
end

function GetPTHFastHarvestRows()
    local rows = {}
    local max_w = GetTile(199, 0) and 199 or 99
    local target_start_x = math.max(0, math.min(PTHT_START_X, max_w))
    local target_end_x   = math.max(0, math.min(PTHT_END_X, max_w))
    local min_x = math.min(target_start_x, target_end_x)
    local max_x = math.max(target_start_x, target_end_x)

    local min_y = math.min(PTHT_START_Y, PTHT_END_Y)
    local max_y = math.max(PTHT_START_Y, PTHT_END_Y)

    local function is_ripe(y)
        for cx = min_x, max_x, 5 do
            local t = GetTile(cx, y)
            if t and t.fg ~= 0 then
                if (t.fg == SEED_ITEM_ID or t.fg == 16267) then
                    local prog = (t.extra and type(t.extra) == "table" and t.extra.progress) or 1
                    if prog == 1 then return true end
                elseif t.extra and type(t.extra) == "table" and t.extra.progress == 1 then
                    return true
                end
            end
        end
        return false
    end

    -- Akun 1 (Maju, PlantReverse=false): Harvest dari BAWAH ke ATAS (Y max -> Y min)
    -- Akun 2 (Mundur, PlantReverse=true): Harvest dari ATAS ke BAWAH (Y min -> Y max)
    if PlantReverse_Checked then
        -- Akun 2: Atas ke Bawah
        for y = min_y, max_y, 2 do
            if is_ripe(y) then table.insert(rows, y) end
        end
    else
        -- Akun 1: Bawah ke Atas
        for y = max_y, min_y, -2 do
            if is_ripe(y) then table.insert(rows, y) end
        end
    end

    return rows
end

function ExecutePTHTCycle()
    if not EnsureTargetWorld() then Sleep(2000); return end
    Log("`6>>> MEMULAI SIKLUS PTHT (Vertikal Zigzag Super Cepat) <<<`0")

    -- Pengecekan Cheat Expired di Loop PTHT
    if need_buy_cheat then
        local now = os and os.time and os.time() or 0
        if (now - last_buycheat_time) >= 5 then
            last_buycheat_time = now
            Log("`2[AUTO BUY CHEAT] Membeli akses Cheat Menu via paket PTHT...`0")
            SendPacket(2, "action|dialog_return\ndialog_name|buycheat\nbuttonClicked|1\n")
            Sleep(800)
        end
        need_buy_cheat = false
    end

    -- Pastikan Mode Ghost Selalu Aktif untuk Kelancaran Menanam (Wajib nyala sebelum tanam/panen)
    EnsureGhostActiveDirect(true)

    -- Aktifkan Cheat Bawaan & Modfly saat PTHT agar gerak noclip & melayang mulus
    CheatTurnOnPTHT()

    local cycle_start_time = os and os.time and os.time() or 0

    -- Watchdog Penjaga PTHT: Jika karakter terdeteksi diam lebih dari 15 detik saat PTHT
    if CheckWatchdogStuck(15) then
        Log("`4[WATCHDOG PENJAGA] Karakter terdeteksi DIAM saat PTHT! Me-refresh navigasi...`0")
        local pl = GetLocal and GetLocal()
        if pl and pl.pos then
            local cx = math.floor(pl.pos.x / 32)
            local cy = math.floor(pl.pos.y / 32)
            GoPath(nil, nil, nil, cx, cy)
        end
        MarkActivity()
    end

    -- 0. PRIORITAS HARVEST TERLEBIH DAHULU (PASTIKAN POHON MATANG BERSIH 100% SEBELUM TANAM - SELALU DARI KIRI X=0)
    local harvest_tries = 0
    while CURRENT_MODE == "PTHT" and InWorld() and harvest_tries < 3 do
        local pending_harvest = GetPTHFastHarvestRows()
        if #pending_harvest == 0 then break end
        harvest_tries = harvest_tries + 1

        Log(string.format("`5[PRIORITAS HARVEST] Terdeteksi %d baris pohon matang! Memanen dari sisi paling kiri (X=0)...`0", #pending_harvest))
        for _, y in ipairs(pending_harvest) do
            if CURRENT_MODE ~= "PTHT" or not InWorld() then return end
            -- Selalu memukul dan memanen dari pohon yang paling kiri (X=0)
            TelePath(0, y)
            SendPacketRaw(false, {type = 3, value = PUNCH_VALUE, state = 32, x = 0 * 32, y = y * 32, px = 0, py = y})
            MarkActivity()
            Sleep(DelayHarvest)
        end
        Sleep(400)
    end

    -- 1. Pastikan Remote Seed Aktif dari Magplant Seed
    if not ptht_seed_remote_verified then
        Log("`3[PTHT START] Mengambil Remote SEED dari Magplant Seed (BG: " .. tostring(PTHT_MAG_BG) .. ")...`0")
        FastRespawn()
        local ok = TakeRemoteNextSeedMag()
        if not ok then
            Log("`4[PTHT] Gagal mengambil Remote Seed! Memeriksa kembali dalam 2.5 detik...`0")
            Sleep(2500)
            return
        end
        ptht_seed_remote_verified = true
    end

    -- 2. FASE MENANAM VERTIKAL ZIGZAG (CEPAT & AMAN - SMART START PILIHAN C)
    while CURRENT_MODE == "PTHT" and InWorld() do
        local plant_tiles = GetPTHTFarmTiles(false)
        if #plant_tiles == 0 then
            Log("`3[PTHT] Seluruh petak baris sudah tertanam penuh!`0")
            break
        end

        for _, tile in ipairs(plant_tiles) do
            if CURRENT_MODE ~= "PTHT" or not InWorld() then return end

            -- Interrupt Guard: Cek apakah ada pohon matang di world setiap 5 petak
            -- Jika ya, akun kedua tidak perlu lanjut menanam, langsung beralih panen
            if _ % 5 == 0 then
                local ripe_check = GetPTHFastHarvestRows()
                if #ripe_check > 0 then
                    Log(string.format("`5[RIPE INTERRUPT] Terdeteksi %d baris pohon matang saat menanam! Beralih ke fase panen...`0", #ripe_check))
                    if TextOverlay then pcall(function() TextOverlay("Pohon Matang! Beralih ke Harvest...") end) end
                    break
                end
            end

            if need_buy_cheat then
                local now = os and os.time and os.time() or 0
                if (now - last_buycheat_time) >= 5 then
                    last_buycheat_time = now
                    Log("`2[AUTO BUY CHEAT] Membeli akses cheat in-game saat PTHT...`0")
                    SendPacket(2, "action|dialog_return\ndialog_name|buycheat\nbuttonClicked|1\n")
                    Sleep(500)
                end
                need_buy_cheat = false
            end

            if is_mag_empty then
                Log("`4[MAG KOSONG] Magplant habis saat menanam! Mengambil remote seed berikutnya...`0")
                FastRespawn()
                current_mag_idx = current_mag_idx + 1
                local ok = TakeRemoteNextSeedMag(true)
                if not ok then
                    Log("`4[PTHT STOP] Seluruh Magplant Seed KOSONG! Menghentikan siklus PTHT.`0")
                    CURRENT_MODE = "IDLE"
                    is_mag_empty = false
                    return
                end
                is_mag_empty = false
            end

            -- TelePath menuju titik poros MRAY
            TelePath(tile.x, tile.y)
            
            -- Periksa apakah terkena kick/respawn mendadak ke White Door saat jalan ke tile ini
            if CheckIfKickedToSpawn(tile.x, tile.y) then
                Log("`3[RECOVERY] Menghentikan antrean tanam lama, memindai ulang petak baru...`0")
                break -- Langsung hentikan loop antrean ini, loop luar akan rescan ulang petak kosong dari titik terdekat
            end

            -- Tembakkan Remote Seed ke baris MRAY (Gunakan arah hadap yang tepat)
            local plant_state = PlantReverse_Checked and 48 or 32
            SendPacketRaw(false, {type = 3, value = REMOTE_ID, state = plant_state, x = tile.x * 32, y = tile.y * 32, px = tile.x, py = tile.y})
            MarkActivity()
            Sleep(DelayPlant)
        end
    end

    if CURRENT_MODE ~= "PTHT" or not InWorld() then return end

    -- 3. FITUR SEMPROT ULTRA WORLD SPRAY (UWS) JIKA DICENTANG DI GUI
    if SprayUWS_Checked and InWorld() and CURRENT_MODE == "PTHT" then
        Log("`3[UWS] Menyemprotkan Ultra World Spray (UWS)...`0")
        SendPacket(2, "action|dialog_return\ndialog_name|ultraworldspray")
        Sleep(DelayUWS or 3000)
        Log("`2[UWS] Pohon berhasil disemprot UWS dan matang instan!`0")

        -- RESPAWN CEPAT SEBELUM HARVEST AGAR HEMAT LANGKAH
        FastRespawn()

        -- 4. FASE HARVEST SUPER CEPAT (MEMASTIKAN 100% BERSIH TANPA SISA POHON MATANG - SELALU DARI KIRI X=0)
        local post_harvest_tries = 0
        while CURRENT_MODE == "PTHT" and InWorld() and post_harvest_tries < 3 do
            local harvest_rows = GetPTHFastHarvestRows()
            if #harvest_rows == 0 then
                Log("`2[HARVEST] Seluruh pohon matang telah berhasil dipanen bersih tanpa sisa!`0")
                break
            end
            post_harvest_tries = post_harvest_tries + 1

            Log(string.format("`5[HARVEST SUPER CEPAT] Memanen %d baris pohon dari sisi paling kiri (X=0)...`0", #harvest_rows))
            for _, y in ipairs(harvest_rows) do
                if CURRENT_MODE ~= "PTHT" or not InWorld() then return end
                -- Selalu memukul dan memanen dari pohon yang paling kiri (X=0)
                TelePath(0, y)
                SendPacketRaw(false, {type = 3, value = PUNCH_VALUE, state = 32, x = 0 * 32, y = y * 32, px = 0, py = y})
                MarkActivity()
                Sleep(DelayHarvest)
            end
            Sleep(400)
        end
    end

    cycle_counter = cycle_counter + 1
    Log(string.format("`2[SELESAI] Putaran PTHT #%d Berhasil Selesai!`0", cycle_counter))

    local duration_sec = os and os.time and (os.time() - cycle_start_time) or 0

    -- Kirim laporan otomatis ke Discord Webhook jika diisi
    SendPiersWebhook("🌾 Putaran PTHT Selesai", string.format("Putaran PTHT #%d telah berhasil dipanen dan ditanam kembali secara tuntas.", cycle_counter), 5763719, duration_sec)

    -- Garbage collection ringan agar RAM HP tidak menumpuk
    if collectgarbage then collectgarbage("step", 100) end

    Sleep(1500)
end

-- =======================================================================
-- ENGINE PNB BFG STANDALONE
-- =======================================================================
function CheatTurnOff()
    SendPacket(2, [[
action|dialog_return
dialog_name|cheats
check_modfly|0
check_autofarm|0
check_bfg|0
check_autobuff|0
check_autoremote|0
check_gems|1
check_lonely|0
check_ignoreo|0
check_ignoref|0
]])
    if ChangeValue then
        pcall(function()
            -- Modfly TETAP AKTIF agar bisa melayang/noclip saat berpindah
            ChangeValue("[C] Modfly", true)
            ChangeValue("[C] Modfly v2", true)
            ChangeValue("[C] Autofarm", false)
            ChangeValue("[C] BFG", false)
            ChangeValue("[C] Auto Remote", false)
            ChangeValue("[C] Fast Punch", false)
        end)
    end
    Sleep(100)

    -- Pecahkan auto-punch packet server
    local pl = GetLocal and GetLocal()
    if pl and pl.pos then
        local cx = math.floor(pl.pos.x / 32)
        local cy = math.floor(pl.pos.y / 32)
        GoPath(nil, nil, nil, cx, cy)
    end
    Sleep(100)
end

function CheatTurnOnPNB()
    SendPacket(2, [[
action|dialog_return
dialog_name|cheats
check_modfly|0
check_autofarm|1
check_bfg|1
check_autobuff|1
check_autoremote|1
check_gems|1
check_lonely|0
check_ignoreo|0
check_ignoref|0
]])
    -- Modfly murni menggunakan Native Bothax
    if ChangeValue then
        pcall(function()
            ChangeValue("[C] Modfly", true)
            ChangeValue("[C] Modfly v2", true)
            ChangeValue("[C] Autofarm", true)
            ChangeValue("[C] BFG", true)
            ChangeValue("[C] Auto Remote", true)
        end)
    end
    Sleep(300)
end

function CheatTurnOnPTHT()
    SendPacket(2, [[
action|dialog_return
dialog_name|cheats
check_modfly|0
check_autofarm|0
check_bfg|0
check_autobuff|1
check_autoremote|1
check_gems|1
check_lonely|0
check_ignoreo|0
check_ignoref|0
]])
    -- Modfly murni menggunakan Native Bothax
    if ChangeValue then
        pcall(function()
            ChangeValue("[C] Modfly", true)
            ChangeValue("[C] Modfly v2", true)
        end)
    end
    Sleep(300)
end

function ExecutePNBStep()
    if CURRENT_MODE ~= "PNB" then return end
    if not EnsureTargetWorld() then Sleep(2000); return end

    -- Pastikan Mode Ghost Selalu Aktif di PNB agar tidak tersangkut blok
    if IS_GHOST_ON ~= true then
        EnsureGhostActiveDirect()
    end

    local cur_gems = 0
    if GetPlayerInfo then pcall(function() cur_gems = GetPlayerInfo().gems or 0 end) end
    if cur_gems == 0 and getGems then pcall(function() cur_gems = getGems() or 0 end) end
    if cur_gems > last_recorded_gems then
        last_recorded_gems = cur_gems
        MarkActivity()
    end

    -- Pengecekan Cheat Expired di Loop PNB
    if need_buy_cheat then
        local now = os and os.time and os.time() or 0
        if (now - last_buycheat_time) >= 5 then
            last_buycheat_time = now
            Log("`2[AUTO BUY CHEAT] Membeli akses Cheat Menu via paket PNB...`0")
            SendPacket(2, "action|dialog_return\ndialog_name|buycheat\nbuttonClicked|1\n")
            Sleep(800)
        end
        need_buy_cheat = false
        pnb_initialized = false
        CheatTurnOnPNB()
        return
    end

    if not pnb_initialized then
        CheatTurnOff()
        -- Pastikan Ghost Mode aktif sebelum mulai PNB, jika mati langsung nyalakan!
        EnsureGhostActiveDirect(true)

        local pl = GetLocal()
        if PNB_LOCK_X == 0 and PNB_LOCK_Y == 0 and pl and pl.pos then
            PNB_LOCK_X = math.floor(pl.pos.x / 32)
            PNB_LOCK_Y = math.floor(pl.pos.y / 32)
            Log(string.format("`2[PNB] Posisi otomatis dikunci di tempat berdiri: (%d, %d)`0", PNB_LOCK_X, PNB_LOCK_Y))
        end

        Log("`3Memastikan Remote Block dari Magplant...`0")
        local ok = TakeRemoteNextBlockMag()
        if not ok or CURRENT_MODE ~= "PNB" then Sleep(2000); return end

        Log(string.format("`3Menuju titik PNB terkunci di (%d, %d)...`0", PNB_LOCK_X, PNB_LOCK_Y))
        TelePathPNB(PNB_LOCK_X, PNB_LOCK_Y)
        if CURRENT_MODE ~= "PNB" then return end
        Sleep(600)
        CheatTurnOnPNB()
        pnb_initialized = true
        Log("`2Engine PNB BFG Aktif!`0")
    end

    -- Jaga posisi agar tidak tergeser & sinkronisasi aktivitas saat PNB
    local pl = GetLocal()
    if CURRENT_MODE == "PNB" and pl and pl.pos and PNB_LOCK_X ~= 0 and PNB_LOCK_Y ~= 0 then
        local cx = math.floor(pl.pos.x / 32)
        local cy = math.floor(pl.pos.y / 32)
        if cx == PNB_LOCK_X and cy == PNB_LOCK_Y then
            -- Karakter tepat berada di titik PNB terkunci (memang diam memukul), perbarui tanda aktivitas
            MarkActivity()
        else
            -- Langsung matikan cheat autofarm seketika saat posisi bergeser (disengaja/tidak)
            CheatTurnOff()
            Sleep(150)

            local dist_drift = math.abs(cx - PNB_LOCK_X) + math.abs(cy - PNB_LOCK_Y)
            if dist_drift > 3 then
                Log(string.format("`4[KICK/TELEPORT DETECTED] Karakter tergeser sejauh %d blok ke (%d, %d)! Cooldown pemulihan...`0", dist_drift, cx, cy))
                if TextOverlay then pcall(function() TextOverlay("KICK TERDETEKSI: Cooldown Pemulihan 3s...") end) end
                Sleep(3000)
                if ChangeValue then
                    pcall(function()
                        ChangeValue("[C] Modfly", true)
                        ChangeValue("[C] Modfly v2", true)
                    end)
                end
            end

            -- Update posisi riil setelah cooldown
            local p_real = GetLocal()
            local rx = (p_real and p_real.pos) and math.floor(p_real.pos.x / 32) or cx
            local ry = (p_real and p_real.pos) and math.floor(p_real.pos.y / 32) or cy
            Log(string.format("`3[PNB] Berjalan kembali dari titik riil (%d, %d) menuju titik PNB (%d, %d)...`0", rx, ry, PNB_LOCK_X, PNB_LOCK_Y))

            TelePathPNB(PNB_LOCK_X, PNB_LOCK_Y)
            if CURRENT_MODE == "PNB" then
                Sleep(500)
                CheatTurnOnPNB()
                MarkActivity()
            end
        end
    end

    -- Sinkronisasi gems agar aktivitas terhitung saat memukul PNB
    local cur_gems = 0
    if GetPlayerInfo then pcall(function() cur_gems = GetPlayerInfo().gems or 0 end) end
    if cur_gems == 0 and getGems then pcall(function() cur_gems = getGems() or 0 end) end
    if cur_gems ~= last_recorded_gems then
        last_recorded_gems = cur_gems
        MarkActivity()
    end

    -- Pengecekan Penjaga Anti-Stuck (Watchdog):
    -- Hanya aktif jika karakter benar-benar macet/tidak ada aktivitas selama lebih dari 45 detik
    if CheckWatchdogStuck(45) then
        Log("`4[WATCHDOG PENJAGA] Karakter terdeteksi MACET (>45s) saat PNB! Memulihkan & melanjutkan kerja...`0")
        CheatTurnOff()
        Sleep(500)
        if not HasRemote() then
            TakeRemoteNextBlockMag()
        end
        TelePathPNB(PNB_LOCK_X, PNB_LOCK_Y)
        Sleep(600)
        CheatTurnOnPNB()
        MarkActivity()
    end

    CheckAndBuyDiamondLock()

    if is_mag_empty then
        CheatTurnOff()
        current_mag_idx = current_mag_idx + 1
        local ok = TakeRemoteNextBlockMag()
        if ok then
            is_mag_empty = false
            TelePathPNB(PNB_LOCK_X, PNB_LOCK_Y)
            Sleep(600)
            CheatTurnOnPNB()
        else
            Log("`4Seluruh Magplant Block habis! Masuk ke Standby.`0")
            CURRENT_MODE = "IDLE"
            pnb_initialized = false
        end
    end
end

-- =======================================================================
-- HOOK EVENT SERVER & CLIENT
-- =======================================================================
RegisterBothaxHook("onsendpacket", function(type, str)
    if type == 2 or type == 3 then
        if string.find(str, "!gui") or string.find(str, "/gui") or string.find(str, "!menu") or string.find(str, "/menu") then
            GUI_open = true
            Log("`2[GUI] Menampilkan kembali jendela ImGui Bothax!`0")
            return true
        end
        if type == 2 and string.find(str, "action|input") and string.find(str, "/ghost") then
            last_ghost_toggle_time = os and os.time and os.time() or 0
        end
    end
end)

RegisterBothaxHook("onvariant", function(var, netid)
    local ev = tostring(var[0] or "")
    local v1 = tostring(var[1] or "")
    local v2 = tostring(var[2] or "")

    if ev == "OnTalkBubble" or ev == "OnConsoleMessage" then
        local msg = (ev == "OnTalkBubble") and v2 or v1

        -- Deteksi Magplant Habis: Wajib dari NetID karakter sendiri (params 1), bukan dari orang lain!
        if ev == "OnTalkBubble" then
            local pl = GetLocal and GetLocal()
            local my_netid = pl and (pl.netid or pl.netID)
            local speaker_netid = tonumber(var[1])
            if my_netid and speaker_netid and my_netid == speaker_netid then
                if string.find(v2, "MAGPLANT 5000 is empty") or string.find(v2, "is empty") then
                    is_mag_empty = true
                end
            end
        elseif ev == "OnConsoleMessage" then
            if string.find(v1, "The MAGPLANT 5000 is empty") then
                is_mag_empty = true
            end
        end

        -- Deteksi Broadcast / Radio Server (_CT:[SB]_ atau ** from)
        -- Jika terdeteksi ada broadcast masuk, berarti radio sedang AKTIF!
        if string.find(msg, "_CT:%[SB%]_") or string.find(msg, "_CT:%[CB%]_") or string.find(msg, "%*%* from") or string.find(msg, "%*%* Radio:") then
            local now = os and os.time and os.time() or 0
            if (now - last_radio_off_time) >= 8 then
                last_radio_off_time = now
                Log("`6[AUTO-RADIO] Terdeteksi broadcast masuk (Radio masih ON)! Mengirim /radio untuk mematikan...`0")
                SendPacket(2, "action|input\n|text|/radio")
            end
        end

        -- Deteksi Pesan Cheat Expired / Buy Cheat Server
        if string.find(msg:lower(), "boringness") then
            local now = os and os.time and os.time() or 0
            if (now - last_buycheat_time) >= 5 then
                last_buycheat_time = now
                Log("`2[AUTO BUY CHEAT] Terdeteksi cheat expired (boringness)! Membeli otomatis & Menunggu 2 detik...`0")
                SendPacket(2, "action|dialog_return\ndialog_name|buycheat\nbuttonClicked|1\n")
                
                -- Jeda instan agar bot tidak melakukan aksi ilegal tanpa cheat
                Sleep(2000)
                
                -- Trigger ulang pengaktifan fitur cheat spesifik setelah terbeli
                if CURRENT_MODE == "PTHT" then
                    pcall(CheatTurnOnPTHT)
                elseif CURRENT_MODE == "PNB" then
                    pcall(CheatTurnOnPNB)
                end
            end
            need_buy_cheat = false
        elseif string.find(msg, "cheater!") or string.find(msg, "Cheater") then
            need_buy_cheat = false
            SendPacket(2, [[
action|dialog_return
dialog_name|cheats
check_gems|1
check_lonely|0
]])
        end

        -- Deteksi Event Status Ghost Real-time dari Server
        if string.find(msg, "Ghost in the shell mod added") or string.find(msg:lower(), "your body begins to shimmer") then
            IS_GHOST_ON = true
            Log("`2[GHOST DETECTED] Mode Ghost AKTIF (ON)!`0")
        elseif string.find(msg, "Ghost in the shell mod removed") or string.find(msg:lower(), "stops shimmering") then
            IS_GHOST_ON = false
            Log("`4[GHOST DETECTED] Mode Ghost DINONAKTIFKAN (OFF)!`0")
        end
    elseif ev == "OnDialogReturn" then
        local dialog_name = tostring(var[1] or "")
        local btn = tostring(var[2] or "")

        if dialog_name == "piers_promo" then
            if btn == "join_discord" then
                -- Klik tombol Discord: buka link di browser
                SendPacket(2, "action|input\n|text|/url discord.gg/sExzWKEker\n")
                Log("`2[PROMO] Membuka Discord Piers Store...`0")
            end
            return true
        end

    elseif ev == "OnDialogRequest" then
        captured_dialog = v1

        -- Deteksi Dialog Profil / Wrench Diri Sendiri (Hanya blokir jika dipicu probe internal script)
        if string.find(v1, "backpack slots") or string.find(v1, "Active effects:") or string.find(v1, "dialog_name|popup") then
            if string.find(v1, "Ghost in the shell") then
                IS_GHOST_ON = true
            else
                IS_GHOST_ON = false
            end
            if not string.find(v1, "Cheater") then
                need_buy_cheat = true
            else
                need_buy_cheat = false
            end
            if silent_profile_probe then
                silent_profile_probe = false
                SendPacket(2, "action|dialog_return\ndialog_name|popup\n")
                return true -- Hanya blokir jika dipicu oleh probe internal bot!
            end
            -- Jika user yang wrench sendiri: biarkan dialog terbuka normal di layar!
            return false
        end

        if string.find(v1, "buycheat") or string.find(v1, "Buy Access To") or string.find(v1, "Cheat Menu") then
            local now = os and os.time and os.time() or 0
            if (now - last_buycheat_time) >= 5 then
                last_buycheat_time = now
                Log("`2[AUTO BUY CHEAT] Menerima dialog cheat! Membeli otomatis (50 WL)...`0")
                SendPacket(2, "action|dialog_return\ndialog_name|buycheat\nbuttonClicked|1\n")
            else
                -- Masa cooldown: kirim penutup dialog agar tidak mengunci layar
                SendPacket(2, "action|dialog_return\ndialog_name|buycheat\nbuttonClicked|1\n")
            end
            need_buy_cheat = false
        elseif string.find(v1, "piers_promo") then
            -- Dialog Promo Piers Store: tampilkan saja, jangan auto-close
            return false
        elseif string.find(v1, "telephone") or string.find(v1, "Diamond Lock") then
            if not AutoBuyDL_Checked then
                SendPacket(2, "action|dialog_return\ndialog_name|telephone\nbuttonClicked|hangup\n")
            elseif string.find(v1, "dlconvert") then
                SendPacket(2, string.format("action|dialog_return\ndialog_name|telephone\nnum|%s|\nbuttonClicked|dlconvert\n", TELEPHONE_NUMBER or "53785"))
            elseif string.find(v1, "bglconvert") then
                SendPacket(2, string.format("action|dialog_return\ndialog_name|telephone\nnum|%s|\nbuttonClicked|bglconvert\n", TELEPHONE_NUMBER or "53785"))
            end
        end
    end
end)

-- =======================================================================
-- FUNGSI KONTROL GHOST (AUTO-TOGGLE SECARA LANGSUNG)
-- Alur Cerdas:
-- 1. Bot langsung mengirim /ghost ke chat
-- 2. Jika respon server: "mod removed" (artinya tadi menyala dan barusan mati),
--    maka bot LANGSUNG mengirim /ghost sekali lagi agar kembali MENYALA (ON)!
-- 3. Jika respon server: "mod added" (artinya tadi mati dan sekarang aktif),
--    maka SELESAI, Ghost sudah aktif!
-- =======================================================================
function EnsureGhostActiveDirect(force_verify)
    if not InWorld() then return end
    if not force_verify and IS_GHOST_ON == true then
        return
    end

    -- Jika belum terdeteksi (nil), lakukan silent wrench cepat ke diri sendiri
    if IS_GHOST_ON == nil then
        local pl = GetLocal and GetLocal()
        if pl and pl.pos then
            local mx = math.floor(pl.pos.x / 32)
            local my = math.floor(pl.pos.y / 32)
            SendPacketRaw(false, {type = 3, state = 32, value = 32, px = mx, py = my, x = mx * 32, y = my * 32})
        end
        local wait = 0
        while wait < 6 and InWorld() and IS_GHOST_ON == nil do
            Sleep(80)
            wait = wait + 1
        end
    end

    -- Jika terbukti MATI (atau belum aktif), langsung nyalakan seketika!
    if IS_GHOST_ON ~= true then
        local now = os and os.time and os.time() or 0
        local last_t = last_ghost_toggle_time or 0
        if (now - last_t) < 3.2 then
            local wait_sec = math.ceil(3.2 - (now - last_t))
            Sleep(wait_sec * 1000)
        end

        Log("`3[GHOST] Ghost Mode MATI! Mengirim /ghost untuk mengaktifkan...`0")
        last_ghost_toggle_time = os and os.time and os.time() or 0
        SendPacket(2, "action|input\n|text|/ghost")
        Sleep(600)
        IS_GHOST_ON = true
        Log("`2[GHOST] Mode Ghost BERHASIL AKTIF (ON)!`0")
        if TextOverlay then pcall(function() TextOverlay("Ghost Mode: ON") end) end
    else
        Log("`2[GHOST] Mode Ghost sudah dipastikan AKTIF (ON)!`0")
    end
end

function SyncAndEnableGhostAtStart()
    if not InWorld() then return end
    Log("`3[STARTUP] Memeriksa status Ghost Mode awal karakter...`0")

    -- 1. Lakukan silent wrench ke diri sendiri untuk memicu dialog profil
    local pl = GetLocal and GetLocal()
    if pl and pl.pos then
        local mx = math.floor(pl.pos.x / 32)
        local my = math.floor(pl.pos.y / 32)
        silent_profile_probe = true
        SendPacketRaw(false, {type = 3, state = 32, value = 32, px = mx, py = my, x = mx * 32, y = my * 32})
    end

    -- 2. Tunggu sebentar hingga silent hook membaca status buff resmi
    local wait = 0
    while wait < 8 and InWorld() and IS_GHOST_ON == nil do
        Sleep(100)
        wait = wait + 1
    end
    silent_profile_probe = false

    -- 3. Jika terdeteksi MATI (atau belum aktif), langsung nyalakan seketika!
    if IS_GHOST_ON ~= true then
        Log("`4[STARTUP] Ghost Mode terdeteksi MATI! Mengaktifkan otomatis (/ghost)...`0")
        local now = os and os.time and os.time() or 0
        local last_t = last_ghost_toggle_time or 0
        if (now - last_t) < 3.2 then
            Sleep(math.ceil(3.2 - (now - last_t)) * 1000)
        end
        last_ghost_toggle_time = os and os.time and os.time() or 0
        SendPacket(2, "action|input\n|text|/ghost")
        Sleep(600)
        IS_GHOST_ON = true
        Log("`2[STARTUP] Ghost Mode BERHASIL DIAKTIFKAN di awal!`0")
        if TextOverlay then pcall(function() TextOverlay("Ghost Mode: AUTO-ACTIVATED (ON)") end) end
    else
        Log("`2[STARTUP] Ghost Mode terdeteksi SUDAH AKTIF (ON)!`0")
        if TextOverlay then pcall(function() TextOverlay("Ghost Mode: ALREADY ON") end) end
    end
end

function EnsureGhostOff()
    if not InWorld() then return end
    if IS_GHOST_ON == true then
        local now = os and os.time and os.time() or 0
        local last_t = last_ghost_toggle_time or 0
        if (now - last_t) < 3.2 then
            Sleep(3200)
        end
        Log("`3[GHOST] Mematikan mode Ghost (/ghost)...`0")
        last_ghost_toggle_time = os and os.time and os.time() or 0
        SendPacket(2, "action|input\n|text|/ghost")
        Sleep(600)
    end
end

-- =======================================================================
-- LOOP UTAMA CONTROLLER (STANDALONE MURNI)
-- =======================================================================

local function ShowPromoDialog()
    if promo_dialog_shown then return end
    promo_dialog_shown = true
    local dialog = table.concat({
        "add_label_with_icon|big|`2Piers Store|left|1426|",
        "add_spacer|small|",
        "add_textbox|`6PNB BFG Script|",
        "add_textbox|`9Auto Buy BGL / Black Auto Store|",
        "add_spacer|small|",
        "add_textbox|`eDiscord: `0discord.gg/sExzWKEker|",
        "add_spacer|small|",
        "add_url_button|join_discord|`9[ Join Discord ]|noflags|https://discord.gg/sExzWKEker|Buka Discord|0|0|",
        "end_dialog|piers_promo||Tutup|",
    }, "\n")

    -- SendVariantList OnDialogRequest
    local ok = false
    if SendVariant then
        ok = pcall(function() SendVariant({[0] = "OnDialogRequest", [1] = dialog}) end)
    end
    if not ok and SendVariantList then
        ok = pcall(function() SendVariantList({[0] = "OnDialogRequest", [1] = dialog}) end)
    end
    if ok then
        Log("`2[PROMO] Dialog Piers Store ditampilkan!`0")
    else
        Log("`4[PROMO] Gagal menampilkan dialog promo.`0")
        promo_dialog_shown = false
    end
end

RunThread(function()
    Log("`2[PIERS BOT] Menginisialisasi PNB BFG Controller v1.0...`0")
    while not InWorld() do
        Sleep(1000)
    end

    -- Tampilkan dialog promo Piers Store DULUAN saat execute (sebelum cek lisensi)
    pcall(ShowPromoDialog)

    -- Eksekusi pengecekan lisensi & kill-switch jarak jauh
    local is_allowed = CheckLicenseAuth()
    if not is_allowed then
        local uid = "Unknown"
        pcall(function() uid = tostring(GetLocal().userid) end)
        Log("`4[PIERS BOT] Akses ditolak untuk UID: " .. uid .. "`0")
        
        -- Dialog khusus akses ditolak
        local denied_dialog = table.concat({
            "add_label_with_icon|big|`4Akses Ditolak!|left|1426|",
            "add_spacer|small|",
            "add_textbox|`6UID kamu belum terdaftar di database kami.|",
            "add_textbox|`9Silakan hubungi admin di Discord untuk aktivasi.|",
            "add_spacer|small|",
            "add_url_button|join_discord|`9[ Join Discord ]|noflags|https://discord.gg/sExzWKEker|Buka Discord|0|0|",
            "end_dialog|piers_denied||Keluar|",
        }, "\n")
        
        local ok = false
        if SendVariant then
            ok = pcall(function() SendVariant({[0] = "OnDialogRequest", [1] = denied_dialog}) end)
        end
        if not ok and SendVariantList then
            ok = pcall(function() SendVariantList({[0] = "OnDialogRequest", [1] = denied_dialog}) end)
        end
        
        return
    end

    -- Auto-load konfigurasi default terakhir jika ada
    pcall(function() LoadConfigFromFile(CONFIG_FILE_NAME) end)

    -- PROBE OTOMATIS: Wrench diri sendiri untuk cek status cheat saat startup
    Log("`3[STARTUP] Memeriksa status cheat...`0")
    silent_profile_probe = true
    SendPacket(2, "action|wrench\n|netid|" .. GetLocal().netid .. "\n")
    Sleep(1500)
    silent_profile_probe = false -- jangan biarkan probe mengunci dialog user
    if need_buy_cheat then
        Log("`4[STARTUP] Cheat terdeteksi mati, membeli otomatis...`0")
        SendPacket(2, "action|dialog_return\ndialog_name|buycheat\nbuttonClicked|1\n")
        Sleep(1000)
        need_buy_cheat = false
    else
        Log("`2[STARTUP] Status Cheat AKTIF.`0")
    end

    -- Nyalakan Native Bothax Modfly saat script pertama kali dijalankan
    if ChangeValue then
        pcall(function()
            ChangeValue("[C] Modfly", true)
            ChangeValue("[C] Modfly v2", true)
        end)
        Log("`2[MODFLY] Native Bothax Modfly otomatis aktif di awal!`0")
    end

    Sleep(500)

    -- Deteksi Ghost Mode saat awal script dijalankan: jika mati langsung aktifkan otomatis!
    pcall(SyncAndEnableGhostAtStart)

    while true do
        if need_buy_dl_now then
            need_buy_dl_now = false
            pcall(function() CheckAndBuyDiamondLock(true) end)
        end

        if CURRENT_MODE == "PTHT" then
            if not EnsureTargetWorld() then
                Sleep(2500)
            else
                if AutoBuyDL_Checked then pcall(CheckAndBuyDiamondLock) end
                local ok, err = pcall(ExecutePTHTCycle)
                if not ok then
                    Log("`4[PTHT ERROR] " .. tostring(err) .. "`0")
                    Sleep(2000)
                end
                Sleep(200)
            end
        elseif CURRENT_MODE == "PNB" then
            if not EnsureTargetWorld() then
                Sleep(2500)
            else
                local ok, err = pcall(ExecutePNBStep)
                if not ok then
                    Log("`4[PNB ERROR] " .. tostring(err) .. "`0")
                    Sleep(2000)
                end
                Sleep(200)
            end
        else
            -- Mode IDLE / STANDBY: Benar-benar diam 100%, jangan warp/join world atau bergerak
            if AutoBuyDL_Checked then
                local cur_gems = 0
                if GetPlayerInfo then pcall(function() cur_gems = GetPlayerInfo().gems or 0 end) end
                if cur_gems == 0 and getGems then pcall(function() cur_gems = getGems() or 0 end) end
                if cur_gems >= 200000 then
                    pcall(CheckAndBuyDiamondLock)
                end
            end
            Sleep(150)
            if collectgarbage then collectgarbage("step", 20) end
        end
    end
end)
