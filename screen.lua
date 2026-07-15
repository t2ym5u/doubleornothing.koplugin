local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local ButtonTable    = require("ui/widget/buttontable")
local DataStorage    = require("datastorage")
local Device         = require("device")
local Font           = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local InfoMessage    = require("ui/widget/infomessage")
local Size           = require("ui/size")
local TextBoxWidget  = require("ui/widget/textboxwidget")
local TextWidget     = require("ui/widget/textwidget")
local UIManager      = require("ui/uimanager")
local VerticalGroup  = require("ui/widget/verticalgroup")
local VerticalSpan   = require("ui/widget/verticalspan")
local _              = require("i18n")

local MenuHelper = require("menu_helper")
local ScreenBase  = require("screen_base")

local DeviceScreen = Device.screen

local DEFAULT_DURATION = 0    -- seconds to think before reveal (0 = no timer)
local DEFAULT_NB_TEAMS = 2
local BASE_POT         = 1    -- pot value after the first correct answer of a turn

local GAME_RULES_EN = _([[
Double or Nothing Party — Rules

Teams take turns. On your turn, a question is shown — confer with your team, then tap "Reveal" to see the answer.

• ✗ Wrong = you lose everything you were sitting on this turn. Turn ends, pot resets to 0.
• ✓ Correct = the pot is won (1 point first time, then doubled each time you keep going). Choose:
    🏦 Bank it — add the pot to your score, turn ends.
    ⚡ Double or Nothing — draw a new (harder) question and risk the pot to double it.

Teams swap after every turn (banked or busted).
]])

local GAME_RULES_FR = [[
Double or Nothing Party — Règles

Les équipes jouent à tour de rôle. À votre tour, une question s'affiche — concertez-vous, puis appuyez sur « Révéler » pour voir la réponse.

• ✗ Faux = vous perdez tout ce que vous aviez en jeu ce tour-ci. Le tour s'arrête, la cagnotte repart à 0.
• ✓ Juste = la cagnotte est gagnée (1 point la première fois, puis doublée à chaque fois que vous continuez). Choisissez :
    🏦 Encaisser — la cagnotte s'ajoute à votre score, le tour s'arrête.
    ⚡ Quitte ou double — une nouvelle question (plus dure) arrive, vous risquez la cagnotte pour la doubler.

Les équipes échangent leur tour après chaque manche (encaissée ou perdue).
]]

local function jsonDecode(s)
    local ok, json = pcall(require, "json")
    if ok then
        local ok2, result = pcall(json.decode, s)
        if ok2 then return result end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- DoubleOrNothingScreen
-- ---------------------------------------------------------------------------

local DoubleOrNothingScreen = ScreenBase:extend{}

function DoubleOrNothingScreen:init()
    self.lang     = self.plugin:getSetting("lang", "fr")
    self.duration = self.plugin:getSetting("duration", DEFAULT_DURATION)
    local nb      = self.plugin:getSetting("nb_teams", DEFAULT_NB_TEAMS)

    self.teams = {}
    for i = 1, nb do
        local default = self.lang == "fr" and ("Équipe " .. i) or ("Team " .. i)
        self.teams[i] = { name = self.plugin:getSetting("team_name_" .. i, default), score = 0 }
    end
    self.current_team = 1

    self.questions       = {}
    self.q_index         = 1
    self.phase            = "idle"  -- "idle" | "question" | "reveal" | "choice"
    self.pot              = 0
    self.time_remaining  = self.duration

    self:_loadQuestions()
    ScreenBase.init(self)
end

-- ---------------------------------------------------------------------------
-- Question loading (JSON, bundled example deck as fallback)
-- ---------------------------------------------------------------------------

