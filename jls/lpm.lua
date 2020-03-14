local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local runtime = require('jls.lang.runtime')
local event = require('jls.lang.event')
local File = require('jls.io.File')
local json = require("jls.util.json")
local HttpClient = require('jls.net.http.HttpClient')
local HttpResponseFile = require('jls.net.http.HttpResponseFile')
local ZipFile = require('jls.util.zip.ZipFile')

local Dependency = class.create(function(dependency)

	function dependency:initialize(name, version)
		self.name = name
		self.version = version
		local scope, packageName = string.match(self.name, '^@([^/]+)/(.+)$')
		if scope then
			self.packageName = packageName
			self.scope = scope
		else
			self.packageName = self.name
		end
	end

	function dependency:install(depsDir)
		local packageDir = File:new(depsDir, self.packageName)
		if not packageDir:isDirectory() then
			print('Create directory "'..packageDir:getPath()..'"')
			packageDir:mkdir()
		end
		local gitUser, gitRepo, gitCommit = string.match(self.version, '^([^/]+)/([^#]+)#?(.*)$')
		if gitUser then
			if gitCommit == '' then
				gitCommit = 'master'
			end
			local installZip = function(zipFile, packageDir)
				print('Unzip file "'..zipFile:getName()..'" to "'..packageDir:getName()..'"')
				local status, err = ZipFile.unzipTo(zipFile, packageDir, ZipFile.fileNameAdapter.newRemoveRoot())
				if not status then
					print('Fail to unzip file "'..zipFile:getName()..'" due to "'..tostring(err)..'"')
				end
			end
			local zipFile = File:new(depsDir, self.packageName..'.zip')
			if zipFile:isFile() then
				installZip(zipFile, packageDir)
				return
			end
			local gitZipUrl = 'https://github.com/'..gitUser..'/'..gitRepo..'/archive/'..gitCommit..'.zip'
			-- redirected to https://codeload.github.com/
			--local gitZipUrl = 'https://codeload.github.com/'..gitUser..'/'..gitRepo..'/zip/'..gitCommit
			local client = HttpClient:new({
				url = gitZipUrl,
				method = 'GET',
				followRedirect = true,
				response = HttpResponseFile:new(zipFile)
			})
			return client:connect():next(function()
				return client:sendReceive()
			end):next(function(response)
				print('Saved')
				client:close()
				if response:getStatusCode() == 200 then
					installZip(zipFile, packageDir)
				end
				return packageDir
			end, function(err)
				client:close()
			end)
		end
		--local file = string.match(self.version, '^file:(.+)$')
		--gzipped tarball
		--if string.match(self.version, '^https?;//.+%.zip$') then end
		return Promise.reject('Do not know how to install version '..self.version..' for "'..self.packageName..'"')
	end

end)


local command = arg[1]

if not command then
	print('Please specify a command')
	runtime.exit(22)
end

local depsDir = File:new('lua_deps')
local currDir = depsDir:getAbsoluteFile():getParentFile()
local packageFile = File:new(currDir, 'lp.json')

local package
--[[
	only name and version are mandatory
	other fields:
	dependencies, os, cpu
]]

if command == 'init' then
	local packageName = currDir:getName() or 'xyz'
	package = {
		name = packageName,
		version = '1.0.0',
		description = packageName..' package',
		author = os.getenv('USERNAME') or os.getenv('USER') or '',
		license = 'ISC'
	}
	packageFile:write(json.encode(package))
	runtime.exit(0)
end

if not packageFile:isFile() then
	print('File not found', packageFile:getName())
	runtime.exit(2)
end

package = json.decode(packageFile:readAll())

if not depsDir:isDirectory() then
	depsDir:mkdir()
end

if command == 'install' then
	local packageName = arg[2]
	local dependencies = package.dependencies or {}
	if not packageName then
		for name, version in pairs(dependencies) do
			local dependency = Dependency:new(name, version)
			dependency:install(depsDir)
		end
	end
elseif command == 'uninstall' then
	local packageName = arg[2]
	if packageName then
		local packageDir = File:new(depsDir, packageName)
		if packageDir:isDirectory() then
			packageDir:deleteRecursive()
		end
	else
		depsDir:deleteAll()
	end
elseif command == 'run' then
	local scriptName = arg[2]
	local scripts = package.scripts or {}
	if scriptName then
		local script = scripts[scriptName]
		if script then
			os.execute(script)
		else
			print('No script "'..scriptName..'"')
			runtime.exit(1)
		end
	else
		local scriptNames = tables.keys(scripts)
		table.sort(scriptNames)
		for _, scriptName in ipairs() do
			local script = scripts[scriptName]
			print('  '..scriptName)
			print('    '..script)
		end
	end
end

event:loop()
