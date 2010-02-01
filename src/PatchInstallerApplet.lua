
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
local Popup            = require("jive.ui.Popup")
local Surface          = require("jive.ui.Surface")
local Framework        = require("jive.ui.Framework")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Task             = require("jive.ui.Task")

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

	local width,height = Framework.getScreenSize()
	if width == 480 then
		self.model = "touch"
	elseif width == 320 then
		self.model = "radio"
	else
		self.model = "controller"
	end

--	local window = Window("text_list", menuItem.text)

	if lfs.attributes("/usr/share/jive/applets") ~= nil then
		self.luadir = "/usr/share"
	else
		-- find the main lua directory
		for dir in package.path:gmatch("([^;]*)%?[^;]*;") do
		        dir = dir .. "share"
		        local mode = lfs.attributes(dir, "mode")
		        if mode == "directory" then
		                self.luadir = dir
		                break
		        end
		end
	end

	log:warn("Got lua directory: "..self.luadir)

--	local http = SocketHttp(jnt, "erlandplugins.googlecode.com", 80)
--	local http = SocketHttp(jnt, "erland.homeip.net", 80)
--	local req = RequestHttp(function(chunk, err)
--			if err then
--				log:warn(err)
--			elseif chunk then
--				log:info("GOT: "..chunk)
--				chunk = json.decode(chunk)
--				self:patchesSink(menuItem,chunk.data)
--			end
--		end,
--		'GET', "/svn/PatchInstaller/trunk/patches/patches.json")
--		'GET', "/patches.json")
--	http:fetch(req)
	local player = appletManager:callService("getCurrentPlayer")
	local server = player:getSlimServer()
	server:userRequest(function(chunk, err)
                                        if err then
                                                log:warn(err)
                                        elseif chunk then
                                                self:patchesSink(menuItem, chunk.data)
                                        end
                                end,
                                player and player:getId(),
                                { "jivepatches", 
                                  "target:" .. System:getMachine(), 
                                  "version:" .. string.match(JIVE_VERSION, "(%d%.%d)"),
                                  "optstr:user"
                          	}
                        )

	-- create animiation to show while we get data from the server
        local popup = Popup("waiting_popup")
        local icon  = Icon("icon_connecting")
        local label = Label("text", self:string("PATCHINSTALLER_FETCHING"))
        popup:addWidget(icon)
        popup:addWidget(label)
        self:tieAndShowWindow(popup)

        self.popup = popup
end

function patchesSink(self,menuItem,data)
	self.popup:hide()
	
	self.window = Window("text_list", menuItem.text)
	self.menu = SimpleMenu("menu")

	self.window:addWidget(self.menu)

	if data.item_loop then
		for _,entry in pairs(data.item_loop) do
			local isCompliant = true
			if entry.models then
				isCompliant = false
				for _,model in pairs(entry.models) do
					if model == self.model then
						isCompliant = true
					end
				end
			else
				log:debug("Supported on all models")
			end 
			if isCompliant then
				self.menu:addItem({
					text = entry.name,
					sound = "WINDOWSHOW",
					callback = function()
						self.appletwindow = self:showPatchDetails(menuItem,entry)
						return EVENT_CONSUME
					end
				})
			else
				log:debug("Skipping "..entry.name..", isn't supported on "..self.model)
			end
		end
	end

	self:tieAndShowWindow(self.window)
	return self.window
end

function showPatchDetails(self,menuItem,entry)
	local window = Window("text_list",menuItem.text)
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	local description = entry.description
	if entry.developer then
		description = description .. "\n" .. entry.developer
	end
	if entry.email then
		description = description .. "\n" .. entry.email
	end
	
	menu:setHeaderWidget(Textarea("help_text",description))
	
	local enabled = 1
	for _,item in pairs(entry.items) do
		if lfs.attributes(self.luadir.."/jive/applets/PatchInstaller.patches/"..entry.name..".patch") == nil and item.type == "original" and item.sha then
			log:debug("Checking sha of: "..self.luadir.."/"..item.file)
			local f = io.open(self.luadir.."/"..item.file, "rb")
			if f then
				local content = f:read("*all")
				f:close()
				local sha1 = sha1:new()
				sha1:update(content)
				if sha1:digest() ~= item.sha then
					log:warn("Missmatched sha on "..self.luadir.."/"..item.file)
					enabled = 0
				else
					log:debug("sha verified on "..self.luadir.."/"..item.file)
				end
			else
				log:warn("Unable to read file "..self.luadir.."/"..item.file)
				enabled = 0
			end
		end
	end

	if enabled == 1 then
		if lfs.attributes(self.luadir.."/jive/applets/PatchInstaller.patches/"..entry.name..".patch") then
			menu:addItem(
				{
					text = tostring(self:string("UNINSTALL")) .. ": " .. entry.name,
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
					text = tostring(self:string("INSTALL")) .. ": " .. entry.name,
					sound = "WINDOWSHOW",
					callback = function(event, menuItem)
						self:applyPatch(entry)
						return EVENT_CONSUME
					end
				}
			)
		end
	end
	self:tieAndShowWindow(window)
	return window