function DoubleOrNothingScreen:_loadQuestions()
    local docs = DataStorage:getDataDir()
    local json_paths = {
        docs .. "/doubleornothing_questions_" .. self.lang .. ".json",
        docs .. "/doubleornothing_questions.json",
        _dir .. "doubleornothing_questions_" .. self.lang .. ".json",
        _dir .. "doubleornothing_questions_en.json",
    }

    for _, path in ipairs(json_paths) do
        local f = io.open(path, "r")
        if f then
            local content = f:read("*all")
            f:close()
            local data = jsonDecode(content)
            if type(data) == "table" and #data > 0 then
                self.questions = data
                self:_shuffleQuestions()
                return
            end
        end
    end

    self.questions = {}
end

function DoubleOrNothingScreen:_shuffleQuestions()
    local q = self.questions
    for i = #q, 2, -1 do
        local j = math.random(i)
        q[i], q[j] = q[j], q[i]
    end
    self.q_index = 1
end

function DoubleOrNothingScreen:_currentQuestion()
    if #self.questions == 0 then return nil end
    if self.q_index > #self.questions then self:_shuffleQuestions() end
    return self.questions[self.q_index]
end

-- ---------------------------------------------------------------------------
-- Timer (optional reflection countdown during "question" phase)
-- ---------------------------------------------------------------------------

function DoubleOrNothingScreen:_startCountdown()
    if self.duration <= 0 then return end
    self._tick_gen = (self._tick_gen or 0) + 1
    local gen = self._tick_gen
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

function DoubleOrNothingScreen:_stopCountdown()
    self._tick_gen = (self._tick_gen or 0) + 1
end

function DoubleOrNothingScreen:_onTick(gen)
    if gen ~= self._tick_gen then return end
    self.time_remaining = math.max(0, self.time_remaining - 1)
    if self.timer_widget then
        self.timer_widget:setText(self:_timerText())
        UIManager:setDirty(self, function() return "fast", self.dimen end)
    end
    if self.time_remaining <= 0 then
        self:onReveal()
    else
        UIManager:scheduleIn(1, function() self:_onTick(gen) end)
    end
end

function DoubleOrNothingScreen:_timerText()
    if self.duration <= 0 then return "" end
    local m = math.floor(self.time_remaining / 60)
    local s = self.time_remaining % 60
    return string.format("%d:%02d", m, s)
end

-- ---------------------------------------------------------------------------
-- Game actions
-- ---------------------------------------------------------------------------

function DoubleOrNothingScreen:onStartTurn()
    if #self.questions == 0 then
        local is_fr = self.lang == "fr"
        UIManager:show(InfoMessage:new{
            text = is_fr
                and "Aucune question chargée.\n\nCopiez doubleornothing_questions_fr.json\ndans le dossier documents de KOReader."
                or  "No questions loaded.\n\nCopy doubleornothing_questions_en.json\nto KOReader's documents folder.",
            timeout = 6,
        })
        return
    end
    self.pot             = 0
    self.time_remaining  = self.duration
    self.phase           = "question"
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    self:_startCountdown()
end

function DoubleOrNothingScreen:onReveal()
    self:_stopCountdown()
    self.phase = "reveal"
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function DoubleOrNothingScreen:onCorrect()
    self.pot = self.pot == 0 and BASE_POT or self.pot * 2
    self.phase = "choice"
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function DoubleOrNothingScreen:onWrong()
    local is_fr = self.lang == "fr"
    local team  = self.teams[self.current_team]
    UIManager:show(InfoMessage:new{
        text = is_fr
            and string.format("%s perd tout (%d pt en jeu). Manche suivante !", team.name, self.pot)
            or  string.format("%s loses it all (%d pt in play). Next team!", team.name, self.pot),
        timeout = 3,
    })
    self:_endTurn()
end

function DoubleOrNothingScreen:onBank()
    local team = self.teams[self.current_team]
    team.score = team.score + self.pot
    self:_endTurn()
end

function DoubleOrNothingScreen:onDoubleAgain()
    self.q_index         = self.q_index + 1
    self.time_remaining  = self.duration
    self.phase           = "question"
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    self:_startCountdown()
end

