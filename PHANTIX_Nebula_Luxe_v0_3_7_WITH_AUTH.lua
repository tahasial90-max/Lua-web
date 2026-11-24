--[[
    PHANTIX Nebula Luxe v0.3.7 — Cloudflare AI Integration
    This is a v0.3.7 launcher/extension:
      1) Loads the unchanged, known-good v0.3.6 GUI from the pinned GitHub raw URL.
      2) Adds an AI Riddle toggle to the existing Settings tab.
      3) Sends manual riddles and matching Global Messages to the Cloudflare Worker.
      4) Places a validated answer in the existing LAST CODE field.
    No automatic redeem/submit behavior is added.

    IMPORTANT:
      - Keep the v0.3.6 file as your rollback copy.
      - Paste the SAME value you saved as Cloudflare secret AUTH_TOKEN below.
      - Do not publish this file with your token in it. A token in client-side Lua
        can be extracted by anyone who gets the script.
]]

local BASE_SCRIPT_URL =
    "https://raw.githubusercontent.com/tahasial90-max/Dex2/main/PHANTIX_Nebula_Luxe_v0_3_6.lua"

local WORKER_URL = "https://broad-term-eb1f.taahasial90.workers.dev"
local WORKER_AUTH_TOKEN = "df069dd8f303e4e02b15e8b7677e004377b8043903625428"

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if not player then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    player = Players.LocalPlayer
end
local playerGui = player:WaitForChild("PlayerGui")

local env = (typeof(getgenv) == "function" and getgenv()) or _G
if type(env.PHANTIX_Stop) == "function" then
    pcall(env.PHANTIX_Stop)
end

local function getRequestFunction()
    return (syn and syn.request)
        or (http and http.request)
        or http_request
        or request
end

-- Load the exact v0.3.6 baseline first; its GUI and existing behavior stay unchanged.
local loader = loadstring
if type(loader) ~= "function" then
    warn("[PHANTIX 0.3.7] loadstring is not available in this executor.")
    return
end

local source
local fetchOk, fetchResult = pcall(function()
    if type(game.HttpGet) == "function" then
        return game:HttpGet(BASE_SCRIPT_URL)
    end
    local requestFunction = getRequestFunction()
    if type(requestFunction) ~= "function" then
        error("No HTTP function is available to download the PHANTIX base.")
    end
    local response = requestFunction({
        Url = BASE_SCRIPT_URL,
        Method = "GET",
    })
    local status = tonumber(response and (response.StatusCode or response.Status))
    if status ~= 200 then
        error("GitHub download returned HTTP " .. tostring(status))
    end
    return response.Body
end)

if not fetchOk or type(fetchResult) ~= "string" or fetchResult == "" then
    warn("[PHANTIX 0.3.7] Could not download v0.3.6: " .. tostring(fetchResult))
    return
end
source = fetchResult

local compileOk, baseChunk = pcall(loader, source)
if not compileOk or type(baseChunk) ~= "function" then
    warn("[PHANTIX 0.3.7] Could not compile the v0.3.6 base: " .. tostring(baseChunk))
    return
end

local runOk, runError = pcall(baseChunk)
if not runOk then
    warn("[PHANTIX 0.3.7] v0.3.6 startup failed: " .. tostring(runError))
    return
end

-- Wait for the base UI to finish creating its named controls.
local gui = playerGui:WaitForChild("PHANTIX_Nebula_Luxe", 15)
if not gui then
    warn("[PHANTIX 0.3.7] Base GUI did not appear within 15 seconds.")
    return
end

local function findNamed(name)
    return gui:FindFirstChild(name, true)
end

local lastOutput = findNamed("LastOutput")
local riddleInput = findNamed("RiddleInput")
local solveButton = findNamed("SolveBtn")
local settingsContent = findNamed("Settings")
local statusRow = findNamed("StatusRow")
local consoleOutput = findNamed("Output")
local bottomBar = findNamed("BottomBar")
local versionLabel
if bottomBar then
    for _, child in ipairs(bottomBar:GetChildren()) do
        if child:IsA("TextLabel") and child.Text == "0.3.6" then
            versionLabel = child
            break
        end
    end
end

local function findStatValue(titleText)
    if not statusRow then return nil end
    for _, card in ipairs(statusRow:GetChildren()) do
        if card:IsA("Frame") then
            local titleLabel
            local valueLabel
            for _, child in ipairs(card:GetChildren()) do
                if child:IsA("TextLabel") then
                    if child.Text == titleText then
                        titleLabel = child
                    elseif not valueLabel then
                        valueLabel = child
                    end
                end
            end
            if titleLabel then
                for _, child in ipairs(card:GetChildren()) do
                    if child:IsA("TextLabel") and child ~= titleLabel then
                        valueLabel = child
                        break
                    end
                end
                return valueLabel
            end
        end
    end
    return nil
