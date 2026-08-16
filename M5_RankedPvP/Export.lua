--[[
    ============================================================================
     M5 Ranked PvP — Export.lua
    ----------------------------------------------------------------------------
     YOUR file. Put whatever you want to happen around a match in here.

     Nothing else in the resource needs editing to add your own behaviour:
     give a hook a body and it runs at that moment. Every hook is called
     inside pcall, so a mistake in here prints an error and the match carries
     on — it can never break the PvP system.

     This file is a shared_script: the same file is loaded on the client and
     on the server. The M5.Client hooks only ever run on the client and the
     M5.Server hooks only ever run on the server, so it is always obvious
     which side your code is on. Client natives belong in M5.Client, database
     and vRP calls belong in M5.Server.

     Three ways to react to the system, use whichever suits you:

       1. Fill in a hook below.                     (simplest)
       2. Listen to the events it fires:            (from another resource)
              AddEventHandler('m5rp:onMatchJoin', function(data) end)
          Client side events fire on the client, server side on the server.
       3. Call the exports it registers:            (from another resource)
              exports.M5_RankedPvP:isInMatch()
              exports.M5_RankedPvP:getMatchInfo()
              exports.M5_RankedPvP:getPlayerRank(userId)   -- server only

     Names below are stable; new hooks may be added, existing ones will not
     change shape.
    ============================================================================
]]

M5 = M5 or {}

-- ============================================================================
-- CLIENT HOOKS
-- ============================================================================
-- Run on the player's own machine. Use client natives here.

M5.Client = {

    --- The player just entered a match, before the first round starts.
    --- data = {
    ---   matchId, mode, modeLabel, ranked (bool), custom (bool),
    ---   practice (bool, true for a bot match), team (1 or 2), ffa (bool),
    ---   map = { id, name }, players (number)
    --- }
    onMatchJoin = function(data)
        -- example: hide another HUD while the fight is on
        -- TriggerEvent('esx_status:pause', true)
        -- exports['my_hud']:setVisible(false)
    end,

    --- The player left the match — finished it, quit, or was removed.
    --- data = { matchId, reason = 'END' | 'LEAVE' | 'KICK' | 'DISCONNECT' }
    onMatchLeave = function(data)
        -- example: put your own HUD back
        -- TriggerEvent('esx_status:pause', false)
        -- exports['my_hud']:setVisible(true)
    end,

    --- A round went live (the countdown finished).
    --- data = { matchId, round, time }
    onRoundStart = function(data)
    end,

    --- A round finished.
    --- data = { matchId, round, winner (1, 2 or 0), reason, scores = { a, b } }
    onRoundEnd = function(data)
    end,

    --- This player died inside a match.
    --- data = { matchId, killer, weapon, headshot (bool), respawn (bool) }
    onDeath = function(data)
    end,

    --- The whole match ended and the result screen opened.
    --- data = { matchId, result = 'WIN' | 'LOSS' | 'DRAW', scores, rp = { delta } }
    onMatchEnd = function(data)
    end,

    --- Entered or left the training range.
    --- data = { kind, label }
    onTrainingStart = function(data)
    end,
    onTrainingEnd = function(data)
    end
}

-- ============================================================================
-- SERVER HOOKS
-- ============================================================================
-- Run on the server. Use oxmysql, vRP and anything else server side here.

M5.Server = {

    --- A player entered a match. Called once per player.
    --- data = {
    ---   userId, source, name, matchId, mode, ranked (bool), custom (bool),
    ---   practice (bool), team, rankId, rank, rp, mmr
    --- }
    onMatchJoin = function(data)
        -- example: take an entry fee, or write your own log
        -- vRP.tryPayment({ data.userId, 500 })
        print(('[M5RP] %s entered match %s'):format(data.name, data.matchId))
    end,

    --- A player left a match, for any reason.
    --- data = { userId, source, name, matchId, reason }
    onMatchLeave = function(data)
        print(('[M5RP] %s left match %s (%s)'):format(data.name, data.matchId, data.reason))
    end,

    --- The match finished and every reward was already applied by the system.
    --- data = {
    ---   matchId, mode, ranked, winner (1, 2 or 0), scores = { a, b },
    ---   mvp = userId or nil,
    ---   players = { { userId, name, team, kills, deaths, assists, headshots,
    ---                 damage, score, won (bool), rpDelta } , ... }
    --- }
    onMatchEnd = function(data)
        -- example: pay the winners something of your own
        -- for _, p in ipairs(data.players) do
        --     if p.won then vRP.giveMoney({ p.userId, 5000 }) end
        -- end
    end,

    --- One kill, as the server resolved it. Authoritative.
    --- data = { matchId, killerUserId, killerName, victimUserId, victimName,
    ---          weapon, headshot (bool) }
    onKill = function(data)
    end,

    --- The player joined or left the ranked queue.
    --- data = { userId, name, mode, partySize }
    onQueueJoin = function(data)
    end,
    onQueueLeave = function(data)
    end,

    --- The player's rank changed, from a match or from a staff grant.
    --- data = { userId, name, from = { id, name }, to = { id, name }, rp, promoted (bool) }
    onRankChange = function(data)
        -- example: hand out a vRP group at a certain rank
        -- if data.to.name == 'Radiant' then
        --     vRP.addUserGroup({ data.userId, 'radiant' })
        -- end
    end
}
