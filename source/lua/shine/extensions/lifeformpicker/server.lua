-- Shine Lifeform Picker
-- lua/shine/extensions/lifeformpicker/server.lua
--
-- Authority for pre-round lifeform declarations.
--
-- A pick is sticky: once made, it survives round transitions rather than being forgotten. What
-- resets each round is only whether it has been *confirmed* - the value stays, the confirmation
-- does not, and the icon reflects that by turning grey until the player reconfirms (or changes
-- their mind) for the new round. See client.lua for how that renders.
--
-- Four rules are kept explicit here because the abandoned "Shine - Lifeform Selector" mod got
-- three of them wrong, and the fourth is what makes persistence work correctly:
--
--  1. The declaring player's identity comes from Client:GetUserId() - never from the message
--     body. That mod trusted a client-supplied steamID, so any modified client could declare a
--     lifeform on someone else's behalf.
--  2. Declarations are only ever transmitted to aliens and spectators. That mod broadcast to
--     everyone and relied on marine clients choosing not to draw them, which puts the data on
--     the enemy's machine regardless.
--  3. Only the confirmation resets when a round ends, not the underlying value - and that reset
--     is broadcast to clients, not just applied here, so their cached copies actually go grey
--     instead of silently continuing to show a stale confirmed pick.
--  4. Re-sending the same lifeform you already have still counts as a fresh confirmation. Without
--     that, clicking your own icon to confirm a pick that survived from last round would look
--     identical to the server as "no change" and do nothing.

local Plugin = ...

-- [ steamId string ] = { lifeform = index or nil, confirmed = bool or nil, evolved = index or nil }
--
-- One entry per player rather than parallel tables keyed the same way: with three facts to track
-- (and a player who has evolved but never declared being a perfectly normal case) parallel tables
-- would need every read, write and sync to remember to visit all of them.
--
-- lifeform and evolved have different lifetimes on purpose. lifeform is sticky and only removed
-- on disconnect; evolved describes the round in progress and is cleared when it ends.
local State = {}

local function GetEntry( SteamId )
	local Entry = State[ SteamId ]
	if not Entry then
		Entry = {}
		State[ SteamId ] = Entry
	end
	return Entry
end

local function IsViewer( Client )
	local Player = Client and Client:GetControllingPlayer()
	local Team = Player and Player:GetTeamNumber()
	return Team == kTeam2Index or Team == kSpectatorIndex
end

local function SendEntryTo( Client, SteamId, Entry )
	Server.SendNetworkMessage( Client, "LifeformPicker_State", {
		steamId = SteamId,
		lifeform = Entry.lifeform or Plugin.kDefaultLifeform,
		confirmed = Entry.confirmed == true,
		hasEvolved = Entry.evolved ~= nil,
		evolved = Entry.evolved or Plugin.kDefaultLifeform
	}, true )
end

-- Deliberately per-client rather than a broadcast: this is the filter that keeps declarations off
-- marine machines entirely.
local function Broadcast( SteamId, Entry )
	local Clients = Shine.GetAllClients()
	for i = 1, #Clients do
		if IsViewer( Clients[ i ] ) then
			SendEntryTo( Clients[ i ], SteamId, Entry )
		end
	end
end

local function SendAllTo( Client )
	Server.SendNetworkMessage( Client, "LifeformPicker_Config", {
		displayMode = Plugin.Config.DisplayMode
	}, true )

	for SteamId, Entry in pairs( State ) do
		SendEntryTo( Client, SteamId, Entry )
	end
end

-- Ends the round's worth of state: every pick becomes unconfirmed and every evolution is
-- forgotten, while the picks themselves survive. Broadcast rather than only applied here, or
-- already-connected clients would keep showing last round's confirmations as current.
local function ResetRound()
	for SteamId, Entry in pairs( State ) do
		Entry.confirmed = nil
		Entry.evolved = nil
	end

	local Clients = Shine.GetAllClients()
	for i = 1, #Clients do
		if IsViewer( Clients[ i ] ) then
			for SteamId, Entry in pairs( State ) do
				SendEntryTo( Clients[ i ], SteamId, Entry )
			end
		end
	end
end

local function OnSelect( Client, Message )
	if not Client or Client:GetIsVirtual() then return end

	local Player = Client:GetControllingPlayer()
	if not Player or Player:GetTeamNumber() ~= kTeam2Index then return end

	-- Commanders have no lifeform to declare while they are in the chair. Player:GetIsCommander
	-- returns false on the base class and is overridden by Commander, so this is polymorphic.
	--
	-- Note this rejects the *declaration*, it does not erase an existing one: someone who called
	-- Fade and then took the chair keeps that stored, hidden while they command, and showing
	-- again if they log out. Losing it on every accidental chair-tap would be worse.
	if Player:GetIsCommander() then return end

	-- Picks can only be changed while they still describe something that has not happened yet.
	-- In PregameOnly the icons are gone once the round starts anyway; in UntilFirstLifeform the
	-- point of the mode is that evolving settles the question. FullGame is the mode that
	-- explicitly allows changing your mind mid-round.
	if Plugin.Config.DisplayMode ~= Plugin.kDisplayMode.FullGame and not Plugin:IsPreRound() then
		return
	end

	local UserId = Client:GetUserId()
	if not UserId or UserId == 0 then return end

	local SteamId = tostring( UserId )
	local Entry = GetEntry( SteamId )

	-- Re-declaring the same value you already have is exactly how a grey, persisted-but-
	-- unconfirmed pick gets reconfirmed - so unlike a plain "did the value change" check, this
	-- only skips the update when nothing would actually change, confirmation included.
	if Entry.lifeform == Message.lifeform and Entry.confirmed then return end

	Entry.lifeform = Message.lifeform
	Entry.confirmed = true
	Broadcast( SteamId, Entry )