end

function applyPatch(self, entry)
	log:debug("Applying patch: "..entry.name)
        -- generate animated downloading screen
        local icon = Icon("icon_connecting")
        self.animatelabel = Label("text", self:string("DOWNLOADING"))
        self.animatewindow = Popup("waiting_popup")
        self.animatewindow:addWidget(icon)
        self.animatewindow:addWidget(self.animatelabel)
        self.animatewindow:show()

        self.task = Task("patch download", self, function()
			if self:_download(entry) then
				self:_finished(label)
			else
				self.animatewindow:hide()
				if self.appletwindow then
				        self.appletwindow:hide()
				end
				self.window:removeWidget(self.menu)
				self.window:addWidget(Textarea("help_text", tostring(self:string("PATCHINSTALLER_FAILED_TO_APPLY_PATCH")).."\n"..tostring(self:string("PATCHINSTALLER_FAILED_MOREINFO"))..":\n/tmp/PatchInstaller.rej"))
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
			if self:patching(entry.name,self.luadir.."/jive/applets/PatchInstaller.patches/"..entry.name..".patch",true) then
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
	os.execute("mkdir -p \""..self.luadir.."/jive/applets/PatchInstaller.patches\"")
	os.execute("rm -f \""..self.luadir.."/jive/applets/PatchInstaller.patches/"..entry.name..".patch\"")
	for _,item in pairs(entry.items) do
		if success then
			if (item.type == "replacement" or item.type == "patch") and item.sha and item.url then
				log:debug("Downloading and checking sha of: "..item.url)
				self.downloadedSha = nil
				self.downloaded = false
				local req = RequestHttp(self:_downloadShaCheck(), 'GET', item.url, { stream = true })
				local uri = req:getURI()
			
				local http = SocketHttp(jnt, uri.host, uri.port, uri.host)
				http:fetch(req)
		
				while not self.downloaded do
					self.task:yield()
				end

				if self.downloadedSha == nil or item.sha ~= self.downloadedSha then
					log:warn("Missmatched sha on "..item.url.." got "..self.downloadedSha)
				else
					log:debug("sha verified on "..item.url)
				end
			end

			if item.type == "replacement" and item.url then
				self.downloaded = false
				local sink = ltn12.sink.chain(zip.filter(),self:_downloadFile(self.luadir.."/"))

				local req = RequestHttp(sink, 'GET', item.url, {stream = true})
				local uri = req:getURI()

				local http = SocketHttp(jnt, uri.host, uri.port, uri.host)
				http:fetch(req)

				while not self.downloaded do
					self.task:yield()
				end
				log:debug("Finished downloading "..item.url)
			elseif item.type == "patch" and item.url then
				self.downloaded = false
				_, _, filename = string.find(item.url,"/([^/]+)$")
				local req = RequestHttp(self:_downloadPatchFile(self.luadir.."/",filename), 'GET', item.url, {stream = true})
				local uri = req:getURI()

				local http = SocketHttp(jnt, uri.host, uri.port, uri.host)
				http:fetch(req)

				while not self.downloaded do
					self.task:yield()
				end
				log:debug("Finished downloading "..item.url)
				if not self:patching(entry.name,self.luadir.."/"..filename,false) then
					success = false
				end
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
			os.execute("cat "..self.luadir.."/"..filename..">> \""..self.luadir.."/jive/applets/PatchInstaller.patches/"..name..".patch\"")
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

function _downloadFile(self, dir)
        local fh = nil

        return function(chunk)

                if chunk == nil then
                        if fh and fh ~= DIR then
                                fh:close()
                                fh = nil
                                self.downloaded = true
                                return nil
                        end

                elseif type(chunk) == "table" then

                        if fh then
                                fh:close()
                                fh = nil
                        end

                        local filename = dir .. chunk.filename

                        if string.sub(filename, -1) == "/" then
                                log:info("creating directory: " .. filename)
                                lfs.mkdir(filename)
                                fh = 'DIR'
                        else
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

