
-- Abstract: InMobi plugin
-- Version: 1.0
-- Sample code is MIT licensed; see https://www.coronalabs.com/links/code/license
---------------------------------------------------------------------------------------

local widget = require( "widget" )
local inMobi = require( "plugin.inMobi" )
local json = require("json")

display.setStatusBar( display.HiddenStatusBar )

local isAndroid = system.getInfo("platformName") == "Android"
local androidPlacementIds =
{
	{unitType = "banner", pid = "1478286408914"}, -- Banner
	{unitType = "interstitial", pid = "1480743237023"}, -- Interstitial (Static + Video)
	{unitType = "interstitial", pid = "1481289791433"}, -- Rewarded Video
}
local iOSPlacementIds =
{
	{unitType = "banner", pid = "1479357133568"}, -- Banner
	{unitType = "interstitial", pid = "1479986687313"}, -- Interstitial (Static + Video)
	{unitType = "interstitial", pid = "1481821101745"}, -- Rewarded Video
}
local placementIds = isAndroid and androidPlacementIds or iOSPlacementIds
local currentPlacementId = 1

-- Create the background
local background = display.newImageRect("back-whiteorange.png", display.actualContentWidth, display.actualContentHeight)
background.x = display.contentCenterX
background.y = display.contentCenterY

-- Create a text object to show the Lua listener events on screen
local statusText = display.newText(
{
	text = "",
	font = native.systemFontBold,
	fontSize = 16,
	align = "left",
	width = 320,
	height = 200,
})
statusText:setFillColor(0)
statusText.anchorX = 0
statusText.anchorY = 0
statusText.y = display.screenOriginY + 10

local processEventTable = function(event)
  local logString = json.prettify(event):gsub("\\","")
  logString = "\nPHASE: "..event.phase.." - - - - - - - - - - - -\n" .. logString
  print(logString)
  return logString
end

local function inMobiListener( event )
	statusText.text = processEventTable(event)
end

-- Init the inMobi plugin
inMobi.init(inMobiListener, {
	accountId = "652651ebf1c94d619de9a69476396f5a", -- Ingemar
	logLevel = "debug",
    hasUserConsent = true
})

-- Set the user interests
inMobi.setUserDetails(
{
	gender = {"male"},
	userInterests = {"Business", "Tech"},
	phoneAreaCode = "353",
	postCode = "xxx1",
	language = "eng",
	birthYear = 1986,
	age = 30,
	ageGroup = "18to24",
	education = "collegeOrGraduate",
	ethnicity = "caucasian",
})

-- Create a button
local changePidButton = widget.newButton(
{
	id = "changePid",
	label = "Change PID",
	width = 250,
	onRelease = function(event)
		currentPlacementId = currentPlacementId + 1
		if currentPlacementId > #placementIds then
			currentPlacementId = 1
		end

		statusText.text = string.format("Ad type: %s\nPID: %s", placementIds[currentPlacementId].unitType, placementIds[currentPlacementId].pid)
	end,
})
changePidButton.x = display.contentCenterX
changePidButton.y = statusText.y + (statusText.height) + 10
local screenOffsetX = (display.actualContentWidth - display.contentWidth) / 2

-- Create a button
local loadAdButton = widget.newButton(
{
	label = "Load Ad",
	onRelease = function(event)
		inMobi.load(placementIds[currentPlacementId].unitType, placementIds[currentPlacementId].pid, {width = display.actualContentWidth, height = 50, autoRefresh = false, refreshInterval = 120})
	end,
})
loadAdButton.x = display.contentCenterX
loadAdButton.y = changePidButton.y + changePidButton.height + loadAdButton.height * .15

-- Create a button
local showAdButton = widget.newButton(
{
	label = "Show Ad",
	onRelease = function(event)
		inMobi.show(placementIds[currentPlacementId].pid, { yAlign = "top" })
	end,
})
showAdButton.x = display.contentCenterX
showAdButton.y = loadAdButton.y + loadAdButton.height + showAdButton.height * .15

-- Create a button
local hideAdButton = widget.newButton(
{
	label = "Hide Ad",
	onRelease = function(event)
		inMobi.hide(placementIds[currentPlacementId].pid)
	end,
})
hideAdButton.x = display.contentCenterX
hideAdButton.y = showAdButton.y + showAdButton.height + hideAdButton.height * .15
