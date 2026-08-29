-- Shine Lifeform Picker
-- lua/shine/extensions/lifeformpicker/client.lua
--
-- Draws a lifeform icon on each alien scoreboard row during the pre-round, and lets you click
-- your own icon to declare what you intend to play.
--
-- A pick is sticky across round transitions - see server.lua - so this file distinguishes the
-- lifeform *value* (which persists) from whether it is *confirmed* for the round in progress
-- (which does not): the icon always shows the last value chosen, tinted grey until it has been
-- confirmed and cream once it has.
--
-- The scoreboard is reached with Shine.Hook.SetupClassHook rather than a ModLoader file hook.
-- That matters for compatibility: mods such as Shimizu Scoreboard claim lua/GUIScoreboard.lua in
-- "replace" mode, and a second mod hooking the same file fights it. Patching the class methods at
-- runtime leaves the file untouched, so this coexists with whatever owns it.

local Plugin = ...

local kAtlas = PrecacheAsset( "ui/LifeformPicker/Alien.dds" )

-- Alien.dds is a 340x570 vertical strip of 340x114 cells, one lifeform per row, in the same
-- order as Plugin.kLifeforms. The source atlas it was cut from carried eleven further rows
-- (Prowler, Shell, Spur, Veil and other structures) that this never samples; they were cropped
-- off the bottom, which leaves rows 0-4 at unchanged coordinates.
--
-- The silhouettes only occupy x 83-250 inside each 340-wide cell; the rest is transparent
-- padding. Cropping to one uniform window across every row keeps a single geometry for all five
-- icons. Tight-cropping each lifeform to its own bounding box instead would give them aspect
-- ratios from 0.90 to 1.78, and squeezing those into a fixed-size box is exactly what makes the
-- old Lifeform Selector mod's icons look stretched.
local kCellHeight = 114
local kCropLeft, kCropRight = 83, 251

-- (251 - 83) / 114 = 1.474, so these preserve the source aspect ratio.
local kIconHeight = 19
local kIconWidth = 28
local kIconGap = 4

-- The artwork is pure white with the shape carried entirely in the alpha channel, which makes it
-- an ideal tint target: SetColor multiplies, so white takes any hue cleanly.
--
-- This is the cream the old Lifeform Selector mod's icons had. That mod never tinted anything -
-- it applied a no-op Color(1,1,1,1) - so the colour came from its texture, the vanilla
-- ui/alien_hivestatus_commicons.dds, whose opaque pixels are baked at RGB 255,225,187. Sampling
-- it and reproducing the value here gets the same look from white source art.
--
-- Two tints signal confirmed intent versus a value that is only remembered from before. Grey is
-- the same "not yet meaningful" tone Enhanced Scoreboard / Shimizu Scoreboard use for their own
-- inactive icons (kEalInactiveColor, RGB 96,96,96); confirming switches the icon to the cream
-- above. A pick that survived a round transition is grey with the same shape it had before -
-- only cream, not the icon itself, is what confirming restores.
local kIconColourUnconfirmed = Color( 96 / 255, 96 / 255, 96 / 255, 1 )
local kIconColourConfirmed = Color( 255 / 255, 225 / 255, 187 / 255, 1 )

-- Everything before the round is live. Note this is a set rather than a single comparison: a
-- match passes through NotStarted, WarmUp, PreGame and Countdown, and testing only for WarmUp
-- (as the old mod does) makes the icons vanish exactly when the round is about to begin.
local kPreRoundStates = {
	[ kGameState.NotStarted ] = true,
	[ kGameState.WarmUp ] = true,
	[ kGameState.PreGame ] = true,
	[ kGameState.Countdown ] = true
}

-- [ steamId string ] = { lifeform = index, confirmed = boolean }, as replicated by the server.
-- A player with no entry has never declared at all, which the lookups below distinguish from a
-- present-but-unconfirmed entry: both render grey, but only the former falls back to the default
-- lifeform rather than showing a remembered one.
local Selections = {}

