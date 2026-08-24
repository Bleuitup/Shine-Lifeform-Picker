-- Shine Lifeform Picker
-- lua/shine/extensions/lifeformpicker/shared.lua
--
-- Shared definitions: registers the plugin and the two network messages used to declare and
-- replicate pre-round lifeform intentions.
--
-- Declaring a lifeform has no gameplay effect whatsoever. It is a communication aid: it tells
-- your own team, at a glance on the scoreboard, what you are planning to evolve into. Nothing
-- is reserved, spent, or enforced.
--
-- The wire format is an index into kLifeforms rather than a name string. Because the field is
-- declared "integer (0 to 4)" an invalid lifeform is unrepresentable, so neither side needs to
-- normalise or validate the value - it cannot arrive malformed.

local Plugin = Shine.Plugin( ... )
Plugin.Version = "1.3-dev"
Plugin.NS2Only = true

Plugin.PrintName = "Lifeform Picker"
Plugin.HasConfig = false
Plugin.DefaultState = true

-- Index order is simultaneously the wire format and the row order in ui/LifeformPicker/Alien.dds,
-- so an index needs no translation to become a texture offset.
--
-- Vanilla lifeforms only. Alien.dds has a sixth row (Prowler) which is deliberately not exposed;
-- widening the "integer (0 to 4)" range is all that would be needed to add it later.
Plugin.kLifeforms = { "Skulk", "Gorge", "Lerk", "Fade", "Onos" }

-- Everyone is assumed to be a Skulk until they say otherwise, so a player who has never declared
-- simply has no entry and resolves to index 0. An explicit pick of Skulk *is* stored and sent,
-- otherwise changing your mind back to Skulk could not be replicated.
Plugin.kDefaultLifeform = 0

-- Client -> Server: "I intend to play this lifeform."
-- The sender is deliberately not identified in the body; the server uses the connection it
-- arrived on. See server.lua.
Shared.RegisterNetworkMessage( "LifeformPicker_Select", {
	lifeform = "integer (0 to 4)"
} )

-- Server -> Client: one player's declaration. Sent only to aliens and spectators.
--
-- steamId is a string rather than an integer because Steam account IDs are unsigned 32-bit and
-- large ones would wrap negative in a signed network integer.
Shared.RegisterNetworkMessage( "LifeformPicker_State", {
	steamId = "string (16)",
	lifeform = "integer (0 to 4)"
} )

-- Server -> Client: forget every declaration held locally. Sent when the round starts and when
-- the round resets, since server.lua wipes its own table at both points and clients otherwise
-- have no way to learn that -- their cached picks would silently survive into the next pre-round
-- and misreport as fresh declarations instead of resetting to "nobody has called anything yet".
Shared.RegisterNetworkMessage( "LifeformPicker_ClearAll", {} )

return Plugin
