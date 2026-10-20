-- Piers Store - Auth System (Multi-Product)
-- Sistem lisensi terpisah per tipe produk

local BASE_URL = "https://raw.githubusercontent.com/aidris23/PTHT_PNB/main/"

-- license_type: "ptht" atau "pnb"
function VerifyUID(uid, license_type)
    if not uid or not license_type then return false end
    
    local url = BASE_URL .. "license_" .. license_type .. ".json"
    local response, error_msg = MakeRequest(url, "GET")
    
    if not response or response == "" then
        Log("`4[AUTH] Gagal menghubungi server lisensi untuk " .. license_type .. "!`0")
        return false
    end
    
    -- Mencari UID di dalam file JSON
    -- Contoh isi file: ["123456", "789012"]
    local is_allowed = string.find(response, '"' .. tostring(uid) .. '"') ~= nil
    return is_allowed
end

function ShowAccessDeniedDialog(product_name)
    local denied_dialog = table.concat({
        "add_label_with_icon|big|`4Akses Ditolak!|left|1426|",
        "add_spacer|small|",
        "add_textbox|`6UID kamu belum terdaftar untuk produk:|",
        "add_textbox|`e" .. product_name .. "|",
        "add_spacer|small|",
        "add_url_button|join_discord|`9[ Hubungi Admin ]|noflags|https://discord.gg/sExzWKEker|Buka Discord|0|0|",
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
