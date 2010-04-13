
--[[
=head1 NAME

applets.PathInstaller.PatchInstallerApplet - Patch installer applet

=head1 DESCRIPTION

Patch Installer is a installer tool for Squeezeplay which is used to install custom
patches upon the standard Squeezeplay source

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. PatchInstallerApplet overrides the
following methods:

=cut
--]]


-- stuff we use
local pairs, ipairs, tostring, tonumber, package,type,string = pairs, ipairs, tostring, tonumber, package, type,string

local oo               = require("loop.simple")
local os               = require("os")
local math             = require("math")
local lfs              = require("lfs")
local ltn12            = require("ltn12")
local sha1             = require("sha1")
local string           = require("jive.utils.string")
local io               = require("io")
local zip              = require("zipfilter")

local System           = require("jive.System")

local Applet           = require("jive.Applet")
local Window           = require("jive.ui.Window")
local Label            = require("jive.ui.Label")
local Textarea         = require("jive.ui.Textarea")
local Icon             = require("jive.ui.Icon")
local Checkbox         = require("jive.ui.Checkbox")
local Popup            = require("jive.ui.Popup")
local Surface          = require("jive.ui.Surface")
local Framework        = require("jive.ui.Framework")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Task             = require("jive.ui.Task")
local Timer            = require("jive.ui.Timer")

local SocketHttp       = require("jive.net.SocketHttp")
local RequestHttp      = require("jive.net.RequestHttp")
local json             = require("json")

local appletManager    = appletManager
local jiveMain         = jiveMain
local jnt              = jnt

local JIVE_VERSION     = jive.JIVE_VERSION

module(..., Framework.constants)
oo.class(_M, Applet)


----------------------------------------------------------------------------------------
-- Helper Functions
--

-- display
-- the main applet function
function patchInstallerMenu(self, menuItem, action)

	log:debug("Patch Installer")
	self.auto = action and action == 'auto'

	self:init()

	local opt = not self:getSettings()["_RECONLY"]
	self.waitingfor = 0
	for id, server in appletManager:callService("iterateSqueezeCenters") do
	        -- need a player for SN query otherwise skip SN, don't need a player for SBS
	        local player
	        if server:isSqueezeNetwork() and server:isConnected() then
	                for p in server:allPlayers() do
	                        if p ~= nil and tostring(p) ~= "ff:ff:ff:ff:ff:ff" then
	                                player = p
	                                break
	                        end
	                end
	        end
	        
	        if not server:isSqueezeNetwork() or player ~= nil then
	                log:info("sending query to ", tostring(server), " player ", tostring(player))
			server:userRequest(function(chunk,err)
					if err then
						log:warn(err)
					else
						model = System:getMachine()
						if model == "squeezeplay" then
							local width,height = Framework.getScreenSize()
							if width == 480 then
								model = "fab4"
							elseif width == 320 then
								model = "baby"
							else
								model = "jive"
							end
						end
						if tonumber(chunk.data._can) == 1 then
							server:userRequest(function(chunk, err)
								        if err then
								                log:warn(err)
								        elseif chunk then
								                self:patchesSink(server, chunk.data)
								        end
								end,
								player and player:getId(),
								{ "jivepatches", 
								  "target:" .. model, 
								  "version:" .. string.match(JIVE_VERSION, "(%d%.%d)"),
								  opt and "optstr:other|user" or "optstr:none"
							  	}
							)
							self.waitingfor = self.waitingfor + 1
						else
							log:info("Server "..tostring(server).." doesn't support patch installation")
						end
					end
				end,
				player and player:getId(),
				{'can','jivepatches', '?'}
			)
		end
	end

	self.responses = {}

        -- start a timer which will fire if one or more servers does not respond
        -- needs to be long enough for async fetch of repo by the server before it responds
        self.timer = Timer(10000,
                           function()
                                   patchesSink(self, nil)
                           end,
                           true)
        self.timer:start()

	-- create animiation to show while we get data from the server
        local popup = Popup("waiting_popup")
        local icon  = Icon("icon_connecting")
        local label = Label("text", self:string("PATCHINSTALLER_FETCHING"))
        popup:addWidget(icon)
        popup:addWidget(label)
        self:tieAndShowWindow(popup)

        self.popup = popup
end

