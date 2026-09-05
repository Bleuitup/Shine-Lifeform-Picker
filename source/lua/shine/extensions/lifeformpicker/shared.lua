-- Shine Lifeform Picker
-- lua/shine/extensions/lifeformpicker/shared.lua
--
-- Shared definitions: registers the plugin, its one server-side setting, and the network messages
-- used to declare and replicate pre-round lifeform intentions.
--
-- Declaring a lifeform has no gameplay effect whatsoever. It is a communication aid: it tells
-- your own team, at a glance on the scoreboard, what you are planning to evolve into. Nothing
-- is reserved, spent, or enforced.
--
-- The wire format is an index into kLifeforms rather than a name string. Because the field is
-- declared "integer (0 to 4)" an invalid lifeform is unrepresentable, so neither side needs to
-- normalise or validate the value - it cannot arrive malformed.

local Plugin = Shine.Plugin( ... )
Plugin.Version = "1.42-dev"
Plugin.NS2Only = true

Plugin.PrintName = "Lifeform Picker"
Plugin.DefaultState = true

Plugin.HasConfig = true
Plugin.ConfigName = "LifeformPicker.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

-- How long the icons stay on the scoreboard. Server-owner setting, edited in
-- config://shine/plugins/LifeformPicker.json and applied on map change / plugin reload.
--
--   0  PregameOnly        Icons only before the round starts, and vanish the moment it does.
--   1  UntilFirstLifeform Icons carry into the round and disappear for a player once they have
--                         evolved into anything past Skulk. A latch: it does not come back if
--                         they die back down to a Skulk, only when the round ends.
--   2  FullGame           Icons stay all round and picks can be changed at any time. Once a
--                         player has evolved past Skulk their icon shows what they actually
--                         became - which is not necessarily what they picked - greyed out.
Plugin.kDisplayMode = {
	PregameOnly = 0,
	UntilFirstLifeform = 1,
	FullGame = 2
}

Plugin.DefaultConfig = {
	DisplayMode = Plugin.kDisplayMode.PregameOnly
}

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

-- Client -> Server: "I intend to play this lifeform." Also how you reconfirm a pick that
-- survived from a previous round: sending the same value again still counts as a fresh
-- confirmation - see the guard in server.lua's OnSelect.
-- The sender is deliberately not identified in the body; the server uses the connection it
-- arrived on. See server.lua.
Shared.RegisterNetworkMessage( "LifeformPicker_Select", {
	lifeform = "integer (0 to 4)"
} )

-- Server -> Client: everything the client needs to know about one player, sent whenever any part
-- of it changes. Sent only to aliens and spectators.
--
-- All three facts travel together in one message rather than as separate ones, so a client that
-- joins late gets a complete picture per player from a single pass over the server's table, with
-- no chance of the parts arriving out of step.
--
--   lifeform   what they picked. Persists across round transitions once set.
--   confirmed  whether that pick has been confirmed for the round in progress.
--   evolved    what they have actually evolved into this round, past Skulk. Only meaningful in
--              DisplayMode 1 and 2, and only ever set - dying back to a Skulk does not clear it,
--              which is what makes mode 1's hide a latch and mode 2 keep showing the last
--              lifeform actually reached. Cleared for everyone when the round ends.
--              hasEvolved carries the "not set" case, since an integer field cannot be nil.
--
-- steamId is a string rather than an integer because Steam account IDs are unsigned 32-bit and
-- large ones would wrap negative in a signed network integer.
Shared.RegisterNetworkMessage( "LifeformPicker_State", {
	steamId = "string (16)",
	lifeform = "integer (0 to 4)",
	confirmed = "boolean",
	hasEvolved = "boolean",
	evolved = "integer (0 to 4)"
} )

-- Server -> Client: the server's DisplayMode. All display logic is client side, so the client
-- cannot decide anything until it has been told this. It defaults to PregameOnly until then,
-- which is the most conservative choice - it shows the least.
Shared.RegisterNetworkMessage( "LifeformPicker_Config", {
	displayMode = "integer (0 to 2)"
} )

return Plugin
