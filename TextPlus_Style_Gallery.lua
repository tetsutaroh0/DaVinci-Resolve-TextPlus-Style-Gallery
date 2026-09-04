-- Text+ Style Gallery for DaVinci Resolve / Fusion
-- Version 1.0.0
-- Release date: 2026-09-04
--
-- A native Lua Text+ style manager with 100 style slots, SVG previews,
-- multiple Shading Element support, and import/export.
--
-- Copyright (c) 2026 Text+ Style Gallery contributors
-- Licensed under the MIT License.

local VERSION = "1.0.0"
local RELEASE_DATE = "2026-09-04"

local PAGE_SIZE = 10
local PAGE_COUNT = 10
local SLOT_COUNT = PAGE_SIZE * PAGE_COUNT
local FIXED_STYLES_NAME = "textplus_styles_10x10_lua.json"
local PYTHON_STYLES_NAME = "textplus_styles_10x10.json"
local LEGACY_STYLES_NAME = "textplus_styles_8x8.json"
local CURRENT_CLIP_OPTION = "Current Clip (playhead)"
local PREVIEW_TEXT = "Aaあア123"
local THUMB_W, THUMB_H = 190, 54
local CARD_BG = "#252525"

local COLOR_OPTIONS = {
    CURRENT_CLIP_OPTION, "Any", "Blue", "Cyan", "Green", "Yellow", "Red",
    "Pink", "Purple", "Fuchsia", "Rose", "Lavender", "Sky", "Mint",
    "Lemon", "Sand", "Cocoa", "Cream"
}

-- ---------------------------------------------------------------------------
-- Small compatibility helpers
-- ---------------------------------------------------------------------------

