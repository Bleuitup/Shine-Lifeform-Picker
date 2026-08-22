-- Shine Lifeform Picker
-- lua/shine/extensions/lifeformpicker/client.lua
--
-- Draws a lifeform icon on each alien scoreboard row during the pre-round, and lets you click
-- your own icon to declare what you intend to play.
--
-- The scoreboard is reached with Shine.Hook.SetupClassHook rather than a ModLoader file hook.
-- That matters for compatibility: mods such as Shimizu Scoreboard claim lua/GUIScoreboard.lua in
-- "replace" mode, and a second mod hooking the same file fights it. Patching the class methods at
-- runtime leaves the file untouched, so this coexists with whatever owns it.

local Plugin = ...

local kAtlas = PrecacheAsset( "ui/LifeformPicker/Alien.dds" )

-- Alien.dds is a 340x1824 vertical strip of 340x114 cells, one lifeform per row, in the same
-- order as Plugin.kLifeforms.
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

-- The artwork is pure white with the shape carried entirely in the alpha channel, so it is drawn
-- at plain full opacity and the texture's own transparency does all the work. No tinting, and no
-- visual distinction between a declared pick and the assumed Skulk default.
local kIconColour = Color( 1, 1, 1, 1 )

-- Everything before the round is live. Note this is a set rather than a single comparison: a
-- match passes through NotStarted, WarmUp, PreGame and Countdown, and testing only for WarmUp
-- (as the old mod does) makes the icons vanish exactly when the round is about to begin.
local kPreRoundStates = {
	[ kGameState.NotStarted ] = true,
	[ kGameState.WarmUp ] = true,
	[ kGameState.PreGame ] = true,
	[ kGameState.Countdown ] = true
}

-- [ steamId string ] = lifeform index, as replicated by the server.
local Selections = {}

local function IsPreRound()
	local GameInfo = GetGameInfoEntity()
	return GameInfo ~= nil and kPreRoundStates[ GameInfo:GetState() ] == true
end

local function IsLocalViewer()
	local Player = Client.GetLocalPlayer()
	local Team = Player and Player:GetTeamNumber()
	return Team == kTeam2Index or Team == kSpectatorIndex
end

-- GetSteamIdForClientIndex returns nil until the player's PlayerInfoEntity has replicated, so the
-- tostring() here can legitimately produce "nil". That simply misses the table and falls back to
-- the Skulk default, which is the correct thing to show anyway.
local function GetLifeformFor( ClientIndex )
	return Selections[ tostring( GetSteamIdForClientIndex( ClientIndex ) ) ] or Plugin.kDefaultLifeform
end

local function EnsureIcon( PlayerItem )
	local Icon = PlayerItem.LifeformPickerIcon
	if Icon then return Icon end

	Icon = GUIManager:CreateGraphicItem()
	Icon:SetAnchor( GUIItem.Left, GUIItem.Center )
	Icon:SetTexture( kAtlas )
	Icon:SetColor( kIconColour )
	Icon:SetStencilFunc( GUIItem.NotEqual )
	Icon:SetIsVisible( false )
	PlayerItem.Background:AddChild( Icon )

	PlayerItem.LifeformPickerIcon = Icon
	return Icon
end

Shine.Hook.SetupClassHook( "GUIScoreboard", "Update", "OnLifeformPickerScoreboardUpdate", "PassivePost" )

function Plugin:OnLifeformPickerScoreboardUpdate( Scoreboard )
	if not Scoreboard.teams then return end

	local Show = IsPreRound() and IsLocalViewer()
	local Scale = GUIScoreboard.kScalingFactor

	for i = 1, #Scoreboard.teams do
		local Team = Scoreboard.teams[ i ]
		local IsAlienTeam = Team.TeamNumber == kTeam2Index
		local PlayerList = Team.PlayerList

		for p = 1, #PlayerList do
			local PlayerItem = PlayerList[ p ]
			local Icon = EnsureIcon( PlayerItem )

			-- Every row is touched on every pass, including marine and ready-room rows. Player
			-- items are pooled and recycled between teams, so a row that used to belong to an
			-- alien can reappear on the marine list; setting visibility unconditionally here is
			-- what stops it carrying its old icon across, and removes any need to also hook
			-- ResizePlayerList.
			if Show and IsAlienTeam then
				local Index = GetLifeformFor( PlayerItem.ClientIndex )

				-- Positioned off the Status column rather than from hard-coded column maths, so
				-- it tracks resolution changes and scoreboard width changes on its own.
				local StatusPos = PlayerItem.Status:GetPosition()

				Icon:SetSize( Vector( kIconWidth, kIconHeight, 0 ) * Scale )
				Icon:SetPosition( Vector( StatusPos.x - ( kIconWidth + kIconGap ) * Scale,
					-kIconHeight * 0.5 * Scale, 0 ) )
				Icon:SetTexturePixelCoordinates( kCropLeft, kCellHeight * Index,
					kCropRight, kCellHeight * ( Index + 1 ) )
				Icon:SetIsVisible( true )
			else
				Icon:SetIsVisible( false )
			end
		end
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

	for i = 1, #Plugin.kLifeforms do
		-- Captured per iteration so each button sends its own index.
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
end

-- ActivePre: returning a non-nil value skips vanilla's handler entirely and returns that value.
-- Returning true on a hit therefore claims the click, so the vanilla Steam-profile/mute menu does
-- not also open on top of the lifeform menu. Returning nothing lets vanilla proceed untouched.
Shine.Hook.SetupClassHook( "GUIScoreboard", "SendKeyEvent", "OnLifeformPickerScoreboardKey", "ActivePre" )

function Plugin:OnLifeformPickerScoreboardKey( Scoreboard, Key, Down )
	if Key ~= InputKey.MouseButton0 or not Down then return end
	if not Scoreboard.visible or Scoreboard.hiddenOverride then return end
	if not MouseTracker_GetIsVisible() or MainMenu_GetIsOpened() then return end
	if not IsPreRound() then return end

	local Menu = Scoreboard.hoverMenu
	if not Menu or Menu.background:GetIsVisible() then return end

	-- Spectators can see declarations but cannot make them, and you may only declare for
	-- yourself, so only your own row responds to a click.
	local Player = Client.GetLocalPlayer()
	if not Player or Player:GetTeamNumber() ~= kTeam2Index then return end

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
	Selections[ Message.steamId ] = Message.lifeform
end )

function Plugin:Initialise()
	self.Enabled = true
	return true
end

function Plugin:Cleanup()
	Selections = {}
	self.BaseClass.Cleanup( self )
end

return Plugin