end
local askedValue = findStatValue("ASKED")
local solvedValue = findStatValue("SOLVED")

if not lastOutput or not riddleInput or not solveButton or not settingsContent then
    warn("[PHANTIX 0.3.7] Required v0.3.6 UI controls were not found. Base GUI remains usable.")
    return
end

if versionLabel and versionLabel:IsA("TextLabel") then
    versionLabel.Text = "0.3.7"
end
if consoleOutput and consoleOutput:IsA("TextLabel") then
    consoleOutput.Text = consoleOutput.Text:gsub(
        "UI demo only — no service connected%.",
        "AI Worker available — enable AI Riddle Listener in Settings."
    )
end

local function log(message, color)
    local output = findNamed("Output")
    if output and output:IsA("TextLabel") then
        local old = output.Text
        local rgb = color or Color3.fromRGB(180, 190, 220)
        local tag = string.format(
            "rgb(%d,%d,%d)",
            math.floor(rgb.R * 255),
            math.floor(rgb.G * 255),
            math.floor(rgb.B * 255)
        )
        local safe = tostring(message):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        local line = '<font color="' .. tag .. '">' .. safe .. "</font>"
        output.Text = old == "" and line or (old .. "\n" .. line)
    end
end

local C = {
    emerald = Color3.fromRGB(0, 225, 158),
    purple = Color3.fromRGB(168, 85, 247),
    purpleLight = Color3.fromRGB(202, 145, 255),
    dim = Color3.fromRGB(180, 190, 220),
    red = Color3.fromRGB(255, 78, 105),
    warn = Color3.fromRGB(255, 211, 105),
    bg = Color3.fromRGB(22, 9, 53),
    card = Color3.fromRGB(34, 29, 82),
    text = Color3.fromRGB(249, 247, 255),
}

local aiEnabled = false
local listenerConnection = nil
local generation = 0
local pending = {}
local recentAnnouncements = {}
local lastRequestAt = 0
local askedCount = 0
local solvedCount = 0
local COOLDOWN = 2.5

local function updateCounters()
    if askedValue and askedValue:IsA("TextLabel") then
        askedValue.Text = tostring(askedCount)
    end
    if solvedValue and solvedValue:IsA("TextLabel") then
        solvedValue.Text = tostring(solvedCount)
    end
end

local function cleanText(value)
    local text = tostring(value or "")
    text = text:gsub("<[^>]->", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function validAnswer(answer)
    if type(answer) ~= "string" then
        return false
    end
    answer = answer:upper()
    return #answer >= 2 and #answer <= 80 and answer:match("^[A-Z0-9]+$") ~= nil
end

local function submitRiddle(rawQuestion, sourceName)
    if not aiEnabled then
        log("AI is OFF. Enable AI Riddle Listener in Settings.", C.warn)
        return
    end

    local question = cleanText(rawQuestion)
    if question == "" then
        log("No riddle text was received.", C.warn)
        return
    end
    if #question > 500 then
        log("Riddle is too long (maximum 500 characters).", C.warn)
        return
    end
    if WORKER_AUTH_TOKEN == "" or WORKER_AUTH_TOKEN == "PUT_THE_SAME_AUTH_TOKEN_HERE" then
        log("Setup incomplete: paste the Cloudflare AUTH_TOKEN into this file first.", C.red)
        return
    end

    local requestKey = question:lower()
    if pending[requestKey] then
        log("Duplicate request ignored (already processing).", C.dim)
        return
    end

    local now = os.clock()
    if now - lastRequestAt < COOLDOWN then
        log("AI cooldown active. Please wait a moment.", C.warn)
        return
    end

    local requestFunction = getRequestFunction()
    if type(requestFunction) ~= "function" then
        log("This executor has no HTTP request function.", C.red)
        return
    end

    lastRequestAt = now
    pending[requestKey] = true
    askedCount += 1
    updateCounters()
    log("Sending " .. tostring(sourceName or "manual") .. " riddle: " .. question:sub(1, 72), C.purpleLight)

    task.spawn(function()
        local ok, response = pcall(function()
            return requestFunction({
                Url = WORKER_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["X-Auth-Token"] = WORKER_AUTH_TOKEN,
                },
                Body = HttpService:JSONEncode({ question = question }),
            })
        end)

        pending[requestKey] = nil

        if not ok or type(response) ~= "table" then
            log("Worker request failed: " .. tostring(response), C.red)
            return
        end

        local status = tonumber(response.StatusCode or response.Status)
        if status ~= 200 then
            if status == 401 or status == 403 then
                log("Authorization failed. Lua token must exactly match Cloudflare AUTH_TOKEN.", C.red)
            elseif status == 429 then
                log("Worker rate limit reached. Wait before trying again.", C.warn)
            else
                log("Worker returned HTTP " .. tostring(status or "unknown") .. ".", C.red)
            end
            return
        end

        local decodeOk, data = pcall(function()
            return HttpService:JSONDecode(tostring(response.Body or ""))
        end)
        if not decodeOk or type(data) ~= "table" then
            log("Worker response was not valid JSON.", C.red)
            return
        end

        if data.ok ~= true or not validAnswer(data.answer) then
            log("No validated answer returned (" .. tostring(data.reason or data.error or "no_answer") .. ").", C.warn)
            return
        end

        local answer = data.answer:upper()
        lastOutput.Text = answer
        solvedCount += 1
        updateCounters()
        log("Answer ready: " .. answer .. " — review it yourself; nothing is auto-submitted.", C.emerald)
    end)
