--// pyxfluff 2024

local AR = { Ranks = {} }

--// Dependencies
local Var = require(script.Parent.Parent.Core.Variables)
local Util = require(script.Parent.Utilities)
local Config = require(script.Parent.Parent.Core.Configuration)

--// Locals
local LastAdminResult

function AR.Bootstrap(
	Player:        Player,
	AdminRankID:   number
): ()
	local Rank = Var.DataStores.AdminsDS:GetAsync(`_Rank{AdminRankID}`)
	local NewPanel = Var.Panel.Spawn(Rank, Player)
	local AllowedPages = {}

	table.insert(Var.Admins.InGame, Player)
	Var.Admins.TotalRunningCount += 1

	for i, v in Rank["AllowedPages"] do
		AllowedPages[v["Name"]] = {
			["Name"] = v["DisplayName"], 
			["ButtonName"] = v["Name"]
		}
	end

	if Rank.PagesCode ~= "*" then
		for _, v in NewPanel.Main.Apps.MainFrame:GetChildren() do
			if not v:IsA("CanvasGroup") then continue end
			if table.find({'Home', 'Template'}, v.Name) then continue end --// Always allowed

			pcall(function()
				xpcall(function()
					if AllowedPages[v.Name] == nil then
						Util.Logging.Print("Not allowed by rank (i think)")

						for i, Page in NewPanel.Main:GetChildren() do
							if Page:GetAttribute("LinkID") == v:GetAttribute("LinkID") then
								Page:Destroy()
							end
						end

						v:Destroy()
					end
				end, function(r)
					Util.Logging.Warn(`Failed performing permission checks on {v.Name}! `)
				end)
			end)
		end
	end

	Util.NewNotification(
		Player, 
		`{Config.Name} loaded! You're a{string.split(string.lower(Rank.RankName), "a")[1] == "" and "n" or ""} {Rank.RankName}. {
		`Press {Util.GetSetting("RequireShift") and "Shift + " or ""}{Util.GetSetting("PanelKeybind")} to enter the panel.`
		}`,
		"Welcome to Administer!", 
		"rbxassetid://16105499426", 15,	nil, {}
	)
end

function AR.PlayerAdded(
	Player:        Player,
	ForceAdmin:    boolean,
	IsScan:        boolean
): {Success: boolean, Message: string}
	LastAdminResult = Util.IsAdmin(Util, Player)
	if Var.LogJoins then
		table.insert(Var.AdminsBootstrapped, Player)
	end

	if Var.WaitForBootstrap then
		repeat task.wait(.1) until Var.DidBootstrap
	end

	if IsScan and table.find(Var.Admins.InGame, Player) and not Var.DisableBootstrapProtection then
		return {false, "This person is already an admin and by default cannot be bootstrapped twice. Change this in the configuration module."}
	end

	task.spawn(function()
		if LastAdminResult.IsAdmin then
			AR.Bootstrap(
				Player,
				LastAdminResult["RankID"]
			)
		elseif (Var.Services.RunService:IsStudio() and Util.GetSetting("SandboxMode")) or Var.EnableFreeAdmin or ForceAdmin then
			AR.Bootstrap(
				Player,
				1
			)
		end
	end)

	return {true, "Done"}
end

function AR.Removing(
	Player: Player
): ()
	if table.find(Var.Admins.InGame, Player) ~= nil then
		table.remove(Var.Admins.InGame, table.find(Var.Admins.InGame, Player))
		table.insert(Var.Admins.OutOfGame, Player)
	end
end

function AR.Scan(
	ForceAdmin: boolean
): ()
	for _, Player: Player in Var.Services.Players:GetPlayers() do
		AR.PlayerAdded(Player, ForceAdmin, true)
	end
end

