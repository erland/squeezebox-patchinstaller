
--[[
=head1 NAME

applets.PatchInstaller.PatchInstallerMeta - Patch Installer meta-info

=head1 DESCRIPTION

See L<applets.PatchInstaller.PatchInstallerApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")
local jul           = require("jive.utils.log")
local Timer         = require("jive.ui.Timer")

local appletManager = appletManager
local jiveMain      = jiveMain
local JIVE_VERSION  = jive.JIVE_VERSION

module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end

function registerApplet(self)
	self:registerService("isPatchInstalled")
	self:registerService("patchInstallerMenu")
	self.menu = self:menuItem('appletPatchInstaller', 'advancedSettings', self:string("PATCHINSTALLER"), function(applet, ...) applet:patchInstallerMenu(...) end)
	jiveMain:addItem(self.menu)
end

function configureApplet(self)
	if self:getSettings()["_AUTOUP"] and self:getSettings()["_LASTVER"] and self:getSettings()["_LASTVER"] ~= JIVE_VERSION then
		Timer(
			5000,
			function() 
				appletManager:callService("patchInstallerMenu",{ text = self:string("PATCHINSTALLER") }, 'auto')
			end,
			true
		):start()
	end
	self:getSettings()["_LASTVER"] = JIVE_VERSION
	self:storeSettings()
end

function defaultSettings(self)
	return { _RECONLY = true,_AUTOUP = false }
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