function DoubleOrNothingScreen:_endTurn()
    self.pot           = 0
    self.q_index        = self.q_index + 1
    self.current_team  = (self.current_team % #self.teams) + 1
    self.phase          = "idle"
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function DoubleOrNothingScreen:onResetScores()
    for _, t in ipairs(self.teams) do t.score = 0 end
    self.current_team = 1
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------

function DoubleOrNothingScreen:openOptionsMenu()
    local is_fr = self.lang == "fr"
    local items = {
        { id = "lang",     text = is_fr and "Langue…"                    or "Language…" },
        { id = "teams",    text = is_fr and "Nombre d'équipes…"          or "Number of teams…" },
        { id = "duration", text = is_fr and "Chrono de réflexion…"       or "Thinking timer…" },
        { id = "reset",    text = is_fr and "Remettre les scores à zéro" or "Reset scores" },
        { id = "reload",   text = is_fr and "Recharger le fichier"       or "Reload file" },
    }
    MenuHelper.openPickerMenu{
        title = "Options", items = items, parent = self,
        on_select = function(id)
            if     id == "lang"     then self:openLangMenu()
            elseif id == "teams"    then self:openTeamsMenu()
            elseif id == "duration" then self:openDurationMenu()
            elseif id == "reset"    then self:onResetScores()
            elseif id == "reload"   then self:_loadQuestions(); self:buildLayout(); UIManager:setDirty(self, function() return "ui", self.dimen end)
            end
        end,
    }
end

function DoubleOrNothingScreen:openLangMenu()
    MenuHelper.openPickerMenu{
        title = "Language / Langue",
        items = { { id = "fr", text = "Français" }, { id = "en", text = "English" } },
        current_id = self.lang, parent = self,
        on_select = function(lang)
            self.lang = lang
            self.plugin:saveSetting("lang", lang)
            self:_loadQuestions()
            self:buildLayout()
            UIManager:setDirty(self, function() return "ui", self.dimen end)
        end,
    }
end

function DoubleOrNothingScreen:openTeamsMenu()
    local is_fr = self.lang == "fr"
    local items = {}
    for n = 2, 6 do
        items[#items + 1] = { id = n, text = n .. " " .. (is_fr and "équipes" or "teams") }
    end
    MenuHelper.openPickerMenu{
        title = is_fr and "Équipes" or "Teams",
        items = items, current_id = #self.teams, parent = self,
        on_select = function(n)
            self.plugin:saveSetting("nb_teams", n)
            while #self.teams < n do
                local i = #self.teams + 1
                self.teams[i] = { name = (self.lang == "fr" and "Équipe " or "Team ") .. i, score = 0 }
            end
            while #self.teams > n do table.remove(self.teams) end
            if self.current_team > #self.teams then self.current_team = 1 end
            self:buildLayout()
            UIManager:setDirty(self, function() return "ui", self.dimen end)
        end,
    }
end

function DoubleOrNothingScreen:openDurationMenu()
    local is_fr = self.lang == "fr"
    local items = {
        { id = 0,  text = is_fr and "Pas de chrono" or "No timer" },
        { id = 15, text = "0:15" }, { id = 20, text = "0:20" },
        { id = 30, text = "0:30" }, { id = 45, text = "0:45" },
    }
    MenuHelper.openPickerMenu{
        title = is_fr and "Chrono" or "Timer",
        items = items, current_id = self.duration, parent = self,
        on_select = function(dur)
            self.duration = dur
            self.plugin:saveSetting("duration", dur)
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function DoubleOrNothingScreen:buildLayout()
    if self.phase == "idle" then
        self:_buildIdleLayout()
    else
        self:_buildPlayLayout()
    end
    self[1] = self.layout
    self:updateStatus()
end

function DoubleOrNothingScreen:_buildIdleLayout()
    local sw    = DeviceScreen:getWidth()
    local sh    = DeviceScreen:getHeight()
    local is_fr = self.lang == "fr"
    local team  = self.teams[self.current_team]

    local title_bar = self:buildTitleBar(_("Double or Nothing Party"), function()
        return {
            { text = is_fr and "Réglages" or "Settings", callback = function() self:openOptionsMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    local btn_w = math.floor(sw * 0.92)
    local buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_w,
        buttons = {{
            { text = is_fr and "Commencer le tour" or "Start turn",
              callback = function() self:onStartTurn() end },
        }},
    }

    local score_parts = {}
    for _, t in ipairs(self.teams) do
        score_parts[#score_parts + 1] = t.name .. " : " .. t.score
    end
    local score_w = TextWidget:new{
        text = table.concat(score_parts, "   "),
        face = Font:getFace("smallinfofont"),
    }

    local team_fs = math.max(24, math.floor(math.min(sw, sh) * 0.08))
    local team_w  = TextWidget:new{
        text = team.name:upper(),
        face = Font:getFace("cfont", team_fs),
    }

    local sub_w = TextWidget:new{
        text = is_fr and "C'est votre tour !" or "It's your turn!",
        face = Font:getFace("smallinfofont"),
    }

    local deck_line
    if #self.questions == 0 then
        deck_line = is_fr and "⚠ Aucune question — voir Options" or "⚠ No questions — see Options"
    else
        deck_line = is_fr
            and string.format("%d questions chargées", #self.questions)
            or  string.format("%d questions loaded",   #self.questions)
    end
    local deck_w = TextWidget:new{
        text = deck_line,
        face = Font:getFace("smallinfofont"),
    }

    local vs  = VerticalSpan:new{ width = Size.span.vertical_large }
    local vs2 = VerticalSpan:new{ width = Size.span.vertical_large * 4 }

    self.timer_widget = nil
    local content = VerticalGroup:new{
        align = "center",
        score_w,
        vs2,
        team_w,
        vs,
        sub_w,
        vs2,
        deck_w,
    }
    self:buildPortraitLayout(title_bar, content, buttons)
end

function DoubleOrNothingScreen:_buildPlayLayout()
    local sw    = DeviceScreen:getWidth()
    local sh    = DeviceScreen:getHeight()
    local is_fr = self.lang == "fr"
    local q     = self:_currentQuestion()
    local team  = self.teams[self.current_team]

    local title_bar = self:buildTitleBar(_("Double or Nothing Party"), function()
        return {
            { text = is_fr and "Réglages" or "Settings", callback = function() self:openOptionsMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    local btn_w = math.floor(sw * 0.92)
    local action_btns
    if self.phase == "question" then
        action_btns = ButtonTable:new{
            shrink_unneeded_width = true,
            width   = btn_w,
            buttons = {{
                { text = is_fr and "Révéler la réponse" or "Reveal answer",
                  callback = function() self:onReveal() end },
            }},
        }
    elseif self.phase == "reveal" then
        action_btns = ButtonTable:new{
            shrink_unneeded_width = true,
            width   = btn_w,
            buttons = {{
                { text = is_fr and "✓  Juste" or "✓  Correct",
                  callback = function() self:onCorrect() end },
                { text = is_fr and "✗  Faux"  or "✗  Wrong",
                  callback = function() self:onWrong() end },
            }},
        }
    else -- "choice"
        local next_pot = self.pot * 2
        action_btns = ButtonTable:new{
            shrink_unneeded_width = true,
            width   = btn_w,
            buttons = {{
                { text = (is_fr and "🏦  Encaisser " or "🏦  Bank ") .. "+" .. self.pot,
                  callback = function() self:onBank() end },
                { text = (is_fr and "⚡  Doubler → " or "⚡  Double → ") .. next_pot,
                  callback = function() self:onDoubleAgain() end },
            }},
        }
    end

    local pot_text = is_fr
        and string.format("Cagnotte en jeu : %d pt%s", self.pot, self.pot > 1 and "s" or "")
        or  string.format("Pot in play: %d pt%s",       self.pot, self.pot ~= 1 and "s" or "")
    local pot_w = TextWidget:new{
        text = pot_text,
        face = Font:getFace("smallinfofont"),
    }

    local team_w = TextWidget:new{
        text = team.name:upper(),
        face = Font:getFace("cfont", math.max(18, math.floor(math.min(sw, sh) * 0.05))),
    }

    local card_group
    if not q then
        card_group = TextWidget:new{
            text = is_fr and "Aucune question." or "No questions.",
            face = Font:getFace("cfont", 24),
        }
    else
        local question_text = q.question or "?"
        local answer_text   = q.answer or "?"
        local category_text = q.category or ""

        local body = VerticalGroup:new{ align = "center" }
        if category_text ~= "" then
            body[#body + 1] = TextWidget:new{
                text = "[ " .. category_text .. " ]",
                face = Font:getFace("smallinfofont"),
            }
            body[#body + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
        end

        local qlen = #question_text
        local q_fs = qlen > 80 and 16 or qlen > 40 and 20 or 26
        q_fs = math.max(q_fs, math.floor(math.min(sw, sh) * 0.035))
        body[#body + 1] = TextBoxWidget:new{
            text  = question_text,
            face  = Font:getFace("cfont", q_fs),
            width = math.floor(sw * 0.88),
        }

        if self.phase == "reveal" or self.phase == "choice" then
            local sep = TextWidget:new{
                text = string.rep("─", 30),
                face = Font:getFace("smallinfofont"),
            }
            local ans_label = TextWidget:new{
                text = is_fr and "Réponse :" or "Answer:",
                face = Font:getFace("smallinfofont"),
            }
            local a_fs  = math.max(22, math.floor(math.min(sw, sh) * 0.06))
            body[#body + 1] = VerticalSpan:new{ width = Size.span.vertical_large * 2 }
            body[#body + 1] = sep
            body[#body + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
            body[#body + 1] = ans_label
            body[#body + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
            body[#body + 1] = TextBoxWidget:new{
                text  = answer_text,
                face  = Font:getFace("cfont", a_fs),
                width = math.floor(sw * 0.85),
            }
        end

        card_group = body
    end

    local card_frame = FrameContainer:new{
        padding = Size.padding.large,
        margin  = Size.margin.default,
        card_group,
    }

    self.timer_widget = nil
    local timer_group = VerticalGroup:new{ align = "center" }
    if self.phase == "question" and self.duration > 0 then
        local timer_fs = math.max(18, math.floor(math.min(sw, sh) * 0.07))
        self.timer_widget = TextWidget:new{
            text = self:_timerText(),
            face = Font:getFace("cfont", timer_fs),
        }
        timer_group[#timer_group + 1] = self.timer_widget
        timer_group[#timer_group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    end

    local vs  = VerticalSpan:new{ width = Size.span.vertical_large }
    local vs2 = VerticalSpan:new{ width = Size.span.vertical_large * 2 }

    local content = VerticalGroup:new{
        align = "center",
        timer_group,
        team_w,
        vs,
        pot_w,
        vs2,
        card_frame,
    }
    self:buildPortraitLayout(title_bar, content, action_btns)
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function DoubleOrNothingScreen:updateStatus(msg)
    if msg then ScreenBase.updateStatus(self, msg); return end
    local parts = {}
    for _, t in ipairs(self.teams) do
        parts[#parts + 1] = t.name .. " " .. t.score
    end
    ScreenBase.updateStatus(self, table.concat(parts, "  |  "))
end

function DoubleOrNothingScreen:onClose()
    self:_stopCountdown()
    ScreenBase.onClose(self)
end

return DoubleOrNothingScreen