function AR.Ranks.New(Data: {
	Name: string, 
	Protected: boolean, 
	Members: {
		{
			ID: number,
			MemberType: "User" | "Group",
			GroupRank: number?
		}
	}, 
	PagesCode: string, --// TODO: REMOVE
	AllowedApps: {
		SuperAdmin: boolean?,

		[AppClass]: {
			PageLinkID: string,
			Commands: {string}?
		}		
	}, 
	CreationReason: string, 
	ActingUser: number, 

	RankID: number?, 
	IsEdit: boolean?
}): {Success: boolean, Message: string}
	if Var.DataStores.AdminsDS:GetAsync("HasMigratedToV2") == false then
		return {false, "Sorry, but you may not create new ranks before updating to Ranks V2."}
	elseif Data.PagesCode ~= nil then
		return {false, "STOP SENDING PAGESCODE ITS GONNA BE GONE SOON"}
	end
	
	Util.Logging.Print("[-] Making a new admin rank...")
	local Start = os.clock()

	xpcall(function()
		local ShouldStep = false
		local OldRankData = nil
		local NewRank = Var.DefaultRank
		local Info = Var.DataStores.AdminsDS:GetAsync("CurrentRanks") or Var.DefaultRankData

		if not Data.RankID or Data.RankID == 0 then
			Data.RankID = Info.Count
			ShouldStep = true
		end

		if Data.IsEdit then
			OldRankData = Var.DataStores.AdminsDS:GetAsync(`_Rank{Data.RankID}`)
		end

		NewRank.RankID = Data.RankID
		NewRank.RankName = Data.Name
		NewRank.Protected = Data.Protected
		NewRank.Modififd = os.time()
		NewRank.CreatorID = Data.ActingUser

		NewRank.Members = Data.Members
		NewRank.Apps = Data.AllowedApps

		table.insert(NewRank.Modifications, {
			Reason = "Made a new rank through the rank editor.",
			ActingAdmin = Data.ActingUser,
			Actions = {"made this rank"}
		})

		Var.DataStores.AdminsDS:SetAsync(`_Rank{Data.RankID}`, NewRank)

		for i, v in Data.Members do
			if v.MemberType == "User" then
				if Info.AdminIDs == nil then
					Info.AdminIDs = {}	
				end

				Info.AdminIDs[v.ID] = {
					UserID = v.ID,
					AdminRankID = Data.RankID,
					AdminRankName = Data.Name
				}
			else
				Info.GroupAdminIDs[`{v.ID}_{Var.Services.HttpService:GenerateGUID(false)}`] = { --// Identify groups differently because we may have the same group multiple times
					GroupID = v.ID,
					RequireRank = v.GroupRank ~= 0,
					RankNumber = v.GroupRank,
					AdminRankID = Data.RankID,
					AdminRankName = Data.Name
				}
			end
		end

		if ShouldStep then
			Info.Count = Data.RankID + 1
			Info.Names = Info.Names or {}
			table.insert(Info.Names, Data.Name)
		end

		Var.DataStores.AdminsDS:SetAsync("CurrentRanks", {
			Count = Info.Count,
			Names = Info.Names,
			GroupAdminIDs = Info.GroupAdminIDs,
			AdminIDs = Info.AdminIDs
		})
	end, function(E)
		Util.Logging.Warn(`Failed to create a new admin rank! {E}`)
		return {false, E}
	end)

	xpcall(function()
		Var.Services.MessagingService:PublishAsync("Administer", {["Action"] = "ForceAdminCheck"})
	end, function(e)
		Util.Logging.Warn(`[X] Failed to publish MessagingService action: ForceAdminCheck! {e}`)
		return {false, `We made the rank fine, but failed to publish the event to tell other servers to check. Please try freeing up some MessagingService slots (disabling other apps, removing other admin systems, etc). {e}`}
	end)
	
	Util.Logging.Print(`[✓] Done in {os.clock() - Start}`)
	return {true, `Success in {os.clock() - Start}s!`}
end

function AR.Ranks.GetAll()
	local Count = Var.DataStores.AdminsDS:GetAsync("CurrentRanks")
	local Ranks = {}
	local Polls = 0

	--// Load in parallel
	for i = 1, tonumber(Count["Count"]) do
		task.spawn(function()
			Ranks[i] = Var.DataStores.AdminsDS:GetAsync("_Rank"..i)
		end)
	end

	repeat 
		Polls += 1
		task.wait(.05) 
		Util.Logging.Debug("RANK CHECK", #Ranks / Count["Count"], Ranks, Count, Polls) 
	until #Ranks == Count["Count"] or Polls == 7

	if Polls == 7 then
		Util.Logging.Warn(`Only managed to load {#Ranks / Count["Count"]}% of ranks, possibly corrupt rank exists!`)
	end

	return Ranks
end


return AR