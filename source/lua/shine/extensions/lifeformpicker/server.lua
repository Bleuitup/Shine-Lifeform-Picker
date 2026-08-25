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
--  3. Only the confirmation resets when a round starts or resets, not the underlying value - and
--     that reset is broadcast to clients, not just applied here, so their cached copies actually
--     go grey instead of silently continuing to show a stale confirmed pick.
--  4. Re-sending the same lifeform you already have still counts as a fresh confirmation. Without
--     that, clicking your own icon to confirm a pick that survived from last round would look
--     identical to the server as "no change" and do nothing.

local Plugin = ...

-- [ steamId string ] = lifeform index. Persists across round transitions once set; a player with
-- no entry has never declared at all and resolves to Skulk client-side. Never wiped by a round
-- boundary - only ClientDisconnect and Cleanup remove an entry.
local Selections = {}

-- [ steamId string ] = true while that player's current Selections value has been actively
-- confirmed for the round in progress. Cleared on every round start/reset; Selections itself is
-- not touched by that, which is what lets a pick outlive the confirmation.
local Confirmed = {}

local function IsViewer( Client )
	local Player = Client and Client:GetControllingPlayer()
	local Team = Player and Player:GetTeamNumber()
	return Team == kTeam2Index or Team == kSpectatorIndex
end

local function SendTo( Client, SteamId, Lifeform, IsConfirmed )
	Server.SendNetworkMessage( Client, "LifeformPicker_State", {
		steamId = SteamId,
		lifeform = Lifeform,
		confirmed = IsConfirmed
	}, true )
end

-- Deliberately per-client rather than a broadcast: this is the filter that keeps declarations off
-- marine machines entirely.
local function Broadcast( SteamId, Lifeform, IsConfirmed )
	local Clients = Shine.GetAllClients()
	for i = 1, #Clients do
		if IsViewer( Clients[ i ] ) then
			SendTo( Clients[ i ], SteamId, Lifeform, IsConfirmed )
		end
	end
end

local function SendAllTo( Client )
	for SteamId, Lifeform in pairs( Selections ) do
		SendTo( Client, SteamId, Lifeform, Confirmed[ SteamId ] == true )
	end
end

-- Marks every sticky pick unconfirmed for the round that is starting, and tells every current
-- viewer so their icons actually turn grey. The values in Selections are untouched - this is the
-- entire mechanism behind a pick persisting through a round transition while still resetting
-- visually.
local function UnconfirmAll()
	for SteamId in pairs( Selections ) do
		Confirmed[ SteamId ] = nil
	end

	local Clients = Shine.GetAllClients()
	for i = 1, #Clients do
		if IsViewer( Clients[ i ] ) then
			for SteamId, Lifeform in pairs( Selections ) do
				SendTo( Clients[ i ], SteamId, Lifeform, false )
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

	local UserId = Client:GetUserId()
	if not UserId or UserId == 0 then return end

	local SteamId = tostring( UserId )

	-- Re-declaring the same value you already have is exactly how a grey, persisted-but-
	-- unconfirmed pick gets reconfirmed - so unlike a plain "did the value change" check, this
	-- only skips the update when nothing would actually change, confirmation included.
	if Selections[ SteamId ] == Message.lifeform and Confirmed[ SteamId ] then return end

	Selections[ SteamId ] = Message.lifeform
	Confirmed[ SteamId ] = true
	Broadcast( SteamId, Message.lifeform, true )
end

Server.HookNetworkMessage( "LifeformPicker_Select", OnSelect )

-- Push the current picture to anyone who becomes able to see it, rather than having clients poll
-- or ask. Fires for spectators too, since they are viewers.
function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	if NewTeam ~= kTeam2Index and NewTeam ~= kSpectatorIndex then return end

	local Client = Server.GetOwner( Player )
	if Client then
		SendAllTo( Client )
	end
end

-- A confirmation describes the round it was made for, so it stops being meaningful the moment a
-- new one begins - the pick itself does not.
function Plugin:SetGameState( Gamerules, NewState, OldState )
	if NewState == kGameState.Started then
		UnconfirmAll()
	end
end

function Plugin:OnGameReset( Gamerules )
	UnconfirmAll()
end

function Plugin:ClientDisconnect( Client )
	local UserId = Client and Client:GetUserId()
	if UserId then
		local SteamId = tostring( UserId )
		Selections[ SteamId ] = nil
		Confirmed[ SteamId ] = nil
	end
end

function Plugin:Cleanup()
	Selections = {}
	Confirmed = {}
	self.BaseClass.Cleanup( self )
end

return Plugin
