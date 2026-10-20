-- Piers Store - Auth System
-- Remake: Centralized UID License Verification

local LICENSE_URL = "https://raw.githubusercontent.com/Piercs033/PTHT_PNB_bhax/main/license.json"

function VerifyUID(uid)
    if not uid then return false end
    local response, error_msg = MakeRequest(LICENSE_URL, "GET")
    if not response or response == "" then
        Log("`4[AUTH] Gagal menghubungi server lisensi! (Offline)`0")
        return false
    end
    
    -- Parse JSON manual sederhana atau gunakan json.decode jika tersedia
    local is_allowed = string.find(response, '"' .. tostring(uid) .. '"') ~= nil
    return is_allowed
end

function ShowAccessDeniedDialog()
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
end