-- Our own private GUIHoverTooltip instance, plus the state needed to avoid redundant work on it.
-- Created lazily by GetTooltip() below; destroyed in Cleanup.
local Tooltip = nil
local TooltipText = nil
local TooltipShown = false

local function IsPreRound()
	local GameInfo = GetGameInfoEntity()
	return GameInfo ~= nil and kPreRoundStates[ GameInfo:GetState() ] == true
end

local function IsLocalViewer()
	local Player = Client.GetLocalPlayer()
	local Team = Player and Player:GetTeamNumber()
	return Team == kTeam2Index or Team == kSpectatorIndex
end

-- GetSteamIdForClientIndex returns nil until that player's PlayerInfoEntity has replicated, so
-- the tostring() here can legitimately produce "nil". That simply misses the table and falls
-- back to the Skulk default, which is the correct thing to show anyway.
local function GetLifeformFor( ClientIndex )
	local Entry = Selections[ tostring( GetSteamIdForClientIndex( ClientIndex ) ) ]
	return Entry and Entry.lifeform or Plugin.kDefaultLifeform
end

-- Whether the current value showing for this player has actually been confirmed for the round in
-- progress, as opposed to only being remembered from a previous one. Drives the grey/cream tint;
-- GetLifeformFor deliberately does not care about this distinction, since the texture shown is
-- the same lifeform either way.
local function IsConfirmed( ClientIndex )
	local Entry = Selections[ tostring( GetSteamIdForClientIndex( ClientIndex ) ) ]
	return Entry ~= nil and Entry.confirmed == true
end

-- A GUIHoverTooltip of our own, deliberately NOT vanilla's shared Scoreboard.badgeNameTooltip.
--
-- Sharing that one does not work. Vanilla's per-row hover logic calls badgeNameTooltip:Hide()
-- every frame the cursor is inside a player row but not over a badge or the skill icon - which is
-- precisely the case when it is over our icon, since our icon lives inside that row. Our hook runs
-- PassivePost, so every frame became: vanilla Hide() destroys the fade-in animation and starts a
-- fade-out, then our Show() destroys that and restarts a 0.25s fade-in *from the current partial
-- alpha*. Restarting an ease-to-target every frame from wherever it got to approaches full opacity
-- asymptotically, which is why the tooltip appeared to crawl into view rather than fading in.
--
-- CreateGUIScript (as opposed to CreateGUIScriptSingle, which returns the shared singleton) hands
-- back a fresh instance, registered with the GUI manager so its own Update runs - which is what
-- makes it follow the cursor and flip near screen edges. Vanilla drives its tooltip, we drive
-- ours, and neither touches the other's animations.
local function GetTooltip()
	if not Tooltip then
		Tooltip = GetGUIManager():CreateGUIScript( "menu/GUIHoverTooltip" )
	end
	return Tooltip
end

local function HideTooltip()
	if Tooltip and TooltipShown then
		Tooltip:Hide()
		TooltipShown = false
	end
end

local function EnsureIcon( PlayerItem )
	local Icon = PlayerItem.LifeformPickerIcon
	if Icon then return Icon end

	Icon = GUIManager:CreateGraphicItem()
	-- Anchored to the Status text item's own right edge, and parented to it directly rather than
	-- to the row background, on Devnull's suggestion: mods such as Enhanced Scoreboard draw
	-- their own upgrade icons to the left of Status, which collided with this icon's previous
	-- left-of-Status position. Parenting under Status also means the icon now tracks Status's
	-- position through the engine's own transform hierarchy rather than being repositioned every
	-- frame from a read of it.
	Icon:SetAnchor( GUIItem.Right, GUIItem.Center )
	Icon:SetTexture( kAtlas )
	-- No SetColor here: confirmed-vs-not can change every frame (a pick lands, a round resets),
	-- so the colour is set on every render pass below instead of once at creation.
	Icon:SetStencilFunc( GUIItem.NotEqual )
	Icon:SetIsVisible( false )
	PlayerItem.Status:AddChild( Icon )

	PlayerItem.LifeformPickerIcon = Icon
	return Icon