function init(self)
	if not self.luadir then
		if lfs.attributes("/usr/share/jive/applets") ~= nil then
			self.luadir = "/usr/"
		else
			-- find the main lua directory
			for dir in package.path:gmatch("([^;]*)%?[^;]*;") do
				local luadir = dir .. "share"
				local mode = lfs.attributes(luadir, "mode")
				if mode == "directory" then
				        self.luadir = dir
				        break
				end
			end
		end

		log:debug("Got lua directory: "..self.luadir)
	end
	-- Handle upgrade scenario
	for patchname,patchversion in pairs(self:getSettings()) do
		if not string.find(patchname,"^_") then
			if lfs.attributes(self.luadir.."share/jive/applets/PatchInstaller.patches/"..patchname..".replacements") and not lfs.attributes(self.luadir.."share/jive/applets/PatchInstaller.patches/"..patchname..".replacements.patch") then
				os.execute("find \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..patchname..".replacements\" -type f > \""..self.luadir.."/activepatches.txt\"")
				if lfs.attributes(self.luadir.."/activepatches.txt")["size"] > 0 then
					log:info("Fixing installed patch state for: "..patchname)
					os.execute("echo \""..patchversion.."\" > \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..patchname..".replacements.patch\"")
				else
					log:info("Removing empty directories for broken patch backup: "..patchname)
					os.execute("rm -rf \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..patchname..".replacements\"")
				end
				os.execute("rm -f \""..self.luadir.."/activepatches.txt\"")
			end
		end
	end
end

function isPatchInstalled(self,patchname)
	self:init()
	if lfs.attributes(self.luadir.."share/jive/applets/PatchInstaller.patches/"..patchname..".patch") or lfs.attributes(self.luadir.."share/jive/applets/PatchInstaller.patches/"..patchname..".replacements.patch") then
		if self:getSettings()[patchname] then
			return true
		end
	end
	return false
end

