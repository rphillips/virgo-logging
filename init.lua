--[[
Copyright 2015 Virgo Agent Toolkit Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--]]
local Writable = require('stream').Writable
local fs = require('fs')
local format = require('string').format
local los = require('los')
local table = require('table')
local utils = require('utils')

-------------------------------------------------------------------------------

local reverseMap = function(t)
  local res = {}
  for k, v in pairs(t) do
    res[v] = k
  end
  return res
end

-------------------------------------------------------------------------------

local EOL

if los.type() == 'win32' then
  EOL = '\r\n'
else
  EOL = '\n'
end

local Logger = Writable:extend()

Logger.LEVELS = {
  ['nothing'] = 0,
  ['critical'] = 1,
  ['error'] = 2,
  ['warning'] = 3,
  ['info'] = 4,
  ['debug'] = 5,
  ['everything'] = 6,
}

Logger.LEVEL_STRS = {
  [1] = ' CRT: ',
  [2] = ' ERR: ',
  [3] = ' WRN: ',
  [4] = ' INF: ',
  [5] = ' DBG: ',
  [6] = ' UNK: ',
}

Logger.REVERSE_LEVELS = reverseMap(Logger.LEVELS)

function Logger:initialize(options)
  Writable.initialize(self)
  self.options = options or {}
  self.log_level = self.options.log_level or self.LEVELS['info']
  self.error_stream = self.options.error_stream
end

function Logger:rotate() end

function Logger:setLogLevel(level)
  self.log_level = level
end

function Logger:getLogLevel()
  return self.log_level
end

function Logger:_log_buf(str)
  self:write(str)
end

function Logger:_log_error_buf(str)
  if self.error_stream then self.error_stream:write(str) end
end

function Logger:_log(level, str)
  if self.log_level < level then
    return
  end

  if #str == 0 then
    return
  end

  local bufs = {}
  table.insert(bufs, os.date('%a %b %d %X %Y'))
  table.insert(bufs, self.LEVEL_STRS[level])
  table.insert(bufs, str)
  table.insert(bufs, EOL)

  bufs = table.concat(bufs)
  self:_log_buf(bufs)
  
  if level == self.LEVELS['critical'] then
    self:_log_error_buf(bufs)
  end
end

function Logger:_logf(level, fmt, ...)
  self:_log(level, format(fmt, ...))
end

-------------------------------------------------------------------------------

local FileLogger = Logger:extend()
function FileLogger:initialize(options)
  Logger.initialize(self, options)
  assert(self.options.path, "path is missing")
  self._path = self.options.path
  self._stream = fs.WriteStreamSync:new(self._path, self.options)
  self:on('finish', utils.bind(self.close, self))
end

function FileLogger:close()
  self._stream:_end()
end

function FileLogger:_write(data, callback)
  self._stream:write(data, callback)
end

function FileLogger:rotate()
  local reopenCallback
  
  function reopenCallback()
    self._stream:uncork()
    self:emit('rotated')
  end

  self._stream:cork() -- buffer writes
  self._stream:once('open', reopenCallback)
  self._stream:open() -- reopen file
end

-------------------------------------------------------------------------------

--[[
options:
  fd: {integer?} file descriptor
--]]

local StdoutLogger = Logger:extend()
function StdoutLogger:initialize(options)
  options = options or {}
  options.fd = options.fd or 1
  Logger.initialize(self, options)
  self._stream = fs.WriteStreamSync:new(nil, self.options)
end

function StdoutLogger:close()
  self._stream:_end()
end

function StdoutLogger:_write(data, callback)
  local function onWriteCallback(...)
    fs.fstatSync(self.options.fd)
    callback(...)
  end
  self._stream:write(data, onWriteCallback)
end

-------------------------------------------------------------------------------

--[[
options:
  fd: {integer?} file descriptor
--]]

local StderrLogger = Logger:extend()
function StderrLogger:initialize(options)
  options = options or {}
  options.fd = options.fd or 2
  Logger.initialize(self, options)
  self._stream = fs.WriteStreamSync:new(nil, self.options)
end

function StderrLogger:close()
  self._stream:_end()
end

function StderrLogger:_write(data, callback)
  local function onWriteCallback(...)
    fs.fstatSync(self.options.fd)
    callback(...)
  end
  self._stream:write(data, onWriteCallback)
end

-------------------------------------------------------------------------------

--[[
  Detects if a path is passed in and enables file logging, or uses stdout.
  options: {table}
    path: {string?} filepath to use logging
--]]
local StdoutFileLogger = Logger:extend()
function StdoutFileLogger:initialize(options)
  options = options or {}
  options.error_stream = options.error_stream or StderrLogger:new()
  Logger.initialize(self, options)
  if options.path then
    if not options.flags then options.flags = "a" end
    self._stream = FileLogger:new(options)
  else
    self._stream = StdoutLogger:new(options)
  end
  self._stream:on('rotated', utils.bind(self.emit, self, 'rotated'))
end

function StdoutFileLogger:close()
  self._stream:_end()
end

function StdoutFileLogger:rotate()
  self._stream:rotate()
end

function StdoutFileLogger:_write(data, callback)
  self._stream:write(data, callback)
end

-------------------------------------------------------------------------------

local function init(stream)
  for k, i in pairs(stream.LEVELS) do
    exports[k] = utils.bind(stream._log, stream, i)
    exports[k .. 'f'] = utils.bind(stream._logf, stream, i)
    exports[k:upper()] = i
  end
  exports.log = utils.bind(stream._log, stream)
  exports.logf = utils.bind(stream._logf, stream)
  exports.rotate = utils.bind(stream.rotate, stream)
  exports.instance = stream
end

-------------------------------------------------------------------------------

exports.LEVELS = Logger.LEVELS

-- Default Logger
exports.DefaultLogger = StdoutLogger:new()

-- Base Logger
exports.Logger = Logger

-- File Logger
exports.FileLogger = FileLogger

-- Stderr Logger
exports.StdoutLogger = StdoutLogger

-- Stderr File Logger
exports.StdoutFileLogger = StdoutFileLogger

-- Sets up exports[LOGGER_LEVELS] for easy logging
exports.init = init

init(exports.DefaultLogger)