end

-- Both class hooks are installed from inside CallAfterFileLoad rather than at file scope.
--
-- This is not optional. Shine.Hook.SetupClassHook resolves the class through _G at the moment it
-- is called, and if lua/GUIScoreboard.lua has not been loaded yet it prints
--   [Shine] [Warn] Attempted to hook class/method GUIScoreboard:Update() which does not exist!
-- and then silently does nothing - the plugin loads and enables perfectly happily while none of
-- its hooks exist. Client plugins can enable before the map's GUI scripts are loaded, so hooking
-- at file scope is a race. CallAfterFileLoad fires immediately if the file is already loaded and
-- otherwise waits, which covers both orderings (and re-fires on a script reload; SetupClassHook
-- dedupes, so being called twice is harmless).
--
-- This is the same idiom Shine's own GUI-hooking plugins use - see extensions/tweaks/client.lua
-- and extensions/chatbox/client.lua.
Shine.Hook.CallAfterFileLoad( "lua/GUIScoreboard.lua", function()
	Shine.Hook.SetupClassHook( "GUIScoreboard", "Update", "OnLifeformPickerScoreboardUpdate", "PassivePost" )
	Shine.Hook.SetupClassHook( "GUIScoreboard", "SendKeyEvent", "OnLifeformPickerScoreboardKey", "ActivePre" )
	Plugin.HooksInstalled = true
end )

function Plugin:OnLifeformPickerScoreboardUpdate( Scoreboard )
	if not Scoreboard.teams then return end

	local Show = IsPreRound() and IsLocalViewer()
	local Scale = GUIScoreboard.kScalingFactor

	-- Hovering an icon shows its lifeform in a GUIHoverTooltip of our own (see GetTooltip), styled
	-- exactly like the comm badge / playtester badge / skill icon tooltips because it is the same
	-- widget class - just not the same instance vanilla drives.
	local CanShowTooltip = Show and MouseTracker_GetIsVisible()
		and not Scoreboard.hoverMenu.background:GetIsVisible() and not MainMenu_GetIsOpened()
	local MouseX, MouseY
	if CanShowTooltip then
		MouseX, MouseY = Client.GetCursorPosScreen()
	end
	local HoveredIndex = nil

	for i = 1, #Scoreboard.teams do
		local Team = Scoreboard.teams[ i ]
		local IsAlienTeam = Team.TeamNumber == kTeam2Index
		local PlayerList = Team.PlayerList

		for p = 1, #PlayerList do
			local PlayerItem = PlayerList[ p ]
			local Icon = EnsureIcon( PlayerItem )

			-- The commander is not going to evolve into anything, so there is nothing for them
			-- to declare and an icon on their row would just be noise. They still see everyone
			-- else's - arguably the person who most wants to know the team's composition.
			local IsCommander = PlayerItem.ClientIndex
				and Scoreboard_GetPlayerData( PlayerItem.ClientIndex, "IsCommander" ) == true

			-- Every row is touched on every pass, including marine and ready-room rows. Player
			-- items are pooled and recycled between teams, so a row that used to belong to an
			-- alien can reappear on the marine list; setting visibility unconditionally here is
			-- what stops it carrying its old icon across, and removes any need to also hook
			-- ResizePlayerList.
			if Show and IsAlienTeam and not IsCommander then
				local Index = GetLifeformFor( PlayerItem.ClientIndex )
				local Confirmed = IsConfirmed( PlayerItem.ClientIndex )

				-- kIconGap here is purely local to Status now that the icon is parented to it -
				-- no need to read Status's own position, since the anchor already places the
				-- icon at Status's right edge and this offset only nudges it clear of that edge.
				Icon:SetSize( Vector( kIconWidth, kIconHeight, 0 ) * Scale )
				Icon:SetPosition( Vector( kIconGap * Scale, -kIconHeight * Scale, 0 ) )
				Icon:SetTexturePixelCoordinates( kCropLeft, kCellHeight * Index,
					kCropRight, kCellHeight * ( Index + 1 ) )
				Icon:SetColor( Confirmed and kIconColourConfirmed or kIconColourUnconfirmed )
				Icon:SetIsVisible( true )

				if CanShowTooltip and HoveredIndex == nil
				and GUIItemContainsPoint( Icon, MouseX, MouseY ) then
					HoveredIndex = Index
				end
			else
				Icon:SetIsVisible( false )
			end
		end
	end

	if HoveredIndex ~= nil then
		local Text = string.format( "Planned Lifeform: %s", Plugin.kLifeforms[ HoveredIndex + 1 ] )
		local ThisTooltip = GetTooltip()

		-- SetText re-runs word wrapping and resizes the background, so only call it when the text
		-- actually changed (moving between two icons showing different lifeforms).
		if TooltipText ~= Text then
			ThisTooltip:SetText( Text )
			TooltipText = Text
		end

		-- Likewise only Show on the transition. Show() is guarded internally against restarting a
		-- running TOOLTIP_SHOW animation, so calling it every frame would be harmless now that
		-- nothing interleaves a Hide() - but there is no reason to.
		if not TooltipShown then
			ThisTooltip:Show()
			TooltipShown = true
		end
	else
		HideTooltip()
	end