end

local function isRiddleAnnouncement(text)
    if #text < 8 or #text > 500 then
        return false
    end
    local lower = text:lower()
    if lower:find("?", 1, true) then
        return true
    end
    local cues = {
        "sammy", "riddle", "brainrot", "animal", "my name",
        "favorite", "favourite", "who ", "what ", "which ",
        "where ", "when ", "how ", "code",
    }
    for _, cue in ipairs(cues) do
        if lower:find(cue, 1, true) then
            return true
        end
    end
    return false
end

local function extractMessage(...)
    local best = ""
    for _, value in ipairs({ ... }) do
        if type(value) == "string" and #value > #best then
            best = value
        elseif type(value) == "table" then
            for _, key in ipairs({ "Text", "text", "Message", "message", "Title", "title", "Body", "body" }) do
                local candidate = value[key]
                if type(candidate) == "string" and #candidate > #best then
                    best = candidate
                end
            end
        end
    end
    return cleanText(best)
end

local function onGlobalAnnouncement(...)
    if not aiEnabled then
        return
    end
    local message = extractMessage(...)
    if not isRiddleAnnouncement(message) then
        return
    end

    local key = message:lower()
    if recentAnnouncements[key] then
        return
    end
    recentAnnouncements[key] = true
    task.delay(20, function()
        recentAnnouncements[key] = nil
    end)

    -- Pass the entire announcement, including spaces, to the AI.
    submitRiddle(message, "Global Message")
end

local function resolveNotifyRemote()
    local shared = env.PhiNotifyRemote or _G.PhiNotifyRemote
    if shared then
        local ok, isRemote = pcall(function()
            return shared:IsA("RemoteEvent")
        end)
        if ok and isRemote then
            return shared
        end
    end

    local packages = ReplicatedStorage:WaitForChild("Packages", 6)
    local net = packages and packages:WaitForChild("Net", 6)
    if not net then
        return nil
    end

    local getConnections = getconnections or (debug and debug.getconnections)
    if type(getConnections) ~= "function" then
        return nil
    end

    for _, remote in ipairs(net:GetDescendants()) do
        if remote:IsA("RemoteEvent") then
            local okConnections, eventConnections = pcall(getConnections, remote.OnClientEvent)
            if okConnections and type(eventConnections) == "table" then
                for _, connection in ipairs(eventConnections) do
                    local okFunction, callback = pcall(function()
                        return connection.Function
                    end)
                    if okFunction and type(callback) == "function" then
                        local sourceName = ""
                        pcall(function()
                            if debug and type(debug.getinfo) == "function" then
                                local info = debug.getinfo(callback)
                                sourceName = info and (info.short_src or info.source) or ""
                            elseif debug and type(debug.info) == "function" then
                                sourceName = debug.info(callback, "s") or ""
                            end
                        end)
                        if tostring(sourceName):find("NotificationController", 1, true) then
                            return remote
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function setAiEnabled(enabled)
    aiEnabled = enabled == true
    generation += 1

    if not aiEnabled then
        if listenerConnection then
            pcall(function()
                listenerConnection:Disconnect()
            end)
            listenerConnection = nil
        end
        log("AI Riddle Listener OFF. No new requests will be sent.", C.dim)
        return
    end

    if WORKER_AUTH_TOKEN == "" or WORKER_AUTH_TOKEN == "PUT_THE_SAME_AUTH_TOKEN_HERE" then
        log("Paste the Cloudflare AUTH_TOKEN into WORKER_AUTH_TOKEN before enabling AI.", C.red)
        aiEnabled = false
        return
    end

    log("AI Riddle Listener ON. Searching for the Global Message receiver...", C.emerald)
    if listenerConnection then
        return
    end

    local thisGeneration = generation
    task.spawn(function()
        local remote = resolveNotifyRemote()
        if not aiEnabled or generation ~= thisGeneration then
            return
        end
        if not remote then
            log("Global Message receiver not found. Manual Riddle Input can still be used.", C.warn)
            return
        end

        local ok, connection = pcall(function()
            return remote.OnClientEvent:Connect(function(...)
                pcall(onGlobalAnnouncement, ...)
            end)
        end)
        if not ok or not connection then
            log("Could not connect to the Global Message receiver.", C.red)
            return
        end
        listenerConnection = connection
        log("Global Message listener connected.", C.emerald)
    end)
