-- Shine Lifeform Picker
-- lua/shine/extensions/lifeformpicker/server.lua
--
-- Authority for pre-round lifeform declarations.
--
-- Three rules are kept explicit here because the abandoned "Shine - Lifeform Selector" mod got
-- each of them wrong:
--
--  1. The declaring player's identity comes from Client:GetUserId() - never from the message
--     body. That mod trusted a client-supplied steamID, so any modified client could declare a
--     lifeform on someone else's behalf.
--  2. Declarations are only ever transmitted to aliens and spectators. That mod broadcast to
--     everyone and relied on marine clients choosing not to draw them, which puts the data on
--     the enemy's machine regardless.
--  3. State is wiped when the round starts, so nothing leaks between rounds.

local Plugin = ...

-- [ steamId string ] = lifeform index. A player with no entry resolves to Skulk client-side, so
-- absence is a valid state and nothing needs seeding when someone joins.
local Selections = {}

local function IsViewer( Client )
	local Player = Client and Client:GetControllingPlayer()
	local Team = Player and Player:GetTeamNumber()
	return Team == kTeam2Index or Team == kSpectatorIndex
end

local function SendTo( Client, SteamId, Lifeform )
	Server.SendNetworkMessage( Client, "LifeformPicker_State", {
		steamId = SteamId,
		lifeform = Lifeform
	}, true )
end

-- Deliberately per-client rather than a broadcast: this is the filter that keeps declarations off
-- marine machines entirely.
local function Broadcast( SteamId, Lifeform )
	local Clients = Shine.GetAllClients()
	for i = 1, #Clients do
		if IsViewer( Clients[ i ] ) then
			SendTo( Clients[ i ], SteamId, Lifeform )
		end
	end
end

local function SendAllTo( Client )
	for SteamId, Lifeform in pairs( Selections ) do
		SendTo( Client, SteamId, Lifeform )
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
	if Selections[ SteamId ] == Message.lifeform then return end

	Selections[ SteamId ] = Message.lifeform
	Broadcast( SteamId, Message.lifeform )
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

-- Declarations describe the round that is about to start, so they stop being meaningful the
-- moment it does. Clearing here means the next pre-round always begins from a clean slate.
function Plugin:SetGameState( Gamerules, NewState, OldState )
	if NewState == kGameState.Started then
		Selections = {}
	end
end

function Plugin:OnGameReset( Gamerules )
	Selections = {}
end

function Plugin:ClientDisconnect( Client )
	local UserId = Client and Client:GetUserId()
	if UserId then
		Selections[ tostring( UserId ) ] = nil
	end
end

function Plugin:Cleanup()
	Selections = {}
	self.BaseClass.Cleanup( self )
end

return Plugin