function patchesSink(self,server,data)
        if server ~= nil then
                -- stash response & wait until all responses received
                log:info("reponse received from ", tostring(server));
                self.responses[#self.responses+1] = { server = server, data = data }
                self.waitingfor = self.waitingfor - 1
        else
                -- timer called sink, give up waiting for more
                log:info("timeout waiting for response")
                self.waitingfor = 0
        end
                
        if self.waitingfor ~= 0 then
                return
        end

        -- kill the timer 
        self.timer:stop()

        -- use the response with the most entries
        data, server = nil, nil
        for _, response in pairs(self.responses) do
		log:debug("Checking response from "..tostring(response.server).." with "..tostring(response.data.count))
                if data == nil or data.count == nil or tonumber(data.count) < tonumber(response.data.count) then
			log:debug("Storing response from "..tostring(response.server))
                        data = response.data
                        server = response.server
                end
        end

	if self.window and self.menu then
		self.window:removeWidget(self.menu)
		self.window:hide()
	end
	if server then
		self.window = Window("text_list", tostring(self:string("PATCHINSTALLER")).." ("..server.name..")")
	else
		self.window = Window("text_list", tostring(self:string("PATCHINSTALLER")))
	end
	self.menu = SimpleMenu("menu")

	self.menu:setComparator(SimpleMenu.itemComparatorWeightAlpha)
        self.menu:setHeaderWidget(Textarea("help_text", self:string("PATCHINSTALLER_WARN")))
	self.window:addWidget(self.menu)

	self.reinstallList = nil

	local idx = 0
	if data and data.item_loop then
		for _,entry in pairs(data.item_loop) do
			local checked = false
			if lfs.attributes(self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".patch") or lfs.attributes(self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".replacements.patch") then
				checked = true
			end
			if self:getSettings()[entry.name] and not checked then
				self.reinstallList = self.reinstallList or {}
				self.reinstallList[idx] = entry
				idx = idx + 1
			end
			self.menu:addItem({
				text = entry.title,
				style = 'item_choice',
				check = Checkbox("checkbox",
				        function(object, isSelected)
						self.appletwindow = self:showPatchDetails(entry.title,entry)
						return EVENT_CONSUME
				        end,
				        checked
				),
				weight = 2
			})
		end
	end

        if self.menu:numItems() == 0 then
                self.menu:addItem( {
                        text = self:string("PATCHINSTALLER_NONE_FOUND"), 
                        iconStyle = 'item_no_arrow',
                        weight = 2
                })
	elseif self.reinstallList then
		self.menu:addItem({
				text = self:string("PATCHINSTALLER_REINSTALL_ALL"),
				callback = function(object, menuItem)
						self:applyPatch(self.reinstallList)
						return EVENT_CONSUME
					end,
				weight = 1
			})
        end
	self.menu:addItem({
		        text = self:string("PATCHINSTALLER_RECONLY"),
		        style = 'item_choice',
		        check = Checkbox("checkbox",
		                function(object, isSelected)
		                        self:getSettings()["_RECONLY"] = isSelected
		                        self:storeSettings()
					self:patchInstallerMenu()
		                end,
		                self:getSettings()["_RECONLY"]
		        ),
		        weight = 3
		})
	self.menu:addItem({
		        text = self:string("PATCHINSTALLER_AUTOUPGRADE"),
		        style = 'item_choice',
		        check = Checkbox("checkbox",
		                function(object, isSelected)
		                        self:getSettings()["_AUTOUP"] = isSelected
		                        self:storeSettings()
		                end,
		                self:getSettings()["_AUTOUP"]
		        ),
		        weight = 4
		})



	self.popup:hide()

	self:tieAndShowWindow(self.window)
	if self.auto and self.reinstallList then
		self:applyPatch(self.reinstallList)
	end
	return self.window
end

function showPatchDetails(self,title,entry)
	local window = Window("text_list",title)
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	local description = entry.desc
	if entry.creator then
		description = description .. "\n" .. tostring(self:string("PATCHINSTALLER_CREATED_BY"))..": "..entry.creator
	end
	if entry.email then
		description = description .. "\n" .. entry.email
	end
	
	menu:setHeaderWidget(Textarea("help_text",description))
	

	if lfs.attributes(self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".patch") or lfs.attributes(self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".replacements.patch") then
		menu:addItem(
			{
				text = tostring(self:string("PATCHINSTALLER_UNINSTALL")),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:revertPatch(entry)
					return EVENT_CONSUME
				end
			}
		)
	else
		menu:addItem(
			{
				text = tostring(self:string("PATCHINSTALLER_INSTALL")),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					local entries = {}
					entries[0] = entry
					self:applyPatch(entries)
					return EVENT_CONSUME
				end
			}
		)
	end
	self:tieAndShowWindow(window)
	return window
end

function applyPatch(self, entries)
        -- generate animated downloading screen
        local icon = Icon("icon_connecting")
        self.animatelabel = Label("text", self:string("DOWNLOADING"))
        self.animatewindow = Popup("waiting_popup")
        self.animatewindow:addWidget(icon)
        self.animatewindow:addWidget(self.animatelabel)
        self.animatewindow:show()

        self.task = Task("patch download", self, function()
			local success = true
			local shaProblem = false
			for _, entry in pairs(entries) do
				log:debug("Applying patch: "..entry.name)
				if self:_download(entry) then
					self:getSettings()[entry.name] = entry.version
			                self:storeSettings()
				else 
					if self.downloadedSha == nil or (entry.sha and entry.sha ~= self.downloadedSha) then
						log:warn("Failed verifying sha checksum for: "..entry.name)
						shaProblem = true
					else
						log:warn("Failed applying patch: "..entry.name)
					end
					success = false
					break
				end
			end

			if success then
				self:_finished(label)
			else
				self.animatewindow:hide()
				if self.appletwindow then
				        self.appletwindow:hide()
				end
				self.window:removeWidget(self.menu)
				if shaProblem then
					self.window:addWidget(Textarea("help_text", self:string("PATCHINSTALLER_FAILED_VERIFY_SHA")))
				else
					self.window:addWidget(Textarea("help_text", tostring(self:string("PATCHINSTALLER_FAILED_TO_APPLY_PATCH")).."\n"..tostring(self:string("PATCHINSTALLER_FAILED_MOREINFO"))..":\n/tmp/PatchInstaller.rej"))
				end
			end
		end)

        self.task:addTask()
end

function revertPatch(self, entry)
	log:debug("Reverting patch: "..entry.name)
        -- generate animated downloading screen
        local icon = Icon("icon_connecting")
        self.animatelabel = Label("text", self:string("PATCHING"))
        self.animatewindow = Popup("waiting_popup")
        self.animatewindow:addWidget(icon)
        self.animatewindow:addWidget(self.animatelabel)
        self.animatewindow:show()

        self.task = Task("patch download", self, function()
			local success = true
			if lfs.attributes(self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".patch") then
				if self:patching(entry.name,self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".patch",true) then
					os.execute("rm -f \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".patch\"")
				else
					success = false
				end
			end
			if success and lfs.attributes(self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".replacements") then
				os.execute("cp -r \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".replacements/\"* "..self.luadir)
				os.execute("rm -rf \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".replacements\"")
				os.execute("rm -f \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".replacements.patch\"")
			end

			if success then
				self:getSettings()[entry.name] = nil
	                        self:storeSettings()
				self:_finished(label)
			else
				self.animatewindow:hide()
				if self.appletwindow then
				        self.appletwindow:hide()
				end
				self.window:removeWidget(self.menu)
				self.window:addWidget(Textarea("help_text", tostring(self:string("PATCHINSTALLER_FAILED_TO_REVERT_PATCH")).."\n"..tostring(self:string("PATCHINSTALLER_FAILED_MOREINFO"))..":\n/tmp/PatchInstaller.rej"))
			end
		end)

        self.task:addTask()
end

-- called when download / removal is complete
function _finished(self, label)
        if lfs.attributes("/bin/busybox") ~= nil then
                self.animatelabel:setValue(self:string("RESTART_JIVE"))
                -- two second delay
                local t = Framework:getTicks()
                while (t + 2000) > Framework:getTicks() do
                        Task:yield(true)
                end
                log:info("RESTARTING JIVE...")
                appletManager:callService("reboot")
        else
                self.animatewindow:hide()
                if self.appletwindow then
                        self.appletwindow:hide()
                end
                self.window:removeWidget(self.menu)
                self.window:addWidget(Textarea("help_text", self:string("PATCHINSTALLER_RESTART_APP")))
        end
end

function _download(self,entry)
	local success = true
	os.execute("mkdir -p \""..self.luadir.."share/jive/applets/PatchInstaller.patches\"")
	if string.find(entry.url,"%.zip") then
		os.execute("rm -rf \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".replacements\"")
		os.execute("rm -f \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".replacements.patch\"")
		os.execute("mkdir -p \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".replacements\"")
	end
	os.execute("rm -f \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".patch\"")

	self.downloadedSha = false
	if entry.sha then
		log:debug("Downloading "..entry.url.." ...")
		self.downloaded = false
		local req = RequestHttp(self:_downloadShaCheck(), 'GET', entry.url, {stream = true})
		local uri = req:getURI()
		
		local http = SocketHttp(jnt, uri.host, uri.port, uri.host)
		http:fetch(req)

		while not self.downloaded do
			self.task:yield()
		end
		
		if self.downloadedSha == nil or entry.sha ~= self.downloadedSha then
			log:warn("Mismatched sha on "..entry.url.." got "..self.downloadedSha.." expected "..entry.sha)
			success = false
		else
			log:debug("Downloaded and verified sha on "..entry.url)
		end
	end

	if success and string.find(entry.url,"%.zip") then
		self.downloaded = false
		local sink = ltn12.sink.chain(zip.filter(),self:_downloadFile(self.luadir,self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".replacements"))

		local req = RequestHttp(sink, 'GET', entry.url, {stream = true})
		local uri = req:getURI()

		local http = SocketHttp(jnt, uri.host, uri.port, uri.host)
		http:fetch(req)

		while not self.downloaded do
			self.task:yield()
		end
		if lfs.attributes(self.luadir.."/"..entry.name..".patch") ~= nil then
			if not self:patching(entry.name,self.luadir.."/"..entry.name..".patch",false) then
				success = false
			end
		end
		if success then
			os.execute("echo \""..entry.version.."\" > \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..entry.name..".replacements.patch\"")
		end
		os.execute("rm -f /tmp/PatchInstallerAbout.rej")
		os.execute("patch -p0 --forward -t --dry-run --global-reject-file=/tmp/PatchInstallerAbout.rej -d "..self.luadir.." < \""..self.luadir.."share/jive/applets/PatchInstaller/about.patch\"")
		if lfs.attributes("/tmp/PatchInstallerAbout.rej") == nil then
			os.execute("patch -p0 --forward -t -d "..self.luadir.." < \""..self.luadir.."share/jive/applets/PatchInstaller/about.patch\"")
		end
		log:debug("Finished downloading "..entry.url)
	elseif success and string.find(entry.url,"%.patch") then
		self.downloaded = false
		local req = RequestHttp(self:_downloadPatchFile(self.luadir.."/",entry.name..".patch"), 'GET', entry.url, {stream = true})
		local uri = req:getURI()

		local http = SocketHttp(jnt, uri.host, uri.port, uri.host)
		http:fetch(req)

		while not self.downloaded do
			self.task:yield()
		end
		log:debug("Finished downloading "..entry.url)
		if not self:patching(entry.name,self.luadir.."/"..entry.name..".patch",false) then
			success = false
		else
			os.execute("rm -f /tmp/PatchInstallerAbout.rej")
			os.execute("patch -p0 --forward -t --dry-run --global-reject-file=/tmp/PatchInstallerAbout.rej -d "..self.luadir.." < \""..self.luadir.."share/jive/applets/PatchInstaller/about.patch\"")
			if lfs.attributes("/tmp/PatchInstallerAbout.rej") == nil then
				os.execute("patch -p0 --forward -t -d "..self.luadir.." < \""..self.luadir.."share/jive/applets/PatchInstaller/about.patch\"")
			end
		end
	end
	return success
end

function patching(self,name,patchfile,revert) 
	log:debug("Verify patch... ")
	os.execute("rm -f /tmp/PatchInstaller.rej")
	if revert then
		os.execute("patch -p0 --reverse -t --dry-run --global-reject-file=/tmp/PatchInstaller.rej -d "..self.luadir.." < \""..patchfile.."\"")
	else
		os.execute("patch -p0 --forward -t --dry-run --global-reject-file=/tmp/PatchInstaller.rej -d "..self.luadir.." < \""..patchfile.."\"")
	end
	if lfs.attributes("/tmp/PatchInstaller.rej") == nil then
		log:debug("Patching... ")
		if revert then
			os.execute("patch -p0 --reverse -t -d "..self.luadir.." < \""..patchfile.."\"")
		else
			os.execute("patch -p0 --forward -t -d "..self.luadir.." < \""..patchfile.."\"")
			os.execute("cat \""..patchfile.."\">> \""..self.luadir.."share/jive/applets/PatchInstaller.patches/"..name..".patch\"")
		end
		os.execute("rm -f \""..patchfile.."\"")
		log:debug("Patching finished")
		return true
	end
	return false
end
-- sink for writing out files once they have been unziped by zipfilter
function _downloadPatchFile(self, dir, filename)
        local fh = nil

        return function(chunk)
                if chunk == nil then
                        if fh and fh ~= DIR then
                                fh:close()
                                fh = nil
                                self.downloaded = true
                                return nil
                        end

                else
                        if fh == nil then
	                        fh = io.open(dir .. filename, "w")
                        end

                        fh:write(chunk)
                end

                return 1
        end
end

function _downloadFile(self, dir, backupdir)
        local fh = nil

        return function(chunk)

                if chunk == nil then
                        if fh and fh ~= 'DIR' then
                                fh:close()
                        end
                        fh = nil
                        self.downloaded = true
                        return nil

                elseif type(chunk) == "table" then

                        if fh and fh ~= 'DIR' then
		                fh:close()
			end
                        fh = nil

                        local filename = dir .. chunk.filename
                        if string.sub(filename, -1) == "/" then
                                log:info("creating directory: " .. filename)
                                lfs.mkdir(filename)
                                fh = 'DIR'
                        else
				if lfs.attributes(filename) ~= nil then
					if lfs.attributes(filename)["size"] and lfs.attributes(filename)["size"]<204800 then
						local dir = string.gsub(chunk.filename,"/[^/]+$","/")
						os.execute("mkdir -p \""..backupdir.."/"..dir.."\"")
						os.execute("cp \""..filename.."\" \""..backupdir.."/"..chunk.filename.."\"")
					else
						os.execute("mkdir -p \""..backupdir.."\"")
					end
				end
                                log:info("extracting file: " .. filename)
                                fh = io.open(filename, "w")
                        end

                else
                        if fh == nil then
                                return nil
                        end

                        if fh ~= 'DIR' then
                                fh:write(chunk)
                        end
                end

                return 1
        end
end

function _downloadShaCheck(self)
	local sha = sha1:new()

	return function(chunk)
		if chunk == nil then
			self.downloaded = true
			self.downloadedSha = sha:digest()
			return nil
		end
		sha:update(chunk)
	end
end

--[[

=head1 LICENSE

Copyright 2010, Erland Isaksson (erland_i@hotmail.com)
Copyright 2010, Logitech, inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Logitech nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL LOGITECH, INC BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
--]]