end

-- Add one matching toggle row to the existing Settings tab (no second GUI).
local settingRow = Instance.new("Frame")
settingRow.Name = "AiRiddleSetting"
settingRow.Size = UDim2.new(1, 0, 0, 44)
settingRow.BackgroundColor3 = C.card
settingRow.BackgroundTransparency = 0.35
settingRow.BorderSizePixel = 0
settingRow.LayoutOrder = 4
settingRow.ZIndex = 6
settingRow.Parent = settingsContent

local rowCorner = Instance.new("UICorner")
rowCorner.CornerRadius = UDim.new(0, 10)
rowCorner.Parent = settingRow

local rowStroke = Instance.new("UIStroke")
rowStroke.Color = C.purpleLight
rowStroke.Thickness = 1
rowStroke.Transparency = 0.4
rowStroke.Parent = settingRow

local settingTitle = Instance.new("TextLabel")
settingTitle.Name = "AiRiddleTitle"
settingTitle.BackgroundTransparency = 1
settingTitle.Size = UDim2.new(1, -70, 1, 0)
settingTitle.Position = UDim2.fromOffset(14, 0)
settingTitle.Text = "AI Riddle Listener"
settingTitle.TextSize = 13
settingTitle.TextColor3 = C.text
settingTitle.Font = Enum.Font.GothamSemibold
settingTitle.TextXAlignment = Enum.TextXAlignment.Left
settingTitle.ZIndex = 7
settingTitle.Parent = settingRow

local toggle = Instance.new("TextButton")
toggle.Name = "AiRiddleToggle"
toggle.Size = UDim2.fromOffset(44, 24)
toggle.Position = UDim2.new(1, -54, 0.5, -12)
toggle.BackgroundColor3 = C.bg
toggle.BorderSizePixel = 0
toggle.AutoButtonColor = false
toggle.Text = "OFF"
toggle.TextSize = 12
toggle.TextColor3 = C.dim
toggle.Font = Enum.Font.GothamBlack
toggle.ZIndex = 7
toggle.Parent = settingRow

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 12)
toggleCorner.Parent = toggle

toggle.Activated:Connect(function()
    local nextState = not aiEnabled
    if nextState and (WORKER_AUTH_TOKEN == "" or WORKER_AUTH_TOKEN == "PUT_THE_SAME_AUTH_TOKEN_HERE") then
        log("Setup incomplete: add the AUTH_TOKEN to this Lua file first.", C.red)
        return
    end

    toggle.Text = nextState and "ON" or "OFF"
    toggle.BackgroundColor3 = nextState and C.emerald or C.bg
    toggle.TextColor3 = nextState and Color3.fromRGB(10, 10, 15) or C.dim
    setAiEnabled(nextState)
end)

-- Existing demo handler is connected first; this handler replaces its demo output.
solveButton.Activated:Connect(function()
    local query = riddleInput.Text
    if not aiEnabled then
        lastOutput.Text = ""
        log("AI is OFF. Turn on AI Riddle Listener in Settings to solve manually.", C.warn)
        return
    end
    submitRiddle(query, "manual input")
end)

-- Cleanup the extension listener whenever the original GUI is destroyed or stopped.
local function cleanupAi()
    aiEnabled = false
    generation += 1
    if listenerConnection then
        pcall(function()
            listenerConnection:Disconnect()
        end)
        listenerConnection = nil
    end
end

pcall(function()
    gui.Destroying:Connect(cleanupAi)
end)

local previousStop = env.PHANTIX_Stop
env.PHANTIX_Stop = function(...)
    cleanupAi()
    if type(previousStop) == "function" then
        return previousStop(...)
    end
end

log("PHANTIX 0.3.7 AI extension loaded. AI is OFF by default.", C.purpleLight)
log("Paste AUTH_TOKEN, then enable AI Riddle Listener in Settings.", C.warn)
print("[PHANTIX] 0.3.7 Nebula Luxe + Cloudflare AI extension loaded.")