local function safe_call(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function script_dir()
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    local dir = src:match("^(.*)[/\\][^/\\]+$")
    if dir and dir ~= "" then return dir end
    return "."
end

local function path_join(a, b)
    if not a or a == "" then return b end
    local sep = package.config:sub(1, 1)
    if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
    return a .. sep .. b
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function ensure_dir(path)
    if not path or path == "" then return false end
    if bmd and bmd.createdir then
        local ok = pcall(function() bmd.createdir(path) end)
        if ok then return true end
    end
    if package.config:sub(1,1) == "\\" then
        os.execute('mkdir "' .. path .. '" >nul 2>nul')
    else
        os.execute('mkdir -p "' .. path .. '" >/dev/null 2>&1')
    end
    return true
end

local function user_data_dir()
    local candidates = {}
    local appdata = os.getenv("APPDATA")
    local localappdata = os.getenv("LOCALAPPDATA")
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    if appdata and appdata ~= "" then table.insert(candidates, path_join(appdata, "TextPlusStyleGallery")) end
    if localappdata and localappdata ~= "" then table.insert(candidates, path_join(localappdata, "TextPlusStyleGallery")) end
    if home and home ~= "" then table.insert(candidates, path_join(home, ".TextPlusStyleGallery")) end
    table.insert(candidates, path_join(script_dir(), "TextPlusStyleGalleryData"))

    for _, p in ipairs(candidates) do
        ensure_dir(p)
        local probe = path_join(p, ".write_test")
        local f = io.open(probe, "wb")
        if f then
            f:write("ok"); f:close(); os.remove(probe)
            return p
        end
    end
    return script_dir()
end

local USER_DATA_DIR = user_data_dir()
local STYLES_FILE = path_join(USER_DATA_DIR, FIXED_STYLES_NAME)
local LOG_FILE = path_join(USER_DATA_DIR, "textplus_style_gallery_lua.log")
local THUMB_DIR = path_join(USER_DATA_DIR, "thumb_cache_lua")
ensure_dir(THUMB_DIR)

local function log_line(msg)
    local f = io.open(LOG_FILE, "ab")
    if not f then return end
    f:write(os.date("[%Y-%m-%d %H:%M:%S] "), tostring(msg), "\n")
    f:close()
end

local function copy_table(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[copy_table(k, seen)] = copy_table(v, seen) end
    return out
end

local function clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function rgb_hex(r, g, b)
    return string.format("#%02X%02X%02X", math.floor(clamp01(r)*255+0.5), math.floor(clamp01(g)*255+0.5), math.floor(clamp01(b)*255+0.5))
end

local function xml_escape(s)
    s = tostring(s or "")
    s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    s = s:gsub('"', "&quot;"):gsub("'", "&apos;")
    return s
end

-- ---------------------------------------------------------------------------
-- Minimal JSON codec (Lua 5.1 compatible)
-- ---------------------------------------------------------------------------

local json = {}

local escape_char_map = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'
}

local function json_escape_string(s)
    return '"' .. tostring(s):gsub('[%z\1-\31\\"]', function(c)
        return escape_char_map[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
end

local function is_array(t)
    local max, count = 0, 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false, 0 end
        if k > max then max = k end
        count = count + 1
    end
    if max ~= count then return false, 0 end
    return true, max
end

local function encode_value(v, stack, indent, level)
    local tv = type(v)
    if v == nil then return "null" end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return tostring(v)
    end
    if tv == "string" then return json_escape_string(v) end
    if tv ~= "table" then return "null" end
    if stack[v] then error("circular reference") end
    stack[v] = true
    local arr, n = is_array(v)
    local pieces = {}
    local pad = indent and string.rep(" ", level * indent) or ""
    local childpad = indent and string.rep(" ", (level + 1) * indent) or ""
    local sep = indent and ",\n" or ","
    if arr then
        for i = 1, n do
            local ev = encode_value(v[i], stack, indent, level + 1)
            if indent then ev = childpad .. ev end
            table.insert(pieces, ev)
        end
        stack[v] = nil
        if #pieces == 0 then return "[]" end
        return indent and ("[\n" .. table.concat(pieces, sep) .. "\n" .. pad .. "]") or ("[" .. table.concat(pieces, sep) .. "]")
    else
        local keys = {}
        for k, _ in pairs(v) do table.insert(keys, tostring(k)) end
        table.sort(keys)
        for _, ks in ipairs(keys) do
            local vv = v[ks]
            if vv == nil then
                -- Recover non-string original key if needed.
                for k, x in pairs(v) do if tostring(k) == ks then vv = x; break end end
            end
            local ev = json_escape_string(ks) .. ":" .. (indent and " " or "") .. encode_value(vv, stack, indent, level + 1)
            if indent then ev = childpad .. ev end
            table.insert(pieces, ev)
        end
        stack[v] = nil
        if #pieces == 0 then return "{}" end
        return indent and ("{\n" .. table.concat(pieces, sep) .. "\n" .. pad .. "}") or ("{" .. table.concat(pieces, sep) .. "}")
    end
end

function json.encode(v, indent)
    return encode_value(v, {}, indent, 0)
end

local function utf8_from_codepoint(cp)
    if cp <= 0x7F then return string.char(cp) end
    if cp <= 0x7FF then return string.char(0xC0 + math.floor(cp/64), 0x80 + (cp % 64)) end
    if cp <= 0xFFFF then
        return string.char(0xE0 + math.floor(cp/4096), 0x80 + (math.floor(cp/64) % 64), 0x80 + (cp % 64))
    end
    return string.char(0xF0 + math.floor(cp/262144), 0x80 + (math.floor(cp/4096) % 64), 0x80 + (math.floor(cp/64) % 64), 0x80 + (cp % 64))
end

function json.decode(str)
    local pos, len = 1, #str
    local parse_value
    local function skip_ws()
        while pos <= len and str:sub(pos,pos):match("%s") do pos = pos + 1 end
    end
    local function parse_string()
        pos = pos + 1
        local out = {}
        while pos <= len do
            local c = str:sub(pos,pos)
            if c == '"' then pos = pos + 1; return table.concat(out) end
            if c == '\\' then
                local e = str:sub(pos+1,pos+1)
                local map = { ['"']='"', ['\\']='\\', ['/']='/', ['b']='\b', ['f']='\f', ['n']='\n', ['r']='\r', ['t']='\t' }
                if e == 'u' then
                    local hex = str:sub(pos+2,pos+5)
                    local cp = tonumber(hex, 16)
                    if not cp then error("invalid unicode escape at " .. pos) end
                    pos = pos + 6
                    if cp >= 0xD800 and cp <= 0xDBFF and str:sub(pos,pos+1) == "\\u" then
                        local low = tonumber(str:sub(pos+2,pos+5), 16)
                        if low and low >= 0xDC00 and low <= 0xDFFF then
                            cp = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
                            pos = pos + 6
                        end
                    end
                    table.insert(out, utf8_from_codepoint(cp))
                else
                    if not map[e] then error("invalid escape at " .. pos) end
                    table.insert(out, map[e]); pos = pos + 2
                end
            else
                table.insert(out, c); pos = pos + 1
            end
        end
        error("unterminated string")
    end
    local function parse_number()
        local start = pos
        while pos <= len and str:sub(pos,pos):match("[%d%+%-%eE%.]") do pos = pos + 1 end
        local n = tonumber(str:sub(start,pos-1))
        if n == nil then error("invalid number at " .. start) end
        return n
    end
    local function parse_array()
        pos = pos + 1; skip_ws()
        local out = {}
        if str:sub(pos,pos) == "]" then pos = pos + 1; return out end
        while true do
            table.insert(out, parse_value()); skip_ws()
            local c = str:sub(pos,pos)
            if c == "]" then pos = pos + 1; return out end
            if c ~= "," then error("expected ',' or ']' at " .. pos) end
            pos = pos + 1; skip_ws()
        end
    end
    local function parse_object()
        pos = pos + 1; skip_ws()
        local out = {}
        if str:sub(pos,pos) == "}" then pos = pos + 1; return out end
        while true do
            if str:sub(pos,pos) ~= '"' then error("expected string key at " .. pos) end
            local key = parse_string(); skip_ws()
            if str:sub(pos,pos) ~= ":" then error("expected ':' at " .. pos) end
            pos = pos + 1; skip_ws(); out[key] = parse_value(); skip_ws()
            local c = str:sub(pos,pos)
            if c == "}" then pos = pos + 1; return out end
            if c ~= "," then error("expected ',' or '}' at " .. pos) end
            pos = pos + 1; skip_ws()
        end
    end
    parse_value = function()
        skip_ws()
        local c = str:sub(pos,pos)
        if c == '"' then return parse_string() end
        if c == "{" then return parse_object() end
        if c == "[" then return parse_array() end
        if c == "-" or c:match("%d") then return parse_number() end
        if str:sub(pos,pos+3) == "true" then pos = pos + 4; return true end
        if str:sub(pos,pos+4) == "false" then pos = pos + 5; return false end
        if str:sub(pos,pos+3) == "null" then pos = pos + 4; return nil end
        error("unexpected token at " .. pos)
    end
    local result = parse_value(); skip_ws()
    if pos <= len then error("trailing data at " .. pos) end
    return result
end

local function read_json(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a"); f:close()
    local ok, data = pcall(json.decode, text)
    if not ok then log_line("JSON read failed: " .. tostring(data)); return nil end
    return data
end

local function write_json(path, data)
    local f, err = io.open(path, "wb")
    if not f then return false, err end
    local ok, text = pcall(json.encode, data, 2)
    if not ok then f:close(); return false, text end
    f:write(text); f:close(); return true
end

-- ---------------------------------------------------------------------------
-- Resolve / Fusion access
-- ---------------------------------------------------------------------------

local function get_resolve()
    if resolve then return resolve end
    if bmd and bmd.scriptapp then return safe_call(function() return bmd.scriptapp("Resolve") end) end
    return nil
end

local function get_fusion()
    if fusion then return fusion end
    if bmd and bmd.scriptapp then return safe_call(function() return bmd.scriptapp("Fusion") end) end
    return nil
end

local function get_current_timeline()
    local r = get_resolve(); if not r then return nil end
    local pm = safe_call(function() return r:GetProjectManager() end); if not pm then return nil end
    local project = safe_call(function() return pm:GetCurrentProject() end); if not project then return nil end
    return safe_call(function() return project:GetCurrentTimeline() end)
end

local function get_comp_list(item)
    local out = {}
    local count = safe_call(function() return item:GetFusionCompCount() end) or 0
    for i = 1, tonumber(count) or 0 do
        local comp = safe_call(function() return item:GetFusionCompByIndex(i) end)
        if comp then table.insert(out, comp) end
    end
    return out
end

local function find_text_tools(comp)
    local out = {}
    local tools = safe_call(function() return comp:GetToolList(false, "TextPlus") end)
    if type(tools) == "table" then
        for _, tool in pairs(tools) do table.insert(out, tool) end
    end
    if #out == 0 then
        tools = safe_call(function() return comp:GetToolList(false) end)
        if type(tools) == "table" then
            for _, tool in pairs(tools) do
                local attrs = safe_call(function() return tool:GetAttrs() end) or {}
                if attrs.TOOLS_RegID == "TextPlus" or attrs.TOOLS_Name == "Text+" then table.insert(out, tool) end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Style capture / application
-- ---------------------------------------------------------------------------

local EXCLUDED_IDS = {
    -- Text content / visibility / animation controls must stay with the target clip.
    StyledText=true, TextText=true,
    Start=true, End=true, Scroll=true, ScrollPosition=true,

    -- Timeline / frame-format / render plumbing.
    GlobalIn=true, GlobalOut=true,
    Width=true, Height=true, PixelAspect=true, UseFrameFormatSettings=true, Depth=true,
    HideInputs=true, ProcessMode=true, MotionBlur=true, Quality=true,
    ShutterAngle=true, CenterBias=true, SampleSpread=true,

    -- Mask / scripting / bookkeeping.
    EffectMask=true, ApplyMaskInverted=true, MultiplyByMask=true, FitMask=true,
    MaskChannel=true, MaskLow=true, MaskHigh=true, MaskClipBlack=true, MaskClipWhite=true,
    Comments=true, FrameRenderScript=true, StartRenderScripts=true, StartRenderScript=true,
    EndRenderScripts=true, EndRenderScript=true,
}

-- IDs that move/reflow the destination text are intentionally not part of an
-- appearance style.  The first generic Lua build copied almost every simple
-- Text+ input; that also copied layout/transform values and could make the text
-- jump off-screen late in the Apply loop.
local SPATIAL_IDS = {
    Center=true, LayoutType=true, LayoutRotation=true, LayoutAngle=true,
    LayoutWidth=true, LayoutHeight=true, LayoutSize=true,
    Position=true, PositionX=true, PositionY=true, PositionZ=true,
    Offset=true, OffsetX=true, OffsetY=true, OffsetZ=true,
    Rotation=true, AngleX=true, AngleY=true, AngleZ=true,
    Pivot=true, PivotX=true, PivotY=true, PivotZ=true,
    Shear=true, ShearX=true, ShearY=true,
    Transform=true, TransformSize=true, TransformRotation=true,
}

local function is_shading_input_id(iid)
    -- Text+ exposes many Shading Element controls beyond the obvious color /
    -- thickness fields.  Crucially, Position1/Rotation1/Pivot1/Size1 and the
    -- *Clone fields also belong to the Shading stack.  Replaying those through
    -- the generic pass can make the rendered text walk off-screen or fade while
    -- Apply is still running.  Keep every per-element shading control out of the
    -- generic pass and let apply_shading_elements() own the stack.
    local patterns = {
        "^Enabled%d+$", "^Name%d+$", "^ElementShape%d+$",
        "^Red%d+$", "^Green%d+$", "^Blue%d+$", "^Alpha%d+$",
        "^Red%d+Clone$", "^Green%d+Clone$", "^Blue%d+Clone$", "^Alpha%d+Clone$",
        "^Thickness%d+$", "^Opacity%d+$",
        "^Softness%d+$", "^SoftnessX%d+$", "^SoftnessY%d+$",
        "^SoftnessGlow%d+$", "^SoftnessBlend%d+$", "^SoftnessOnFillColorToo%d+$",
        "^OutsideOnly%d+$", "^PriorityBack%d+$", "^OverrideColor%d+$",
        "^Offset%d+$", "^OffsetZ%d+$",
        "^Position%d+$", "^Rotation%d+$", "^AngleX%d+$", "^AngleY%d+$", "^AngleZ%d+$",
        "^Pivot%d+$", "^PivotZ%d+$",
        "^Shear%d+$", "^ShearX%d+$", "^ShearY%d+$",
        "^Size%d+$", "^SizeX%d+$", "^SizeY%d+$",
        "^Shading.*%d+$", "^ImageShading.*%d+$"
    }
    for _, pat in ipairs(patterns) do
        if iid:match(pat) then return true end
    end
    return false
end

local SHADING_LEGACY_ALIAS_IDS = {
    Outline=true, DropShadow=true,
    ShdwDistance=true, ShdwSoftness=true, ShdwAngle=true, ShdwOpacity=true,
}

-- Forward declaration is required in Lua: is_safe_generic_apply_id() is
-- defined before the implementation below and must reference this local, not
-- an accidental global named is_style_input_id.
local is_style_input_id

local function is_safe_generic_apply_id(iid)
    -- Capture may remain broad for diagnostics / future compatibility, but Apply
    -- is deliberately conservative.  Only typography controls that cannot move
    -- the text off-screen or blank the Shading stack are replayed generically.
    if not is_style_input_id(iid) then return false end
    if iid == "Font" or iid == "Style" or iid == "Size" then return true end
    if iid == "CharacterSpacing" or iid == "CharacterSpacingClone" then return true end
    if iid == "LineSpacing" or iid == "LineSpacingClone" then return true end
    if iid == "Strikeout" or iid == "Underline" then return true end
    if iid == "Direction" or iid == "LineDirection" then return true end
    if iid == "HorizontalJustification" or iid == "HorizontalJustificationNew" or
       iid == "HorizontalJustificationLeft" or iid == "HorizontalJustificationCenter" or
       iid == "HorizontalJustificationRight" or iid == "HorizontalLeftCenterRight" or
       iid == "HorizontallyJustified" then return true end
    if iid == "VerticalJustification" or iid == "VerticalJustificationNew" or
       iid == "VerticalJustificationTop" or iid == "VerticalJustificationCenter" or
       iid == "VerticalJustificationBottom" or iid == "VerticalTopCenterBottom" or
       iid == "VerticallyJustified" or iid == "CenterOnBaseOfFirstLine" then return true end
    if iid == "TabSpacing" or iid == "Tab" or iid:match("^Tab%d+Position$") or iid:match("^Tab%d+Alignment$") then return true end
    return false
end

is_style_input_id = function(iid)
    iid = tostring(iid or "")
    if iid == "" or EXCLUDED_IDS[iid] or SPATIAL_IDS[iid] then return false end
    if is_shading_input_id(iid) then return false end
    if iid:sub(1,6) == "Gamut." then return false end
    if iid:match("Nest$") or iid:match("Spacer$") or iid:match("Separator$") then return false end
    if iid:match("^Properties%d+$") or iid == "Select" or iid == "SelectElement" or iid == "SortShadingElements" then return false end

    -- Broad safety net for layout / transform / animation plumbing.  Keep
    -- typography names such as HorizontalJustification, VerticalJustification,
    -- CharacterSpacing and LineSpacing, but reject coordinates and tool motion.
    local low = iid:lower()
    if low == "center" or low:match("^center[xyz]$") then return false end
    if low:match("^layout.*(center|position|width|height|rotation|angle|size)") then return false end
    if low:match("^transform") then return false end
    if low:match("^pivot") or low:match("^shear") then return false end
    if low:match("^angle[xyz]$") or low:match("^rotation[xyz]$") then return false end
    return true
end

local function json_safe_value(v, depth)
    depth = depth or 0
    if depth > 6 then return nil, false end
    local tv = type(v)
    if tv == "nil" then return nil, true end
    if tv == "number" or tv == "string" or tv == "boolean" then return v, true end
    if tv ~= "table" then
        local n = tonumber(v)
        if n then return n, true end
        return nil, false
    end
    local out = {}
    for k, value in pairs(v) do
        local converted, ok = json_safe_value(value, depth + 1)
        if not ok then return nil, false end
        out[k] = converted
    end
    return out, true
end

local function scalar(v)
    local c, ok = json_safe_value(v)
    if ok and (type(c)=="number" or type(c)=="string" or type(c)=="boolean") then return c end
    return nil
end

local function capture_all_style_inputs(tool)
    local params, complex, excluded, total = {}, {}, {}, 0
    local input_list = safe_call(function() return tool:GetInputList() end) or {}
    for key, inp in pairs(input_list) do
        total = total + 1
        local attrs = safe_call(function() return inp:GetAttrs() end) or {}
        local iid = tostring(attrs.INPS_ID or key)
        if not is_style_input_id(iid) then
            table.insert(excluded, iid)
        else
            local raw = safe_call(function() return tool:GetInput(iid) end)
            local converted, ok = json_safe_value(raw)
            if ok and converted ~= nil then params[iid] = converted
            elseif raw ~= nil then table.insert(complex, iid) end
        end
    end
    log_line(string.format("capture: generic inputs total=%d saved=%d excluded=%d complex_skipped=%d", total,
        (function() local n=0 for _ in pairs(params) do n=n+1 end return n end)(), #excluded, #complex))
    if #complex > 0 then
        local s = {} for i=1, math.min(40,#complex) do s[#s+1]=complex[i] end
        log_line("capture: complex values skipped: " .. table.concat(s, ", "))
    end
    return params
end

local function capture_shading_elements(tool)
    local elements = {}
    for i = 1, 8 do
        local enabled = safe_call(function() return tool:GetInput("Enabled" .. i) end)
        if enabled and tonumber(enabled) ~= 0 then
            local function gi(prefix) return safe_call(function() return tool:GetInput(prefix .. i) end) end
            local e = {
                index=i, name=gi("Name") or "", shape=scalar(gi("ElementShape")),
                red=scalar(gi("Red")), green=scalar(gi("Green")), blue=scalar(gi("Blue")), alpha=scalar(gi("Alpha")),
                thickness=scalar(gi("Thickness")), opacity=scalar(gi("Opacity")), softness=scalar(gi("Softness")),
                softness_x=scalar(gi("SoftnessX")), softness_y=scalar(gi("SoftnessY")), softness_glow=scalar(gi("SoftnessGlow")),
                outside_only=scalar(gi("OutsideOnly")), priority_back=scalar(gi("PriorityBack")), override_color=scalar(gi("OverrideColor")),
            }
            local offset = gi("Offset")
            if type(offset) == "table" then
                e.offset_x = tonumber(offset[1] or offset["1"] or 0) or 0
                e.offset_y = tonumber(offset[2] or offset["2"] or 0) or 0
            else e.offset_x, e.offset_y = 0, 0 end
            table.insert(elements, e)
        end
    end
    return elements
end

local function capture_style_from_playhead()
    local timeline = get_current_timeline(); if not timeline then error("no current timeline") end
    local item = safe_call(function() return timeline:GetCurrentVideoItem() end)
    if not item then error("no video clip at playhead") end
    local tool = nil
    for _, comp in ipairs(get_comp_list(item)) do
        local tools = find_text_tools(comp)
        if #tools > 0 then tool = tools[1]; break end
    end
    if not tool then error("no Text+ tool found at playhead") end
    local params = capture_all_style_inputs(tool)
    local elements = capture_shading_elements(tool)
    if #elements > 0 then params.ShadingElements = elements end
    if params.Outline == nil and (params.Thickness1 ~= nil or params.Red2 ~= nil or params.Green2 ~= nil or params.Blue2 ~= nil) then params.Outline = 1 end
    if params.DropShadow == nil and (params.ShdwDistance ~= nil or params.ShdwSoftness ~= nil or params.ShdwAngle ~= nil or params.ShdwOpacity ~= nil) then params.DropShadow = 1 end
    local name = safe_call(function() return item:GetName() end) or ""
    return params, name
end

local function set_input_safe(tool, iid, value)
    if iid == "StyledText" or iid == "ShadingElements" then return false end
    local ok, result = pcall(function() return tool:SetInput(iid, value) end)
    if not ok then return false end
    return result ~= false
end

local function apply_shading_elements(tool, elements)
    if type(elements) ~= "table" then return false end
    local changed = false
    local captured = {}
    for _, e in ipairs(elements) do
        local i = tonumber(e.index)
        if i and i >= 1 and i <= 8 then captured[i] = true end
    end

    -- Make the destination's Shading stack match the captured style.  Do this
    -- once here instead of also replaying raw EnabledN/AlphaN/etc generically.
    for i=1,8 do
        if not captured[i] then set_input_safe(tool, "Enabled"..i, 0) end
    end

    -- Apply element properties first and enable the element last.  This avoids
    -- partially-painted intermediate states while Resolve is processing the
    -- sequence of SetInput calls.
    for _, e in ipairs(elements) do
        local i = tonumber(e.index)
        if i and i >= 1 and i <= 8 then
            local ordered = {
                {"Name","name"}, {"ElementShape","shape"},
                {"Red","red"}, {"Green","green"}, {"Blue","blue"}, {"Alpha","alpha"},
                {"Thickness","thickness"}, {"Opacity","opacity"},
                {"Softness","softness"}, {"SoftnessX","softness_x"},
                {"SoftnessY","softness_y"}, {"SoftnessGlow","softness_glow"},
                {"OutsideOnly","outside_only"}, {"PriorityBack","priority_back"},
                {"OverrideColor","override_color"},
            }
            for _, pair in ipairs(ordered) do
                local prefix, key = pair[1], pair[2]
                if e[key] ~= nil and set_input_safe(tool, prefix..i, e[key]) then changed = true end
            end
            if e.offset_x ~= nil or e.offset_y ~= nil then
                local pt = { tonumber(e.offset_x) or 0, tonumber(e.offset_y) or 0, 0 }
                if set_input_safe(tool, "Offset"..i, pt) then changed = true end
            end
            if set_input_safe(tool, "Enabled"..i, 1) then changed = true end
        end
    end
    return changed
end

local function apply_params_to_item(item, params)
    local changed, found = false, false
    for _, comp in ipairs(get_comp_list(item)) do
        for _, tool in ipairs(find_text_tools(comp)) do
            found = true

            -- Preserve the target clip's actual text.  Some Text+ inputs are coupled
            -- internally, so writing a broad set of style inputs can indirectly reset
            -- StyledText even though we never intentionally copy it.
            local original_text = safe_call(function() return tool:GetInput("StyledText") end)

            -- Extra safety guard: even if Resolve exposes an unexpected alias for
            -- a layout input, preserve the destination's most important spatial
            -- values and restore them after applying appearance settings.
            local preserve_ids = {"Center", "LayoutType", "LayoutRotation", "LayoutWidth", "LayoutHeight"}
            local preserved = {}
            for _, pid in ipairs(preserve_ids) do
                preserved[pid] = safe_call(function() return tool:GetInput(pid) end)
            end

            -- Apply the conservative typography subset first.  Shading is always
            -- applied LAST so no legacy Outline/DropShadow alias can mutate the
            -- freshly restored Shading stack afterwards.
            local generic_applied, generic_skipped = 0, 0
            for iid, value in pairs(params) do
                if iid ~= "ShadingElements" then
                    local safe_ok, safe_result = pcall(is_safe_generic_apply_id, iid)
                    if not safe_ok then
                        log_line("apply: safety predicate ERROR for " .. tostring(iid) .. ": " .. tostring(safe_result))
                        generic_skipped = generic_skipped + 1
                    elseif safe_result and not (params.ShadingElements and SHADING_LEGACY_ALIAS_IDS[iid]) then
                        if set_input_safe(tool, iid, value) then
                            changed = true
                            generic_applied = generic_applied + 1
                        else
                            log_line("apply: SetInput rejected " .. tostring(iid))
                        end
                    else
                        generic_skipped = generic_skipped + 1
                    end
                end
            end
            log_line(string.format("apply: generic safe applied=%d skipped=%d", generic_applied, generic_skipped))

            if params.ShadingElements then
                if apply_shading_elements(tool, params.ShadingElements) then changed = true end
            end

            -- Always restore destination text and placement after style application.
            if original_text ~= nil then
                local ok = pcall(function() tool:SetInput("StyledText", original_text) end)
                if not ok then log_line("apply: WARNING failed to restore StyledText") end
            end
            for _, pid in ipairs(preserve_ids) do
                if preserved[pid] ~= nil then
                    pcall(function() tool:SetInput(pid, preserved[pid]) end)
                end
            end
        end
    end
    return changed, found
end

local function get_clip_color(item)
    local v = safe_call(function() return item:GetClipColor() end)
    return tostring(v or "")
end

local function selected_track_index(track_combo)
    local s = tostring(track_combo.CurrentText or "")
    if s:upper() == "ALL" then return nil end
    local n = s:match("^[Vv](%d+)$")
    return n and tonumber(n) or nil
end

local function apply_style_to_selection(style, color_combo, track_combo, status)
    local params = style.textplus_params or {}
    local timeline = get_current_timeline(); if not timeline then status.Text="No current timeline"; return end
    local selected_color = tostring(color_combo.CurrentText or "")
    if selected_color == CURRENT_CLIP_OPTION then
        local item = safe_call(function() return timeline:GetCurrentVideoItem() end)
        if not item then status.Text="No clip at playhead"; return end
        local changed, found = apply_params_to_item(item, params)
        status.Text = found and (changed and "Applied to current clip" or "Text+ found, but no inputs changed") or "No Text+ tool found"
        return
    end

    local track_only = selected_track_index(track_combo)
    local track_count = tonumber(safe_call(function() return timeline:GetTrackCount("video") end) or 0) or 0
    local changed_count, matched = 0, 0
    for t = 1, track_count do
        if not track_only or track_only == t then
            local items = safe_call(function() return timeline:GetItemListInTrack("video", t) end) or {}
            for _, item in pairs(items) do
                local color_ok = (selected_color == "" or selected_color:lower() == "any" or get_clip_color(item):lower() == selected_color:lower())
                if color_ok then
                    matched = matched + 1
                    local changed = apply_params_to_item(item, params)
                    if changed then changed_count = changed_count + 1 end
                end
            end
        end
    end
    status.Text = string.format("Applied: %d clip(s) changed / %d matched", changed_count, matched)
end

-- ---------------------------------------------------------------------------
-- Fixed 10x10 style library
-- ---------------------------------------------------------------------------

local function normalize_styles(data)
    local incoming = type(data)=="table" and data.styles or nil
    if type(incoming) ~= "table" then incoming = {} end
    local styles = {}
    for i = 1, SLOT_COUNT do
        local s = type(incoming[i])=="table" and copy_table(incoming[i]) or {}
        s.style_id = string.format("fixed_slot_%02d", i)
        s.display_name = tostring(s.display_name or "")
        if type(s.textplus_params) ~= "table" then s.textplus_params = {} end
        styles[i] = s
    end
    return styles
end

local function save_styles(styles, path)
    path = path or STYLES_FILE
    local ok, err = write_json(path, {version=1, generator="TextPlus Style Gallery Lua "..VERSION, styles=styles})
    if not ok then error("failed to save styles: " .. tostring(err)) end
end

local function load_styles(path)
    local data = read_json(path or STYLES_FILE)
    return normalize_styles(data or {styles={}})
end

local function ensure_styles_file()
    if file_exists(STYLES_FILE) then return end
    local candidates = { path_join(USER_DATA_DIR, PYTHON_STYLES_NAME), path_join(script_dir(), PYTHON_STYLES_NAME), path_join(USER_DATA_DIR, LEGACY_STYLES_NAME), path_join(script_dir(), LEGACY_STYLES_NAME) }
    for _, p in ipairs(candidates) do
        if file_exists(p) then
            local data = read_json(p)
            if data then save_styles(normalize_styles(data), STYLES_FILE); log_line("migrated styles from " .. p); return end
        end
    end
    save_styles(normalize_styles({styles={}}), STYLES_FILE)
end

local function slot_empty(style)
    return type(style) ~= "table" or type(style.textplus_params) ~= "table" or next(style.textplus_params) == nil
end

-- ---------------------------------------------------------------------------
-- SVG thumbnail renderer (native Lua, no Pillow)
-- ---------------------------------------------------------------------------

local function is_shadow_element(e)
    local name = tostring(e.name or ""):lower()

    -- Text+ uses OutsideOnly for true outline/ring elements.  These must stay
    -- centered around the glyph even if the element also exposes softness or
    -- tiny non-zero offsets internally.
    if (tonumber(e.outside_only) or 0) > 0.5 then return false end

    -- Prefer semantic names when Resolve provides them.
    if name:find("outline", 1, true) or name:find("border", 1, true) then return false end
    if name:find("shadow", 1, true) or name:find("drop", 1, true) then return true end

    -- An actual shadow needs displacement.  Do NOT use softness alone here:
    -- outline elements can legally carry softness controls too.
    local ox = math.abs(tonumber(e.offset_x) or 0)
    local oy = math.abs(tonumber(e.offset_y) or 0)
    return ox > 0.001 or oy > 0.001
end

local function svg_text_element(x, y, text, family, size, fill, opacity, stroke, stroke_width, weight)
    local attrs = string.format('x="%.2f" y="%.2f" text-anchor="middle" dominant-baseline="middle" font-family="%s" font-size="%d" font-weight="%s" fill="%s" fill-opacity="%.3f"',
        x, y, xml_escape(family), size, xml_escape(weight), fill, opacity)
    if stroke and stroke_width and stroke_width > 0 then
        attrs = attrs .. string.format(' stroke="%s" stroke-width="%.2f" stroke-linejoin="round" stroke-linecap="round" paint-order="stroke fill"', stroke, stroke_width)
    end
    return '<text ' .. attrs .. '>' .. xml_escape(text) .. '</text>'
end

-- Match the Python/Pillow stable renderer more closely.  Text+ Thickness is
-- treated as a fraction of the preview font size.  SVG strokes are centred on
-- the glyph edge, so a small compensation factor keeps the visible outside ring
-- close to the Pillow/Text+ result without making thin outlines explode.
local function shading_thickness_to_visible_px(thickness, font_px)
    local t = math.max(0, tonumber(thickness) or 0)
    if t <= 0 then return 0 end
    -- Text+ Thickness behaves much closer to an OUTWARD ring thickness.
    -- This returns the desired visible outward width; the SVG stroke-width
    -- itself is doubled later because SVG strokes are centered on glyph edges.
    local px = t * font_px * 1.15
    return math.max(0.75, math.min(font_px * 0.42, px))
end

local function visible_px_to_svg_stroke(px, font_px)
    if not px or px <= 0 then return 0 end
    return math.max(1.5, math.min(font_px * 0.90, px * 2.0))
end

local function empty_thumb_path()
    return path_join(THUMB_DIR, "_empty_slot.svg")
end

local function ensure_empty_thumb_svg()
    local path = empty_thumb_path()
    if file_exists(path) then return path end
    local f = io.open(path, "wb")
    if not f then return nil end
    f:write(string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n', THUMB_W, THUMB_H, THUMB_W, THUMB_H))
    f:write('<rect width="100%" height="100%" rx="4" fill="#383838"/>\n')
    f:write(string.format('<text x="%d" y="%d" text-anchor="middle" dominant-baseline="middle" font-family="Arial" font-size="14" fill="#888888">(empty)</text>\n', THUMB_W/2, THUMB_H/2 + 1))
    f:write('</svg>\n')
    f:close()
    return path
end

local function render_thumbnail_svg(style, path)
    local p = style.textplus_params or {}
    local font = tostring(p.Font or "Arial")
    local font_style = tostring(p.Style or "Regular")
    local weight = font_style:lower():find("bold",1,true) and "700" or "400"
    local size_norm = tonumber(p.Size) or 0.08
    local font_px = math.max(27, math.min(64, math.floor(size_norm * 380 + 0.5)))
    local cx = THUMB_W / 2
    -- Resolve's Qt SVG renderer places mixed Latin/Japanese glyphs above
    -- the optical middle even with dominant-baseline="middle". Apply a
    -- font-size-aware optical correction for the thumbnail preview.
    local optical_y_offset = math.max(11.0, math.min(13.0, font_px * 0.32))
    local cy = THUMB_H / 2 + optical_y_offset
    local parts = {
        string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">', THUMB_W, THUMB_H, THUMB_W, THUMB_H),
        '<rect width="100%" height="100%" rx="4" fill="'..CARD_BG..'"/>'
    }
    local elements = p.ShadingElements
    if type(elements) == "table" and #elements > 0 then
        local fill_el, borders, shadows = nil, {}, {}

        -- Resolve's Shading stack is not reliably classifiable from
        -- ElementShape alone.  In particular, later enabled elements may still
        -- report ElementShape == 0 while behaving as an outline/ring.  Treat
        -- the FIRST enabled shape-0 element as the glyph fill; classify every
        -- later enabled element by its actual appearance controls.
        for _, e in ipairs(elements) do
            local shape = math.floor((tonumber(e.shape) or 0)+0.5)
            local thick = math.abs(tonumber(e.thickness) or 0)
            local outside = (tonumber(e.outside_only) or 0) > 0.5
            local name = tostring(e.name or ""):lower()
            local has_border_hint = outside or thick > 0.0005 or name:find("outline",1,true) or name:find("border",1,true)

            if not fill_el and shape == 0 and not is_shadow_element(e) then
                fill_el = e
            elseif is_shadow_element(e) then
                table.insert(shadows, e)
            elseif shape ~= 0 or has_border_hint then
                table.insert(borders, e)
            else
                -- Do not silently drop an enabled later shading element.  A
                -- zero-thickness element can still contribute a colored layer
                -- in Resolve, so keep it as a border-like layer for preview.
                table.insert(borders, e)
            end
        end

        -- Text+ commonly uses element 1 as fill, then element 2 as the inner
        -- outline and element 3 as the next outer outline.  Each OutsideOnly
        -- ring contributes additional width; it is not an absolute SVG stroke.
        -- Keep that semantic order here and build cumulative outward widths.
        table.sort(borders, function(a,b)
            return (tonumber(a.index) or 999) < (tonumber(b.index) or 999)
        end)

        local cumulative_visible = 0
        for border_pos, e in ipairs(borders) do
            local add = shading_thickness_to_visible_px(e.thickness, font_px)
            -- Even a very small enabled outline needs a visible contribution.
            if add <= 0 then add = 0.75 end

            -- Optical tuning against Resolve's viewer: the first/inner ring
            -- tends to disappear under the next SVG stroke, while outer rings
            -- look slightly too dominant.  Preserve the cumulative model but
            -- redistribute the visible widths a little.
            if border_pos == 1 then
                add = add * 1.20
            else
                add = add * 0.85
            end

            cumulative_visible = cumulative_visible + add
            e._preview_visible_outer_px = cumulative_visible
            e._preview_svg_stroke_px = visible_px_to_svg_stroke(cumulative_visible, font_px)
        end

        -- Diagnostic trace: useful when a Resolve version exposes unusual
        -- Shading defaults.  This also makes future preview mismatches easy to
        -- diagnose without changing the actual Apply behaviour.
        for _, e in ipairs(elements) do
            local shape = math.floor((tonumber(e.shape) or 0)+0.5)
            local kind = (shape == 0) and "fill" or (is_shadow_element(e) and "shadow" or "border")
            log_line(string.format(
                "thumbnail: shading idx=%s kind=%s name=%s shape=%s thick=%.4f outside=%s priority=%s offset=(%.4f,%.4f) rgb=(%.3f,%.3f,%.3f)",
                tostring(e.index or "?"), kind, tostring(e.name or ""), tostring(e.shape or ""),
                tonumber(e.thickness) or 0, tostring(e.outside_only or ""), tostring(e.priority_back or ""),
                tonumber(e.offset_x) or 0, tonumber(e.offset_y) or 0,
                tonumber(e.red) or 0, tonumber(e.green) or 0, tonumber(e.blue) or 0))
        end

        for _, e in ipairs(shadows) do
            local color = rgb_hex(e.red or 0, e.green or 0, e.blue or 0)
            local opacity = clamp01((tonumber(e.alpha) or 1) * (tonumber(e.opacity) or 1))
            local dx = (tonumber(e.offset_x) or 0) * font_px
            local dy = -(tonumber(e.offset_y) or 0) * font_px
            local sw = visible_px_to_svg_stroke(shading_thickness_to_visible_px(e.thickness, font_px), font_px)
            table.insert(parts, svg_text_element(cx+dx, cy+dy, PREVIEW_TEXT, font, font_px, color, opacity, sw>0 and color or nil, sw, weight))
        end
        -- Draw OUTER rings first, then inner rings, then the actual fill.
        -- Using cumulative stroke widths prevents equal-thickness Text+ rings
        -- from covering each other in the SVG preview.
        for n = #borders, 1, -1 do
            local e = borders[n]
            local color = rgb_hex(e.red or 0, e.green or 0, e.blue or 0)
            local opacity = clamp01((tonumber(e.alpha) or 1) * (tonumber(e.opacity) or 1))
            local sw = tonumber(e._preview_svg_stroke_px) or 0
            table.insert(parts, svg_text_element(cx, cy, PREVIEW_TEXT, font, font_px, color, opacity, color, sw, weight))
            log_line(string.format(
                "thumbnail: cumulative border idx=%s visible_outer=%.2f svg_stroke=%.2f",
                tostring(e.index or "?"), tonumber(e._preview_visible_outer_px) or 0, sw))
        end
        local f = fill_el or {}
        local fill = rgb_hex(f.red or p.Red1 or 1, f.green or p.Green1 or 1, f.blue or p.Blue1 or 1)
        local alpha = clamp01((tonumber(f.alpha) or tonumber(p.Alpha1) or 1) * (tonumber(f.opacity) or 1))
        table.insert(parts, svg_text_element(cx, cy, PREVIEW_TEXT, font, font_px, fill, alpha, nil, 0, weight))
    else
        local fill = rgb_hex(p.Red1 or 1, p.Green1 or 1, p.Blue1 or 1)
        local outline = tonumber(p.Outline) and tonumber(p.Outline) ~= 0
        local stroke = rgb_hex(p.Red2 or 0, p.Green2 or 0, p.Blue2 or 0)
        local sw = outline and visible_px_to_svg_stroke(shading_thickness_to_visible_px(tonumber(p.Thickness1) or 0.04, font_px), font_px) or 0
        if tonumber(p.DropShadow) and tonumber(p.DropShadow) ~= 0 then
            local dist = (tonumber(p.ShdwDistance) or 0.03) * THUMB_H
            local angle = math.rad(tonumber(p.ShdwAngle) or 315)
            local dx, dy = math.cos(angle)*dist, -math.sin(angle)*dist
            table.insert(parts, svg_text_element(cx+dx,cy+dy,PREVIEW_TEXT,font,font_px,"#000000",clamp01(p.ShdwOpacity or 0.4),nil,0,weight))
        end
        table.insert(parts, svg_text_element(cx,cy,PREVIEW_TEXT,font,font_px,fill,clamp01(p.Alpha1 or 1),sw>0 and stroke or nil,sw,weight))
    end
    table.insert(parts, "</svg>")
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(table.concat(parts, "\n")); f:close(); return true
end

local function thumb_path(style_id) return path_join(THUMB_DIR, tostring(style_id) .. ".svg") end

local function fallback_css(style)
    local p = style.textplus_params or {}
    local fill = rgb_hex(p.Red1 or 1, p.Green1 or 1, p.Blue1 or 1)
    local stroke = "#000000"
    local elements = p.ShadingElements
    if type(elements)=="table" then
        for _,e in ipairs(elements) do if tonumber(e.shape or 0) ~= 0 and not is_shadow_element(e) then stroke=rgb_hex(e.red or 0,e.green or 0,e.blue or 0); break end end
    elseif p.Red2 ~= nil then stroke=rgb_hex(p.Red2,p.Green2,p.Blue2) end
    return string.format("background-color:%s; color:%s; border:2px solid %s; border-radius:4px; font-weight:bold;", CARD_BG, fill, stroke)
end

local function set_thumb(ui, item, style)
    if slot_empty(style) then
        -- UIManager/Qt may keep the previous QIcon even after the backing SVG
        -- has been deleted.  Replace it with a real empty-slot icon instead of
        -- only changing Text/StyleSheet; this prevents the deleted thumbnail
        -- from remaining visible beside the "(empty)" state.
        local empty_path = ensure_empty_thumb_svg()
        if empty_path then
            local ok = pcall(function()
                item.Icon = ui:Icon{File=empty_path}
                item.IconSize = {THUMB_W-8, THUMB_H-8}
                item.Text = ""
                item.StyleSheet = "background-color:#383838; border-radius:4px;"
            end)
            if ok then return end
        end
        pcall(function() item.Icon = nil end)
        item.Text = "(empty)"
        item.StyleSheet = "background-color:#383838; color:#888888; border-radius:4px;"
        return
    end
    local path = thumb_path(style.style_id)
    if render_thumbnail_svg(style, path) then
        local ok = pcall(function()
            item.Icon = ui:Icon{File=path}
            item.IconSize = {THUMB_W-8, THUMB_H-8}
            item.Text = ""
            item.StyleSheet = "background-color:"..CARD_BG.."; border-radius:4px;"
        end)
        if ok then return end
    end
    pcall(function() item.Icon = nil end)
    item.Text = PREVIEW_TEXT
    item.StyleSheet = fallback_css(style)
end

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------

local function resolve_file_path(name)
    name = tostring(name or "")
    if name == "" then name = FIXED_STYLES_NAME end
    if not name:match("^%a:[/\\]") and name:sub(1,1) ~= "/" and name:sub(1,2) ~= "\\\\" then name = path_join(USER_DATA_DIR, name) end
    return name
end

local function run_gallery()
    ensure_styles_file()
    local fu = get_fusion(); if not fu then error("Fusion handle unavailable") end
    local ui = fu.UIManager
    local disp = bmd.UIDispatcher(ui)
    local geometry = {100,100,770,790}
    local current_page = 0

    -- Build the window only once so Prev/Next can update the existing rows
    -- without hiding the gallery or unnecessarily reloading thumbnail icons.
    local rows = {}
    rows[#rows+1] = ui:Label{ID="title", Text="Text+ Style Gallery (Lua Universal 10x10)  v"..VERSION, Weight=0}
    rows[#rows+1] = ui:HGroup{Weight=0, Spacing=6,
        ui:Label{Text="Clip Color Filter:",Weight=0}, ui:ComboBox{ID="clipColor",Weight=0,MinimumSize={180,0}},
        ui:Label{Text="",Weight=0,MinimumSize={18,0},MaximumSize={18,16777215}},
        ui:Label{Text="Video Track:",Weight=0}, ui:ComboBox{ID="trackSelect",Weight=0,MinimumSize={90,0}}
    }
    rows[#rows+1] = ui:Label{Text="Click thumbnail to Apply. Capture reads style from Text+ at playhead. StyledText is preserved.",Weight=0}
    rows[#rows+1] = ui:HGroup{Weight=0,Spacing=6,
        ui:Button{ID="exportBtn",Text="Export",Weight=0,MinimumSize={72,0}},
        ui:Button{ID="importBtn",Text="Import",Weight=0,MinimumSize={72,0}},
        ui:LineEdit{ID="fileName",Text=FIXED_STYLES_NAME,Weight=1,MinimumSize={180,0},MaximumSize={420,16777215}},
        ui:Button{ID="browseBtn",Text="Browse...",Weight=0,MinimumSize={78,0}}
    }
    rows[#rows+1] = ui:HGroup{Weight=0,Spacing=6,
        ui:Button{ID="prevPageBtn",Text="< Prev",Weight=0,MinimumSize={72,0}},
        ui:Button{ID="nextPageBtn",Text="Next >",Weight=0,MinimumSize={72,0}},
        ui:Label{ID="pageLabel",Text="Page 1 / "..PAGE_COUNT,Weight=0,MinimumSize={90,0},Alignment={AlignHCenter=true}},
        ui:Label{Text="",Weight=1}
    }
    for ri=1,PAGE_SIZE do
        rows[#rows+1] = ui:HGroup{Weight=0,Spacing=6,
            ui:Label{ID="seq_"..ri,Text=tostring(ri),Weight=0,MinimumSize={20,0}},
            ui:Button{ID="thumb_"..ri,Text="(empty)",Weight=0,MinimumSize={THUMB_W,THUMB_H},MaximumSize={THUMB_W,THUMB_H}},
            ui:LineEdit{ID="name_"..ri,Text="",Weight=1,MinimumSize={160,0},MaximumSize={280,16777215}},
            ui:Button{ID="capture_"..ri,Text="Capture",Weight=0,MinimumSize={70,0}},
            ui:Button{ID="delete_"..ri,Text="Delete",Weight=0,MinimumSize={70,0}}
        }
    end
    rows[#rows+1] = ui:Label{ID="status",Text="Ready",Weight=0}
    rows[#rows+1] = ui:HGroup{Weight=0,Spacing=0,ui:Label{Text="",Weight=1},ui:Button{ID="closeBtn",Text="Close",Weight=0,MinimumSize={140,30},MaximumSize={140,34}},ui:Label{Text="",Weight=1}}

    local win = disp:AddWindow({ID="TextPlusStyleGalleryLua",WindowTitle="Text+ Style Gallery (Lua 10x10)",Geometry=geometry}, ui:VGroup{ID="root",Spacing=3,Margin=8,unpack(rows)})
    local items=win:GetItems(); local status=items.status; local cc=items.clipColor; local tc=items.trackSelect
    for _,c in ipairs(COLOR_OPTIONS) do cc:AddItem(c) end; cc.CurrentIndex=0
    tc:AddItem("All")
    local tl=get_current_timeline(); local track_count=tl and tonumber(safe_call(function() return tl:GetTrackCount("video") end) or 0) or 0
    for t=1,track_count do tc:AddItem("V"..t) end; tc.CurrentIndex=0

    -- Prevent TextChanged handlers from writing names back while a page is
    -- being populated programmatically.
    local updating_page = false

    local function set_thumb_fast(item, style, force_render)
        if slot_empty(style) then
            return set_thumb(ui, item, style)
        end
        local path = thumb_path(style.style_id)
        if (not force_render) and file_exists(path) then
            local ok = pcall(function()
                item.Icon = ui:Icon{File=path}
                item.IconSize = {THUMB_W-8, THUMB_H-8}
                item.Text = ""
                item.StyleSheet = "background-color:"..CARD_BG.."; border-radius:4px;"
            end)
            if ok then return end
        end
        set_thumb(ui, item, style)
    end

    local function update_page(new_page, force_render)
        current_page = math.max(0, math.min(PAGE_COUNT-1, tonumber(new_page) or current_page))
        local styles = load_styles(STYLES_FILE)
        updating_page = true
        items.pageLabel.Text = string.format("Page %d / %d", current_page+1, PAGE_COUNT)
        for ri=1,PAGE_SIZE do
            local index=current_page*PAGE_SIZE+ri
            local s=styles[index]
            items["seq_"..ri].Text=tostring(index)
            items["name_"..ri].Text=tostring((s and s.display_name) or "")
            set_thumb_fast(items["thumb_"..ri], s or {style_id="fixed_slot_"..index,textplus_params={}}, force_render)
        end
        updating_page = false
        status.Text = string.format("Page %d / %d", current_page+1, PAGE_COUNT)
    end

    win.On.TextPlusStyleGalleryLua.Close=function() disp:ExitLoop() end
    win.On.closeBtn.Clicked=function() disp:ExitLoop() end
    win.On.prevPageBtn.Clicked=function() update_page(current_page-1, false) end
    win.On.nextPageBtn.Clicked=function() update_page(current_page+1, false) end
    win.On.browseBtn.Clicked=function()
        local selected=safe_call(function() return fu:RequestFile(STYLES_FILE) end)
        if selected then items.fileName.Text=tostring(selected); status.Text="Selected: "..tostring(selected) end
    end
    win.On.exportBtn.Clicked=function()
        local target=resolve_file_path(items.fileName.Text)
        local ok,err=pcall(function() save_styles(load_styles(STYLES_FILE),target) end)
        status.Text=ok and ("Exported: "..target) or ("Export failed: "..tostring(err))
    end
    win.On.importBtn.Clicked=function()
        local source=resolve_file_path(items.fileName.Text)
        local data=read_json(source)
        if not data then status.Text="Import failed: file unreadable" else
            local ok,err=pcall(function() save_styles(normalize_styles(data),STYLES_FILE) end)
            if ok then status.Text="Imported: "..source; update_page(current_page, true) else status.Text="Import failed: "..tostring(err) end
        end
    end

    -- Event handlers are attached once.  The target slot is resolved from the
    -- current page at click time, so no window rebuild is needed when paging.
    for ri=1,PAGE_SIZE do
        win.On["thumb_"..ri].Clicked=function()
            local index=current_page*PAGE_SIZE+ri
            local current=load_styles(STYLES_FILE); local s=current[index]
            if slot_empty(s) then status.Text="Empty slot" else apply_style_to_selection(s,cc,tc,status) end
        end
        win.On["capture_"..ri].Clicked=function()
            local index=current_page*PAGE_SIZE+ri
            local ok,params,clip_name=pcall(capture_style_from_playhead)
            if not ok then status.Text="Capture failed: "..tostring(params); return end
            local current=load_styles(STYLES_FILE); local target=current[index]; target.textplus_params=params
            if target.display_name=="" then target.display_name="NewStyle"..index end
            local saved,err=pcall(function() save_styles(current,STYLES_FILE) end)
            if not saved then status.Text="Capture save failed: "..tostring(err); return end
            updating_page = true
            items["name_"..ri].Text=target.display_name
            updating_page = false
            set_thumb_fast(items["thumb_"..ri],target,true)
            status.Text="Captured: "..target.display_name..(clip_name~="" and (" from "..clip_name) or "")
            log_line("capture: updated slot in-place "..tostring(target.style_id))
        end
        win.On["delete_"..ri].Clicked=function()
            local index=current_page*PAGE_SIZE+ri
            local current=load_styles(STYLES_FILE)
            current[index].display_name=""
            current[index].description=""
            current[index].textplus_params={}
            save_styles(current,STYLES_FILE)
            pcall(function() os.remove(thumb_path(current[index].style_id)) end)
            updating_page = true
            items["name_"..ri].Text=""
            updating_page = false
            set_thumb_fast(items["thumb_"..ri],current[index],true)
            status.Text="Deleted slot "..index
        end
        win.On["name_"..ri].TextChanged=function()
            if updating_page then return end
            local index=current_page*PAGE_SIZE+ri
            local current=load_styles(STYLES_FILE)
            current[index].display_name=tostring(items["name_"..ri].Text or "")
            save_styles(current,STYLES_FILE)
        end
    end

    update_page(0, false)
    win:Show()
    disp:RunLoop()
    win:Hide()
end

log_line("START TextPlus Style Gallery Lua v"..VERSION.." user_data_dir="..USER_DATA_DIR)
local ok,err=pcall(run_gallery)
if not ok then
    log_line("FATAL: "..tostring(err))
    print("TextPlus Style Gallery Lua error: "..tostring(err))
end
