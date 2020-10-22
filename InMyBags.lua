SLASH_JADBAGSCAN1  = "/imbscan"		--collect all inventory data
SLASH_JADBAGRESET1 = "/imbreset"	--purge all inventory data for all characters, must type 2x; there is no undo  ;)
SLASH_JADBAGLIST1  = "/imb"			--show the In My Bags window; optionally follow with a name to see only that inventory
									--    or with letters not a name for a search
									--    shift-click an inventory item to search for it

JADInMyBags = {}				-- function namespace

--You can change these names but will need to reset/rebuild the database for all characters when you do
MAIN_BANK_BAG_NAME  = "Main bank"
OTHER_BANK_BAG_NAME = "Bank bag"
BACKPACK_BAG_NAME   = "Backpack"
ON_PERSON_BAG_NAME  = "On-person bag"
KEYRING_BAG_NAME	= "Keyring"
REAGENT_BAG_NAME	= "Reagent bank"

JADrefreshCode		= "RefreshRefresh"


JADBagInventory = {}			-- SAVED VARIABLE, hold all the inventory data
JADBagAllFactionFlag = false	-- SAVED VARIABLE, show inventory across both factions (or not)
JADBagAllRealmsFlag = false		-- SAVED VARIABLE, show inventory across all realms (or not)
JADBagVersionTwoUpgrade = false -- SAVED VARIABLE, used to signal rebuild of database for 2.0
JADBagDisplay = {}				-- built each time the window is displayed
JADBankWindowOpen = 0			-- toggles whenever the bank window is opened or closed
JADBagConfirmReset = 0			-- toggles to ensure reset is entered twice
JADMatchString = ""				-- the search string, if ~= ""
JADMatchStringSafe = ""			-- set same as above but with all hyphens escaped with % characters for pattern matching
JADRememberFilterCode = ""		-- used when refreshing the list (checkbox toggled) to keep filter active
_NoErr = 0						-- named constant
JADisWoWClassic = select(4, GetBuildInfo()) < 20000


-- #####################################
-- ##      /imbscan                   ##
-- #####################################