end

Server.HookNetworkMessage( "LifeformPicker_Select", OnSelect )

-- Maps the alien player classes that count as "evolved" to their lifeform index. Skulk is
-- deliberately absent: it is the state everyone starts in, so treating it as an evolution would
-- make every alien immediately "evolved". Embryo is absent too - gestating is not yet arriving,
-- and a player who dies mid-gestation never got there.
local kEvolvedClassToLifeform = {
	Gorge = 1,
	Lerk = 2,
	Fade = 3,
	Onos = 4
}

-- Polled rather than hooked. The moment a gestation completes is inside UpdateGestation, a
-- file-local in Embryo.lua, so there is nothing there to hook; Player:Replace is reachable but
-- fires for team changes and respawns too, and would have to be filtered by resulting class
-- anyway. Reading the class directly is immune to however NS2 arranges any of that internally,
-- and for a scoreboard icon a second of latency is not worth trading robustness for.
local function PollEvolutions()
	local Clients = Shine.GetAllClients()

	for i = 1, #Clients do
		local Client = Clients[ i ]
		local Player = Client and Client:GetControllingPlayer()

		if Player and Player:GetTeamNumber() == kTeam2Index then
			local Lifeform = kEvolvedClassToLifeform[ Player:GetClassName() ]
			local UserId = Lifeform and Client:GetUserId()

			if UserId and UserId ~= 0 then
				local SteamId = tostring( UserId )
				local Entry = GetEntry( SteamId )

				-- Only ever set, never cleared on the way back down. That is what makes mode 1's
				-- hide a latch for the round, and what lets mode 2 keep showing the last lifeform
				-- actually reached after a death back to Skulk.
				if Entry.evolved ~= Lifeform then
					Entry.evolved = Lifeform
					Broadcast( SteamId, Entry )
				end
			end
		end
	end
end

function Plugin:IsPreRound()
	local Gamerules = GetGamerules and GetGamerules()
	local GameState = Gamerules and Gamerules:GetGameState()

	return GameState == kGameState.NotStarted or GameState == kGameState.WarmUp
		or GameState == kGameState.PreGame or GameState == kGameState.Countdown
end

function Plugin:Initialise()
	-- CheckConfigTypes catches a non-number, but not a number outside the three modes.
	local Mode = self.Config.DisplayMode
	if Mode ~= self.kDisplayMode.PregameOnly and Mode ~= self.kDisplayMode.UntilFirstLifeform
	and Mode ~= self.kDisplayMode.FullGame then
		self:Print( "DisplayMode %s is not 0, 1 or 2 - falling back to 0 (pregame only).",
			true, tostring( Mode ) )
		self.Config.DisplayMode = self.kDisplayMode.PregameOnly
	end

	-- PregameOnly never looks at what anyone evolved into, so it does not need the poll at all.
	if self.Config.DisplayMode ~= self.kDisplayMode.PregameOnly then
		self:CreateTimer( "PollEvolutions", 1, -1, PollEvolutions )
	end

	-- ClientConnect covers everyone who joins from here on, but not anyone already connected -
	-- which is exactly the case after sh_reloadplugin, where the mode may well have just changed.
	-- Without this they would keep the old mode until they reconnected.
	local Clients = Shine.GetAllClients()
	for i = 1, #Clients do
		Server.SendNetworkMessage( Clients[ i ], "LifeformPicker_Config", {
			displayMode = self.Config.DisplayMode
		}, true )
	end

	self.Enabled = true

	return true
end

-- Push the current picture to anyone who becomes able to see it, rather than having clients poll
-- or ask. Fires for spectators too, since they are viewers.
function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	if NewTeam ~= kTeam2Index and NewTeam ~= kSpectatorIndex then return end

	local Client = Server.GetOwner( Player )
	if Client then
		SendAllTo( Client )
	end
end

-- Every client needs the mode, not just viewers: someone sitting in the ready room has to already
-- know it by the time they join aliens.
function Plugin:ClientConnect( Client )
	Server.SendNetworkMessage( Client, "LifeformPicker_Config", {
		displayMode = self.Config.DisplayMode
	}, true )
end

-- A confirmation describes the round it was made for, and an evolution describes the round it
-- happened in. Both stop being meaningful when that round ends; the picks themselves do not.
--
-- This keys off the round *ending* rather than starting, so that in the modes where icons carry
-- into the round a confirmed pick stays confirmed while it is still worth reading. In
-- PregameOnly the icons vanish at kGameState.Started anyway, so resetting there instead would be
-- invisible either way.
function Plugin:SetGameState( Gamerules, NewState, OldState )
	if NewState == kGameState.Team1Won or NewState == kGameState.Team2Won
	or NewState == kGameState.Draw then
		ResetRound()
	end
end

function Plugin:OnGameReset( Gamerules )
	ResetRound()
end

function Plugin:ClientDisconnect( Client )
	local UserId = Client and Client:GetUserId()
	if UserId then
		State[ tostring( UserId ) ] = nil
	end
end

function Plugin:Cleanup()
	State = {}

	-- Destroys the poll timer too - CreateTimer registers it with the plugin, and the base
	-- Cleanup tears down everything it registered.
	self.BaseClass.Cleanup( self )
end

return Plugin
