local M={}
local prepared=setmetatable({},{__mode='k'})

local function normalize(value)
  return (tostring(value or ''):gsub('(%l)(%u)','%1 %2'):lower():gsub('(%a)(%d)','%1 %2'):gsub('(%d)(%a)','%1 %2')
    :gsub('[^%w%s]',' '):gsub('%s+',' '):match('^%s*(.-)%s*$'))
end

local function tokens(text)
  local out={}
  for word in text:gmatch('%S+') do out[#out+1]=word end
  return out
end

function M.match(rows,query)
  local needle=normalize(query)
  if needle=='' then return rows end
  local terms=tokens(needle)
  local compact=needle:gsub(' ','')
  local ranked={}
  for order,fx in ipairs(rows) do
    local display=(fx.display or fx.name or ''):gsub('^[%w]+:%s*','')
    local signature=display..'\0'..(fx.developer or '')
    local data=prepared[fx]
    if not data or data.signature~=signature then
      local name=normalize(display:gsub('%s*%([^)]*%)%s*$',''))
      data={signature=signature,name=name,words=tokens(normalize(display..' '..(fx.developer or ''))),joined=name:gsub(' ','')}
      prepared[fx]=data
    end
    local name,words=data.name,data.words
    local score,matched=0,true
    for _,term in ipairs(terms) do
      local best=0
      for _,word in ipairs(words) do
        if word==term then best=math.max(best,20)
        elseif not term:match('^%d+$') and word:sub(1,#term)==term then best=math.max(best,10) end
      end
      if best==0 and not term:match('%d') then
        for i=1,#words do
          local phrase=''
          for j=i,#words do
            phrase=phrase..words[j]
            if phrase==term then best=20;break end
            if #phrase>=#term then break end
          end
          if best>0 then break end
        end
      end
      if best==0 then matched=false;break end
      score=score+best
    end
    -- A joined spelling such as "proq4" also matches "Pro-Q 4".
    local joined=data.joined
    if joined==compact then matched=true;score=score+200
    else
      local joined_match=false
      for i=1,#words do
        local phrase=''
        for j=i,#words do
          phrase=phrase..words[j]
          if phrase==compact then
            joined_match=true
            score=score+(i==1 and 120 or 60)
            break
          end
          if #phrase>=#compact then break end
        end
        if joined_match then break end
      end
      if joined_match then matched=true end
    end
    if name==needle then score=score+300
    elseif (' '..name..' '):find(' '..needle..' ',1,true) then score=score+150 end
    if matched then ranked[#ranked+1]={fx=fx,score=score,order=order} end
  end
  table.sort(ranked,function(a,b)
    if a.score~=b.score then return a.score>b.score end
    return a.order<b.order
  end)
  local result={}
  for _,entry in ipairs(ranked) do result[#result+1]=entry.fx end
  return result
end

return M