SlashCmdList["JADBAGSCAN"] = function(msg, theEditFrame)			-- /imbscan
	local bag, slot, result, bagslots, bagstart, bagstop

	InMyBags:Hide();
		--REAGENTBANK_CONTAINER Reagent bank (-3)					
		--KEYRING_CONTAINER: Keyring and currency bag (-2)		added late in Classic
		--BANK_CONTAINER Main storage area in the bank (-1)
		--BACKPACK_CONTAINER: Backpack (0)
		--1 through NUM_BAG_SLOTS: Bag slots (as presented in the default UI, numbered right(!) to left)
		--NUM_BAG_SLOTS + 1 through NUM_BAG_SLOTS + NUM_BANKBAGSLOTS: Bank bag slots (as presented in the default UI, numbered left to right)
	if (JADBankWindowOpen > 0)  then
		bagslots = NUM_BAG_SLOTS + NUM_BANKBAGSLOTS + 3		-- includes mutually-exclusive keyring and reagent bank
		if JADisWoWClassic then
			bagstart = KEYRING_CONTAINER
		else
			bagstart = REAGENTBANK_CONTAINER					-- lowest numbered bag
		end
		bagstop = NUM_BAG_SLOTS + NUM_BANKBAGSLOTS
		result = JADInMyBags:purgeCharacterEntries("all")
	else		-- bank window is not open					-- NEW in 1.4
		bagslots = NUM_BAG_SLOTS + 2
		bagstart = KEYRING_CONTAINER
		bagstop = NUM_BAG_SLOTS		
		result = JADInMyBags:purgeCharacterEntries("nobank")
	end
	
	if (result == _NoErr) then 
		--print( "In My Bags cataloging items from "..bagslots.." containers." )
		for bag = bagstart, bagstop do
			local skip = false
			if (JADisWoWClassic and bag == REAGENTBANK_CONTAINER) then skip = true end
			if ((not JADisWoWClassic) and bag == KEYRING_CONTAINER) then skip = true end
			if (JADBankWindowOpen <= 0 and bag == BANK_CONTAINER) then skip = true end
			if (not skip) then
				--print( "Bag "..bag.." has "..GetContainerNumSlots(bag).." slots")
				for slot = 1, GetContainerNumSlots(bag) do
					local texture, count, locked, qualityBroken, readable, lootable, link = GetContainerItemInfo(bag, slot)
					local name, quality
					if texture then
						if JADisWoWClassic then
							name, link, quality = GetItemInfo(link)
			--				name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo("itemLink")
			--													   ^^ as in AH ^^
						else
							local openBracket = strfind(link,"|h")
							local closeBracket = strfind(link,"|h",openBracket+1)
							name = strsub(link,openBracket+3,closeBracket-2)
							quality = qualityBroken
							-- http://wowwiki.wikia.com/wiki/API_GetItemInfo
						end
						faction = UnitFactionGroup("player") or "None"  --UnitFactionGroup can return nil
						table.insert(JADBagInventory, {
							["name"]		= format("%q",name),
							["holder"]		= UnitName("player"),
							["realm"]		= GetRealmName(),
							["faction"]		= faction,
							["quantity"]	= count,
							["detailLink"]	= link,
							["heldIn"]		= JADInMyBags:translateBagID(bag)
							}
							)
					end
				end
			end
		end
		JADInMyBags:consolidateLikeItems(UnitName("player"), GetRealmName(), (UnitFactionGroup("player") or "None") )
		print( "In My Bags database updated. Now tracking "..#JADBagInventory.." items.")
	else
		print( "An error occured trying to reset "..UnitName("player").."'s inventory" )
	end
	JADBagConfirmReset = 0					--reset delete confirmation flag on any other command
end



-- #####################################
-- ##      /imbreset                  ##
-- #####################################

SlashCmdList["JADBAGRESET"] = function(msg, theEditFrame)		--  /imbreset
	if ( JADBagConfirmReset > 0 ) then
		JADBagInventory = {}
		ChatFrame1:AddMessage( "In My Bags inventory database reset for all characters.")
		JADBagConfirmReset = 0
	else
		ChatFrame1:AddMessage( "ARE YOU SURE?  Type "..SLASH_JADBAGRESET1.." again to confirm.",255,0,0 )
		JADBagConfirmReset = 1
	end
end



-- #####################################
-- ##      /imb                       ##
-- #####################################

SlashCmdList["JADBAGLIST"] = function(msg, theEditFrame)		--  /imb,  /imb me,  /imb Name,  /imb xxx
	local showNameList = 0
	JADMatchString = ""
	
	if (msg == "") then
		msg = nil
	elseif (msg == "me") then
		msg = UnitName("player")
		showNameList = 1
	else
		local inventorySize = #JADBagInventory
		if (inventorySize > 0 ) then
			for i = 1,inventorySize do
				if ( string.lower(JADBagInventory[i].holder) == string.lower(msg) ) then	-- did user type a stored player name?
					showNameList = 1
					i = inventorySize							-- break out of the loop
				end
			end
		end
	end
	
	if (showNameList == 1) then
		JADInMyBags:showTheList(msg)
	else
		if ( msg and string.find(msg, "Hitem") ) then			-- is not nil & is a link?
			local linkExtractStart = string.find(msg, "|h%[") + 3
			local linkExtractStop  = string.find(msg, "%]|h") - 1
			msg = string.sub(msg, linkExtractStart,  linkExtractStop)
		end
		
		JADMatchString = ( msg or "" )    -- the message, unless it's nil then make it ""
		JADInMyBags:showTheList()
	end
	JADBagConfirmReset = 0				  --reset delete confirmation flag on any other command
end


function JADInMyBags:OnLoad()
	f = InMyBags
--	frame:RegisterEvent("ADDON_LOADED")	-- ready to process saved data
	f:RegisterEvent("PLAYER_ENTERING_WORLD")	-- everything ready
	f:RegisterEvent("BANKFRAME_OPENED")	-- when the bank is opened
	f:RegisterEvent("BANKFRAME_CLOSED")	-- when the bank is closed
--	frame:RegisterEvent("BAG_OPEN")	-- when a bag is opened // no longer being sent in 4.3
--	frame:RegisterEvent("BAG_UPDATE")	-- when contents of a bag change; FUTURE OPPORTUNITY
	f:RegisterForDrag("LeftButton")
end


function JADInMyBags:OnEvent(event, arg1, ...)
	if event == "PLAYER_ENTERING_WORLD" then			-- set stuff up
		InMyBagsTitleText:SetText("In My Bags")
		InMyBagsPortrait:SetTexture("Interface\\MERCHANTFRAME\\UI-BuyBack-Icon")
		JADBankWindowOpen = 0							-- bank is always closed on /reload
		table.insert(UISpecialFrames, "InMyBags")		--makes it close with ESC key (silently)
		InMyBagsFactionCheck:SetChecked(JADBagAllFactionFlag)	-- restore user setting
		InMyBagsRealmsCheck:SetChecked(JADBagAllRealmsFlag)		-- restore user setting
		if ( JADBagVersionTwoUpgrade == false) then 
			StaticPopupDialogs["IMB_UPDATE_WARNING"] = {
			  text = "|cffbbbbffInMyBags version 2|r\n\nThe inventory database must be reset.",
			  button1 = "Reset Inventory",
			  button2 = "Disable InMyBags",
			  OnAccept = function()
				  JADBagInventory = {}
				  ChatFrame1:AddMessage( "In My Bags inventory database reset for all characters & realms.")
				  JADBagVersionTwoUpgrade = true
			  end,
			  OnCancel = function()
				  SLASH_JADBAGSCAN1  = nil	
				  SLASH_JADBAGRESET1 = nil
				  SLASH_JADBAGLIST1  = nil
			  end,
			  timeout = 0,
			  whileDead = true,
			  hideOnEscape = false,
			  preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
			}	
			StaticPopup_Show ("IMB_UPDATE_WARNING")
		end
	elseif event == "BANKFRAME_OPENED" then
		JADBankWindowOpen = 1
	elseif event == "BANKFRAME_CLOSED" then
		JADBankWindowOpen = 0
	end		
end


function JADInMyBags:translateBagID (bag)
	local itemSource
	if (bag == BANK_CONTAINER) then
		itemSource = MAIN_BANK_BAG_NAME
	elseif (bag == REAGENTBANK_CONTAINER) then
		itemSource = REAGENT_BAG_NAME
	elseif (bag == KEYRING_CONTAINER) then
		itemSource = KEYRING_BAG_NAME
	elseif (bag == BACKPACK_CONTAINER) then
		itemSource = BACKPACK_BAG_NAME
	elseif (bag <= NUM_BAG_SLOTS) then
		itemSource = ON_PERSON_BAG_NAME
	else 
		itemSource = OTHER_BANK_BAG_NAME
	end
	return itemSource
end


function JADInMyBags:purgeCharacterEntries(purgeType)
	local total = #JADBagInventory
	local playerName = UnitName("player")
	local playerRealm = GetRealmName()
	local playerFaction = UnitFactionGroup("player") or "None"
	if (total > 0) then 
		for i = #JADBagInventory, 1, -1 do		--count backwards else the list shrinks while it's counting up
			if (self:isSameOwner(JADBagInventory[i], playerName, playerRealm, playerFaction) ) then
				if (purgeType == "all") then
					table.remove(JADBagInventory, i)					-- no idea how to trap an error with this call
				else		-- "nobank"
					if 	(JADBagInventory[i].heldIn == BACKPACK_BAG_NAME or JADBagInventory[i].heldIn == ON_PERSON_BAG_NAME) then
						table.remove(JADBagInventory, i)
					end
				end
			end
		end
	end
	return _NoErr
end


function JADInMyBags:buildListForDisplay(limitTo)
	JADBagDisplay = {}		--start over; reset table
	--local countAdded = 0
	--local countAppended = 0
	local totalVendorValue = 0
	local money = 0
	local testName = nil
	local factionTexture = ""
	local distantRealm = false
	
	JADMatchStringSafe = string.gsub(string.lower(JADMatchString), "%-", "%%%-") -- hyphens cannot be used in lua find search patterns without escaping
			-- this code replaces all '-' with '%-'
	if (limitTo ~= nil) then 
		testName = string.lower(limitTo)
	end
	for i = 1 , #JADBagInventory do
		if ( (limitTo==nil) or ( string.lower(JADBagInventory[i].holder) == testName) ) then
		
			if ( JADBagAllFactionFlag or JADBagInventory[i].faction == UnitFactionGroup("player") ) then
				if ( JADBagAllRealmsFlag or JADBagInventory[i].realm == GetRealmName() ) then
					if ( (JADMatchString == "") or string.find(string.lower(JADBagInventory[i].name),JADMatchStringSafe) ) then
						displayListFoundLine = self:itemAlreadyInDisplayList(JADBagInventory[i].name)
						if (JADBagAllFactionFlag) then 
							factionTexture = self:graphicFaction(JADBagInventory[i].faction)
						end
						if ( (JADBagAllRealmsFlag) and (GetRealmName() ~= JADBagInventory[i].realm) ) then
							distantRealm = true
						else
							distantRealm = false
						end
						if ( displayListFoundLine > 0 ) then
							self:appendPlayerInventory(	displayListFoundLine,
														JADBagInventory[i].holder,
														factionTexture,
														distantRealm,
														JADBagInventory[i].quantity,
														JADBagInventory[i].heldIn
														);
							--countAppended = countAppended + 1
						else
							self:addPlayerInventory( JADBagInventory[i].name,
													 JADBagInventory[i].holder,
													 factionTexture,
													 distantRealm,
													 JADBagInventory[i].quantity,
													 JADBagInventory[i].detailLink,
													 JADBagInventory[i].heldIn
													 );
							--countAdded = countAdded + 1
						end
					end
					money = select(11, GetItemInfo(JADBagInventory[i].detailLink))		--can sometimes return nil, so...
					if (money) then
						totalVendorValue = totalVendorValue + ( money * JADBagInventory[i].quantity )
					end	
					
				end
			end
				
		end
	end
	
	table.sort(JADBagDisplay, function(item1, item2) return item1.itemName < item2.itemName end )
	
	if (JADMatchString == "") then
		InMyBagsVendor:SetText("Total vendor value:|n"..GetCoinTextureString(totalVendorValue))
	else
		InMyBagsVendor:SetText("Limiting list to:|n\""..JADMatchString.."\"")
	end	
	--	ChatFrame1:AddMessage( "build for display created "..countAdded.." lines which contained "..countAppended.." combined records." )
	return _NoErr
end
	
	
function JADInMyBags:addPlayerInventory(theName, theHolder, factionTexture, distantRealm, theQuantity, theLink, theBag)
	--local bagIcon = "|TInterface\\ICONS\\INV_Misc_Bag_08:16:16:0:1|t"
	if (distantRealm == true) then
		theHolder = "|cff999955" .. theHolder
	else
		if (theHolder == UnitName("player") ) then
			theHolder = "|cffffffdd" .. theHolder --hilight in color the current player's name and inventory
		end
	end
		
	local theTexture = select(10, GetItemInfo(theLink))			--can return nil, so...
	
	if theTexture == nil or theTexture == 0 then
		if JADisWoWClassic then
			theTexture = "|TInterface\\ICONS\\WoWUnknownItem01:0|t"
		else
			theTexture = "525134"--"|TInterface\\ICONS\\INV_Misc_QuestionMark:0|t"
		end
	end
	
	table.insert(JADBagDisplay, {
		["itemName"]	= theName,
		["icon"]		= theTexture,
		["hyperlink"]	= theLink,
		["holders"]		= factionTexture .. theHolder .. ": " .. theQuantity .. " in " .. self:graphicBag(theBag) .."|r",
				-- the |r reset is here in case of the color shift from a few lines above, otherwise ignored
		["totalCount"]	= theQuantity
		}
		)
end


function JADInMyBags:appendPlayerInventory(lineNum, theHolder, factionTexture, distantRealm, theQuantity, theBag)
	if (distantRealm == true) then
		theHolder = "|cff999955" .. theHolder
	else
		if (theHolder == UnitName("player") ) then
			theHolder = "|cffffffdd" .. theHolder 
		end
	end

	JADBagDisplay[lineNum].holders = JADBagDisplay[lineNum].holders .. ", " .. factionTexture .. theHolder .. ": " .. theQuantity .. " in " .. self:graphicBag(theBag) .."|r"
	JADBagDisplay[lineNum].totalCount = JADBagDisplay[lineNum].totalCount + theQuantity
end


function JADInMyBags:graphicBag(theBag)
	local bagTexture
	if (theBag == MAIN_BANK_BAG_NAME) then
		if JADisWoWClassic then
			bagTexture = "INV_Misc_Bag_13"							-- squarish brown backpack with red glow
		else
			bagTexture = "ACHIEVEMENT_GUILDPERK_MOBILEBANKING"		-- wooden chest opening showing gold coins
		end
	elseif (theBag == REAGENT_BAG_NAME) then
		bagTexture = "INV_Box_03"								-- large green wooden box (new in 1.5)
	elseif (theBag == KEYRING_BAG_NAME) then
		bagTexture = "INV_Misc_Key_03"
	elseif (theBag == OTHER_BANK_BAG_NAME) then
		bagTexture = "INV_Misc_Bag_10_Red"						-- plump red bag tied shut (Santa-style)
	elseif (theBag == BACKPACK_BAG_NAME) then
		bagTexture = "INV_Misc_Bag_08"							-- leather backpack with buckle
	else
		bagTexture = "INV_Misc_Bag_09_Blue"						-- blue bag attached to a belt
	end															-- Void Storage: INV_Misc_ShadowEgg
	return "|TInterface\\ICONS\\"..bagTexture..":17:17:0:0|t"..theBag
end

function JADInMyBags:graphicFaction(playerFaction)
	if ( playerFaction == "Alliance" ) then
		if JADisWoWClassic then
			return "|TInterface\\COMMON\\icon-alliance:24:24|t"
		else
			return "|TInterface\\ICONS\\Achievement_PVP_A_A:17:13|t"
		end
	elseif ( playerFaction == "Horde" ) then
		if JADisWoWClassic then
			return "|TInterface\\COMMON\\icon-horde:24:24|t"
		else
			return "|TInterface\\ICONS\\Achievement_PVP_H_H:17:13|t"
		end
	else
		return "|TInterface\\ICONS\\Spell_Nature_ElementalShields:17:13|t" -- or INV_Misc_GroupLooking
	end
end

function JADInMyBags:itemAlreadyInDisplayList(theNameSeeking)
	local foundAt = 0
	local displaySize = #JADBagDisplay
	if (displaySize > 0 ) then
		for i = 1,displaySize do
			if ( JADBagDisplay[i].itemName == theNameSeeking ) then
				foundAt = i
				i = displaySize
			end
		end
	end
	return foundAt
end


function JADInMyBags:consolidateLikeItems(playerName, playerRealm, playerFaction)
	--local startSize = #JADBagInventory
	--local playerCheckCount=0
	--local purged = 0
	local compareline = 1
	repeat
		if ( self:isSameOwner(JADBagInventory[compareline], playerName, playerRealm, playerFaction ) ) then
			--playerCheckCount = playerCheckCount + 1
			for i = #JADBagInventory, compareline+1, -1 do
				if ( self:isSameOwner(JADBagInventory[i], playerName, playerRealm, playerFaction ) ) then
					if ( JADBagInventory[i].name == JADBagInventory[compareline].name ) then
						if ( JADBagInventory[i].heldIn == JADBagInventory[compareline].heldIn ) then
							JADBagInventory[compareline].quantity = JADBagInventory[compareline].quantity + JADBagInventory[i].quantity
							table.remove(JADBagInventory, i)
							--purged = purged + 1
						end
					end
				end
			end
		end
		compareline = compareline + 1	
	until (compareline >= #JADBagInventory)
	--ChatFrame1:AddMessage( "Reduced "..playerCheckCount.." of "..playerName.." records by "..purged.." entires." )
	--ChatFrame1:AddMessage( "   JADBagInventory from "..startSize.." to "..#JADBagInventory )
	return _NoErr
end

function JADInMyBags:isSameOwner(inventoryTableItem, playerName, playerRealm, playerFaction)
	if ( (inventoryTableItem.holder == playerName) and
		 (inventoryTableItem.realm == playerRealm) and
		 (inventoryTableItem.faction == playerFaction) ) then
		return true
	else
		return false
	end
end


--**********************************************************

function JADInMyBags:showTheList(playerName)
	local testPlayerName = playerName
	if ( testPlayerName == JADrefreshCode) then
		testPlayerName = JADRememberFilterCode
	end
	self:buildListForDisplay(testPlayerName);			--create the JADBagDisplay table
	InMyBags:Show();
	JADRememberFilterCode = testPlayerName
	
	InMyBagsScrollFrameScrollBar:SetValue(1);
	if (#JADBagDisplay > 8) then
		InMyBagsScrollFrameScrollBar:SetMinMaxValues(1,#JADBagDisplay-8)
		InMyBagsScrollFrameScrollBar.scrollStep = 8;		--how much to move when clicking the up/down buttons, or mouse wheel
	else
		InMyBagsScrollFrameScrollBar:SetMinMaxValues(1,1)
		InMyBagsScrollFrameScrollBar.scrollStep = 1;
	end
	self:paintTheLines(1)
end


function JADInMyBags:paintTheLines(startLine)
	if ( startLine+8 > #JADBagDisplay) then			-- last list item never above the bottom...
		startLine = #JADBagDisplay - 8
	end
	startLine = startLine - 1
	if ( startLine < 0 ) then						-- unless it's a really short list!
		startLine = 0
	end
	
	local showName
	local quality
	local qualityColor

	for i = 1, 9 do
		if ( i+startLine <= #JADBagDisplay ) then											--in case a really short list
			showName, _, quality = GetItemInfo(JADBagDisplay[i+startLine].hyperlink);		--can return nil, so...
			if ( (showName == nil) or (quality == nil) ) then			-- had to be put in for KeyStone
				if JADisWoWClassic then
					showName = "Unknown"
				else
					local link = JADBagDisplay[i+startLine].hyperlink
					local openBracket = strfind(link,"|h")
					local closeBracket = strfind(link,"|h",openBracket+1)
					showName = strsub(link,openBracket+3,closeBracket-2)
					showName = strsub(link, 1, 10) .. showName
					--showName = "Unknown"
					--print(JADBagDisplay[i+startLine].icon)
				end
				quality = 0
			end
			qualityColor = select(4, GetItemQualityColor(quality))
			_G["InMyBagsLine0"..i.."LineIconNormalTexture" ]:SetTexture(JADBagDisplay[i+startLine].icon);
			_G["InMyBagsLine0"..i.."LineIconLineTotalCount"]:SetText(JADBagDisplay[i+startLine].totalCount);		
			_G["InMyBagsLine0"..i.."LineNameText"          ]:SetText("|c"..qualityColor..showName.."|r");
			_G["InMyBagsLine0"..i.."LineHyperlink"         ]:SetText(JADBagDisplay[i+startLine].hyperlink);  --hidden; for tooltip
			_G["InMyBagsLine0"..i.."LineHolderString"      ]:SetText(JADBagDisplay[i+startLine].holders);
		else
			_G["InMyBagsLine0"..i.."LineIconNormalTexture" ]:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag");
			_G["InMyBagsLine0"..i.."LineIconLineTotalCount"]:SetText("");		
			_G["InMyBagsLine0"..i.."LineNameText"          ]:SetText("");
			_G["InMyBagsLine0"..i.."LineHyperlink"         ]:SetText(nil);  --hidden; for tooltip
			_G["InMyBagsLine0"..i.."LineHolderString"      ]:SetText("");		
		end
	end	
end


function JADInMyBags:Item_OnMouseEnter(thisLine)
	local original = thisLine:GetName()
	-- turn InMyBagsLine0xLineIcon  into  InMyBagsLine0xLineHyperlink
	local converted = string.gsub(original, "Icon", "Hyperlink")
	if ( _G[converted]:GetText() ) then 	--not nil
		GameTooltip:SetOwner(thisLine, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(_G[converted]:GetText())
		GameTooltip:Show()
	else
		GameTooltip:Hide()
	end
end


function JADInMyBags:FrameBrowse_Update()		--can be called anytime, but always when scroll bar clicked/scrolled

	local totalItems = #JADBagDisplay;
	local scrollPosit = InMyBagsScrollFrameScrollBar:GetValue();
	local minScroll, maxScroll = InMyBagsScrollFrameScrollBar:GetMinMaxValues();
	
	if (scrollPosit > minScroll) then
		InMyBagsScrollFrameScrollBarScrollUpButton:Enable();
	else
		InMyBagsScrollFrameScrollBarScrollUpButton:Disable();
	end
	
	if (scrollPosit < maxScroll) then
		InMyBagsScrollFrameScrollBarScrollDownButton:Enable();
	else
		InMyBagsScrollFrameScrollBarScrollDownButton:Disable();
	end

	self:paintTheLines(math.floor(scrollPosit))
	
	local checkUnderMouse = GetMouseFocus():GetName();
	if ( checkUnderMouse and string.sub(checkUnderMouse,-8) == "LineIcon" ) then			--RIGHT$
		JADInMyBags:Item_OnMouseEnter(GetMouseFocus())						--update the tooltip
	end

end

function JADInMyBags:filterFaction(applyFilter)
	JADBagAllFactionFlag = not applyFilter -- saved variable
	self:showTheList(JADrefreshCode)
end

function JADInMyBags:filterRealm(applyFilter)
	JADBagAllRealmsFlag = not applyFilter -- saved variable
	self:showTheList(JADrefreshCode)
end