end

local function ShowLifeformMenu( Scoreboard )
	local Menu = Scoreboard.hoverMenu

	-- The same palette both the old Lifeform Selector and Shimizu Scoreboard use. Despite the
	-- name, GUIScoreboard.kRedColor is the alien team's orange.
	local Background = GUIScoreboard.kRedColor * 0.5
	local Highlight = GUIScoreboard.kRedColor * 0.75
	local TextColour = Color( 1, 1, 1, 1 )

	Menu:ResetButtons()

	-- A non-interactive title row, the same idiom Shimizu Scoreboard uses for its own lifeform
	-- menu: transparent background and highlight so it never looks clickable, and no callback
	-- so GUIHoverMenu's click handling skips it (only AddButton entries with a callback fire
	-- when clicked, per GUIHoverMenu:SendKeyEvent).
	Menu:AddButton( "Planned Lifeform", Color( 0, 0, 0, 0 ), Color( 0, 0, 0, 0 ), TextColour )

	for i = 1, #Plugin.kLifeforms do
		-- Captured per iteration so each button sends its own index. Sending the same lifeform
		-- already held (for example reconfirming a grey pick that survived from last round) is
		-- not special-cased here - server.lua is what turns that into a fresh confirmation.
		local Index = i - 1
		Menu:AddButton( Plugin.kLifeforms[ i ], Background, Highlight, TextColour, function()
			Client.SendNetworkMessage( "LifeformPicker_Select", { lifeform = Index }, true )
		end )
	end

	-- Show() places the menu at the cursor using the background's *current* size, and AddButton
	-- resizes that background as it goes - so it has to run after the buttons exist. Populating a
	-- menu that is already open (what the old mod does, by leaning on the one vanilla just
	-- opened) leaves it sized correctly but positioned from the stale size.
	Menu:Show()

	if Scoreboard.badgeNameTooltip then
		Scoreboard.badgeNameTooltip:Hide( 0 )
	end

	-- Ours too: the menu opens over the icon that was being hovered, and waiting for the next
	-- update pass to notice would leave the tooltip visible under it for a frame.
	HideTooltip()
end

