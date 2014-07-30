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

-- lib

function file_size(file)
  local f = io.open(file,"r")
  if not f then return nil end
  local len=f:seek("end")
  f:close()
  return len
end

function shell_quote(str)
  return "'"..string.gsub(str,"'","'\\''").."'"
end

function q_strip(str)
  local s
  s = string.gsub(str,"\"","")
  s = string.gsub(str,"'","")
  return s
end

function dq_strip(str)
  return string.gsub(str,"\"","")
end

function random10(n)
  local f = io.open("/dev/urandom","r")
  local x=0 buf=""
  while x<n do
    local b = string.byte(f:read(1))%16
    if b<10 then
      buf=buf..string.char(b+48)
      x=x+1
    end
  end
  f:close()
  return buf
end

function random16(n)
  local set = "0123456789abcdef"
  local f = io.open("/dev/urandom","r")
  local x=0 buf=""
  while x<n do
    local b = string.byte(f:read(1))%16
    buf=buf..string.sub(set,b,b)
    x=x+1
  end
  f:close()
  return buf
end

function fill(str,vars)
  return string.gsub(str,"%${([^}]+)}",
                     function(k,fmt)
                       return vars[k] or ""
                     end)
end

-- email

function mk_msg(eml_file,file,secs,to)
  local time = tonumber(getvar_a("start_epoch"))
  local stamp = os.date("%Y%m%dT%H%M%SZ",time)
  local htime = os.date("%Y-%m-%d %H:%M:%S UTC",time)
  local uuid = session:get_uuid()
  local domain = getvar_a("domain")
  local clidnamq = dq_strip(getvar_a("caller_id_name"))
  local clidnumq = q_strip(getvar_a("caller_id_number"))
  local clidsubj = "\""..clidnamq.."\" <"..clidnumq..">"
  if #clidnamq == 0 and #clidnumq == 0 then
    clidnamq="Unknown caller"
    clidnumq="unknown"
    clidsubj="\"Unknown caller\""
  elseif #clidnamq == 0 then
    clidnamq=clidnumq
    clidsubj="<"..clidnumq..">"
  elseif #clidnumq == 0 then
    clidnumq=""
    clidsubj="\""..clidnamq.."\""
  elseif clidnam == clidnum then
    clidsubj="\""..clidnamq.."\""
  end
  local eml_f = assert(io.open(eml_file,"w"))
  local msg_vars = {
    msg_to = to,
    msg_boundary1 = "------------"..random10(24),
    msg_boundary2 = "------------"..random10(24),
    msg_id = uuid.."_"..random16(16).."@"..domain,
    msg_date = os.date("%a, %d %b %Y %H:%M:%S %z",time),
    msg_file = stamp.."_"..uuid..".wav",
    domain = domain,
    clidnamq = clidnamq,
    clidnumq = clidnumq,
    clidsubj = clidsubj,
    len_secs = secs,
    htime = htime,
  }
  local msg_top = fill([[
Message-ID: <${msg_id}>
Date: ${msg_date}
From: "${clidnamq}" <${clidnumq}@${domain}>
MIME-Version: 1.0
To: ${msg_to}
Subject: Voicemail from ${clidsubj} (${len_secs} seconds)
Content-Type: multipart/mixed;
 boundary="${msg_boundary1}"

This is a multi-part message in MIME format.
--${msg_boundary1}
Content-Type: multipart/alternative;
 boundary="${msg_boundary2}"

--${msg_boundary2}
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 7bit

From: "${clidnamq}" <${clidnumq}>
Date: ${htime}
Length: ${len_secs} seconds

--${msg_boundary2}
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: 7bit

<html xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
    <title>Voicemail from "${clidnamq}" <${clidnumq}> (${len_secs} seconds)</title>
  </head>
  <body>
    <font face="arial">
      <b>Voicemail from "${clidnamq}" &lt;<a href="tel:${clidnumq}">${clidnumq}</a>&gt;</b><br/>
      <hr style="height:1px;border-width:0;color=gray;background-color:gray" />
      Date: ${htime}<br/>
      Length: ${len_secs} seconds<br/>
    </font>
  </body>
</html>

--${msg_boundary2}--

--${msg_boundary1}
Content-Type: audio/x-wav;
 name="${msg_file}"
Content-Transfer-Encoding: base64
Content-Disposition: attachment;
 filename="${msg_file}"

]],msg_vars)
  eml_f:write(msg_top)
  eml_f:close()
  os.execute("base64 -w72 < "..shell_quote(file).." >> "..shell_quote(eml_file))
  local eml_f = assert(io.open(eml_file,"a"))
  eml_f:write("--"..msg_vars.msg_boundary1.."--\n")
  eml_f:close()
end

function send_msg(file,secs,rcpts)
  local time = tonumber(getvar_a("start_epoch"))
  local stamp = os.date("%Y%m%dT%H%M%SZ",time)
  local uuid = session:get_uuid()
  local eml_file = "/tmp/"..stamp.."_"..uuid..".eml"
  local domain = getvar_a("domain")
  local sender_from = "noreply@"..domain
  local to = table.join(rcpts,",")
  local rcpts_q=table.join(map(shell_quote,rcpts)," ")
  log("notice","Sending email to: "..to)
  mk_msg(eml_file,file,secs,to)
  os.execute("cat "..shell_quote(eml_file).." | sendmail -f "..sender_from.." "..rcpts_q)
  os.remove(eml_file)
end

-- record_msg

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
          return record_msg(file)
        end
      return "break"
    end
  end
end

function record_review(file,i)
  if not session:ready() then return end
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

function record_msg(file)
  if not session:ready() then return nil end
  session:streamFile("voicemail/vm-record_message.wav")
  session:streamFile("tone_stream://%(400,0,800)")
  if not session:ready() then return nil end
  icd_d=nil
  session:setInputCallback("icb_break_on_any_dtmf","")
  session:recordFile(file,120000,200,2)
  record_review(file,3)
  local fsize = file_size(file)
  if not fsize or fsize < 100 then return nil end
  local len = tonumber(getvar_a("record_seconds"))
  if not len or len < 3 then return nil end
  return len
end

-- leave voicemail message

if not session then
  return log("err","Aborting voicemail; need a session")
end
local time = tonumber(getvar_a("start_epoch"))
local stamp = os.date("%Y%m%dT%H%M%SZ",time)
local uuid = session:get_uuid()
local vm_file = "/tmp/"..stamp.."_"..uuid..".wav"
local vm_args,vm_rcpts = table.splice(table.seq(argv),2)
local vm_greeting = table.unpack(vm_args)
if not vm_greeting or type(vm_greeting) ~= "string" then
  return log("err","Aborting voicemail; no greeting path")
end
if not vm_rcpts or #vm_rcpts < 1 then
  return log("err","Aborting voicemail; nowhere to send the message")
end
if file_size(vm_greeting) then
  session:streamFile(vm_greeting)
end
local vm_secs = record_msg(vm_file)
if vm_secs then
  send_msg(vm_file,vm_secs,vm_rcpts)
end
os.remove(vm_file)
