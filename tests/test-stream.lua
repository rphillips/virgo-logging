--[[

Copyright 2015 The Luvit Authors. All Rights Reserved.

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

local fs = require('fs')
local uv = require('uv')
local pathJoin = require('luvi').path.join

require('tap')(function(test)
  local logger = require('..')

  local BufferLogger = logger.Logger:extend()
  function BufferLogger:initialize(options)
    logger.Logger.initialize(self, options or {})
    self:_clear()
  end

  function BufferLogger:_clear()
    self._buffer = {}
  end
  
  function BufferLogger:_write(data, encoding, callback)
    table.insert(self._buffer, data)
    callback()
  end

  test('test simple writes', function()
    local lg

    lg = BufferLogger:new()
    logger.init(lg)
    logger.nothing('All the world\'s a stage')
    logger.critical('and all the men and women merely players')
    logger.error('they have their exits and their entrances;')
    logger.warning('and one man in his time plays many parts, his')
    logger.info('acts being seven ages.')
    logger.debug('William Shakespeare')
    assert(#lg._buffer == 4)

    lg = BufferLogger:new({ log_level = logger.LEVELS['everything'] })
    logger.init(lg)
    logger.nothing('All the world\'s a stage')
    logger.critical('and all the men and women merely players')
    logger.error('they have their exits and their entrances;')
    logger.warning('and one man in his time plays many parts, his')
    logger.info('acts being seven ages.')
    logger.debug('William Shakespeare')
    assert(#lg._buffer == 6)
  end)

  test('test formatted writes', function()
    local lg, extra_str

    lg = BufferLogger:new()
    logger.init(lg)
    logger.nothingf('All the world\'s a stage')
    logger.criticalf('and all the men and women merely players')
    logger.errorf('they have their exits and their entrances;')
    logger.warningf('and one man in his time plays many parts, his')
    logger.infof('acts being seven ages.')
    logger.debugf('William Shakespeare')
    assert(#lg._buffer == 4)

    extra_str = "hello world"

    lg = BufferLogger:new({ log_level = logger.LEVELS['everything'] })
    logger.init(lg)
    logger.nothingf('All the world\'s a stage: %s', extra_str)
    logger.criticalf('and all the men and women merely players: %s', extra_str)
    logger.errorf('they have their exits and their entrances;: %s', extra_str)
    logger.warningf('and one man in his time plays many parts, his, %s', extra_str)
    logger.infof('acts being seven ages. %s', extra_str)
    logger.debugf('William Shakespeare: %s', extra_str)
    assert(#lg._buffer == 6)
    for _, line in pairs(lg._buffer) do
      assert(line:find(extra_str) > -1)
    end
  end)

  test('stdoutfile logger (stdout)', function(expect)
    local cmd, args, stdout, onRead, handle
    local count = 0

    function onRead(err, data)
      assert(err == nil)
      if data == nil then
        assert(count == 2)
        uv.close(stdout)
      else
        count = count + 1
        p(data)
      end
    end

    stdout = uv.new_pipe(false)
    cmd = uv.exepath()
    args = { pathJoin(module.dir, 'scripts', 'stdoutfile-stdout.lua') }
    p(cmd, args)
    handle = uv.spawn(cmd, {
      args = args,
      stdio = { nil, stdout}
    }, function()
      uv.close(handle)
    end)

    uv.read_start(stdout, onRead)
  end)

  test('stdoutfile logger (file)', function(expect)
    local run, filename, onRead

    filename = 'test-log.txt'

    function onRead(err, data)
      assert(err == nil)
      if data == nil then
        assert(count == 2)
        uv.close(stdout)
      else
        count = count + 1
        p(data)
      end
    end

    function run(callback)
      local handle
      handle = uv.spawn(uv.exepath(), {
        args = { pathJoin(module.dir, 'scripts', 'stdoutfile-file.lua') },
      }, function(code)
        assert(code == 0)
        uv.close(handle)
        callback()
      end)
    end

    uv.fs_unlink(filename)
    run(function()
      local data, count
      data = fs.readFileSync(filename)
      count = 0
      for line in data:gmatch("[^\r\n]+") do
        count = count + 1
        p(line)
      end
      uv.fs_unlink(filename)
      assert(count == 2)
    end)
  end)

  test('stdoutfile logger (rotate)', function(expect)
    local log, filename, onRotated, timer

    filename = 'test-log.txt'

    function onRotated() p('rotated') end
    function cleanup() uv.fs_unlink(filename) end

    cleanup()
    log = logger.StdoutFileLogger:new({path = filename})
    log:on('rotated', expect(onRotated))
    logger.init(log)
    logger.critical('message1')
    logger.rotate()
    logger.critical('message2')
    logger.critical('message3')

    timer = uv.new_timer()
    uv.timer_start(timer, 100, 0, function()
      local data, count
      data = fs.readFileSync(filename)
      count = 0
      for line in data:gmatch("[^\r\n]+") do
        count = count + 1
        p(line)
      end
      assert(count == 3)
      uv.fs_unlink(filename)
      uv.close(timer)
    end)
  end)
end)
