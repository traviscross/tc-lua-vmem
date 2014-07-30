-- Copyright (c) 2014 Travis Cross <tc@traviscross.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

require "ivrlib-micro"
require "tc-util"

-- record_greeting

icb_k=nil
icb_d=nil

function icb_break_on_any_dtmf(s,dtype,data)
  if dtype=="dtmf" then return "break" end end

function icb_record_review(s,dtype,data,arg)
  local file=arg.file
  if dtype=="dtmf" then
    if data.digit=="1" then
      icb_k=
        function()
          icb_k=nil
          session:streamFile(file)
          return record_review(file,3)
        end
      return "break"
    elseif data.digit=="2" then
      icb_k=
        function()
          icb_k=nil
          session:streamFile("voicemail/vm-saved.wav")
          session:sleep(1000)
          session:streamFile("voicemail/vm-goodbye.wav")
          return session:hangup()
        end
      return "break"
    elseif data.digit=="3" then
      icb_k=
        function()
          icb_k=nil
          return record_greeting(file)
        end
      return "break"
    end
  end
end

function record_review(file,i)
  icb_d={file=file}
  session:setInputCallback("icb_record_review","icb_d")
  session:sayPhrase("voicemail_record_file_check","1:2:3","en")
  if icb_k then return icb_k() end
  session:sleep(3000)
  if icb_k then return icb_k() end
  if i > 0 then
    return record_review(file,i-1)
  else
    session:streamFile("voicemail/vm-goodbye.wav")
    return session:hangup()
  end
end

function record_greeting(file)
  session:streamFile("voicemail/vm-record_greeting.wav")
  session:streamFile("tone_stream://%(400,0,800)")
  session:setInputCallback("icb_break_on_any_dtmf","")
  session:recordFile(file,120000,200,3)
  session:streamFile(file)
  return record_review(file,3)
end

-- record voicemail greeting

if not session then
  return log("err","Aborting voicemail setup; need a session")
end
local greeting_file=argv[1]
if not greeting_file then
  return log("err","Aborting voicemail setup; need a greeting path")
end
record_greeting(greeting_file)