-- Hooked as ActivePre (see CallAfterFileLoad above): returning a non-nil value skips vanilla's
-- handler entirely and returns that value. Returning true on a hit therefore claims the click, so
-- the vanilla Steam-profile/mute menu does not also open on top of the lifeform menu. Returning
-- nothing lets vanilla proceed untouched.
function Plugin:OnLifeformPickerScoreboardKey( Scoreboard, Key, Down )
	if Key ~= InputKey.MouseButton0 or not Down then return end
	if not Scoreboard.visible or Scoreboard.hiddenOverride then return end
	if not MouseTracker_GetIsVisible() or MainMenu_GetIsOpened() then return end
	if not IsPreRound() then return end

	local Menu = Scoreboard.hoverMenu
	if not Menu or Menu.background:GetIsVisible() then return end

	-- Spectators can see declarations but cannot make them, and you may only declare for
	-- yourself, so only your own row responds to a click.
	--
	-- Commanders are excluded too: they have no lifeform to call while in the chair. The
	-- server enforces this as well; this check only avoids offering a menu that would be
	-- rejected. Their row has no icon to click anyway, so this is belt and braces.
	local Player = Client.GetLocalPlayer()
	if not Player or Player:GetTeamNumber() ~= kTeam2Index then return end
	if Player.GetIsCommander and Player:GetIsCommander() then return end

	local LocalSteamId = tostring( Client.GetSteamId() )
	local MouseX, MouseY = Client.GetCursorPosScreen()

	for i = 1, #Scoreboard.teams do
		local Team = Scoreboard.teams[ i ]
		if Team.TeamNumber == kTeam2Index then
			local PlayerList = Team.PlayerList

			for p = 1, #PlayerList do
				local PlayerItem = PlayerList[ p ]
				local Icon = PlayerItem.LifeformPickerIcon

				if Icon and Icon:GetIsVisible()
				and tostring( GetSteamIdForClientIndex( PlayerItem.ClientIndex ) ) == LocalSteamId
				and GUIItemContainsPoint( Icon, MouseX, MouseY ) then
					ShowLifeformMenu( Scoreboard )
					return true
				end
			end
		end
	end
end

Client.HookNetworkMessage( "LifeformPicker_State", function( Message )
	Selections[ Message.steamId ] = { lifeform = Message.lifeform, confirmed = Message.confirmed }
end )

-- Icons are conditional, so "nothing is showing" has several possible causes that look identical
-- on screen. This reports which one it is. Run `lifeformpicker_status` in the client console.
local function PrintStatus()
	local Player = Client.GetLocalPlayer()
	local Team = Player and Player:GetTeamNumber()
	local GameInfo = GetGameInfoEntity()
	local State = GameInfo and GameInfo:GetState()

	local Total, ConfirmedCount = 0, 0
	for _, Entry in pairs( Selections ) do
		Total = Total + 1
		if Entry.confirmed then ConfirmedCount = ConfirmedCount + 1 end
	end

	Print( "[LifeformPicker] hooks installed : %s", tostring( Plugin.HooksInstalled == true ) )
	Print( "[LifeformPicker] your team       : %s (need %s alien or %s spectator)",
		tostring( Team ), tostring( kTeam2Index ), tostring( kSpectatorIndex ) )
	Print( "[LifeformPicker] game state      : %s (pre-round: %s)",
		tostring( State ), tostring( State ~= nil and kPreRoundStates[ State ] == true ) )
	Print( "[LifeformPicker] icons should be : %s",
		tostring( IsPreRound() and IsLocalViewer() ) )
	Print( "[LifeformPicker] picks remembered: %d (%d confirmed, %d grey/unconfirmed)",
		Total, ConfirmedCount, Total - ConfirmedCount )
end

function Plugin:Initialise()
	self.Enabled = true

	if not self.AddedStatusCommand then
		Event.Hook( "Console_lifeformpicker_status", PrintStatus )
		self.AddedStatusCommand = true
	end

	return true
end

function Plugin:Cleanup()
	Selections = {}

	-- Ours to create, ours to destroy - unlike the shared singleton, nothing else will clean this
	-- up if the plugin is disabled or reloaded.
	if Tooltip then
		GetGUIManager():DestroyGUIScript( Tooltip )
		Tooltip = nil
	end
	TooltipText = nil
	TooltipShown = false

	self.BaseClass.Cleanup( self )
end

return Plugin
