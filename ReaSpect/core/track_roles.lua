-- Plain, whole-word name matching. Longer phrases win; utility roles have
-- priority so "Vocal Reverb" is an FX return rather than a lead vocal.
local palette=require('ReaSpect.core.palettes')[1].colors
local M={}
local definitions={
  {'drums','Drum bus','Drums','drum bus,drum buss,drums,readrum,readrumxt,readrum xt,rea drum xt,drum rack,drum machine,ezdrummer,superior drummer,addictive drums',1,true,80},
  {'kick','Kick','Drums','kick,kik,bd,bass drum',2,true},
  {'snare','Snare','Drums','snare,snr,sn,sd',3,true},
  {'toms','Toms','Drums','tom,toms,rack tom,floor tom',4,true},
  {'hats','Hi-hats','Drums','hi hat,hi hats,hihat,hihats,open hat,open hats,closed hat,closed hats,hat,hats,hh',5,true},
  {'cymbals','Cymbals','Drums','cymbal,cymbals,crash,ride,splash',6,true},
  {'overheads','Overheads','Drums','overhead,overheads,oh',7,true},
  {'room','Drum room','Drums','drum room,room mic,room mics',8,false},
  {'percussion','Percussion','Drums','percussion,perc,clap,claps,handclap,handclaps,shaker,tambourine,conga,bongo',9,true},
  {'bass','Bass guitar','Bass','bass,bass guitar',4,true},
  {'synth_bass','Synth bass','Bass','synth bass,bass synth',5,true},
  {'sub','Sub / 808','Bass','sub,sub bass,808',6,true},
  {'electric','Electric guitar','Guitars','electric guitar,electric gtr,guitar,gtr,guitars',9,true},
  {'acoustic','Acoustic guitar','Guitars','acoustic,acoustic guitar,acoustic gtr,ac gtr',10,true},
  {'lead_guitar','Lead guitar','Guitars','lead guitar,lead gtr,guitar solo,gtr solo',11,false},
  {'keys','Keys','Keys','keys,keyboard,keyboards,key bus,keys bus',7,true},
  {'piano','Piano','Keys','piano,grand piano',7,true},
  {'ep','Electric piano','Keys','electric piano,e piano,ep,rhodes,wurlitzer,wurli',8,true},
  {'organ','Organ','Keys','organ,hammond',9,false},
  {'synth','Synth','Keys','synth,synths,synthesizer',10,true},
  {'pads','Pads','Keys','pad,pads,atmosphere',11,true},
  {'strings','Strings','Orchestral','strings,string section,violin,viola,cello,contrabass',12,false},
  {'brass','Brass','Orchestral','brass,trumpet,trombone,horn,tuba',13,false},
  {'woodwinds','Woodwinds','Orchestral','woodwind,woodwinds,flute,clarinet,oboe,bassoon,sax,saxophone',14,false},
  {'lead_vocal','Lead vocal','Vocals','vocal,vocals,vox,lead vocal,lead vox,main vocal,main vox',13,true},
  {'backing','Backing vocals','Vocals','backing vocal,backing vocals,backing vox,bg vocal,bg vocals,bg vox,bgv,bgvs,bv,bvs,background vocal,background vocals',14,true},
  {'doubles','Vocal doubles','Vocals','vocal double,vocal doubles,vox double,vox doubles,doubles,dbl',15,false},
  {'harmonies','Harmonies','Vocals','harmony,harmonies,harm',16,false},
  {'adlibs','Ad-libs','Vocals','ad lib,ad libs,adlib,adlibs',12,false},
  {'choir','Choir','Vocals','choir,choral',11,false},
  {'returns','FX returns','Utility','reverb,verb,delay,echo,fx return,return,returns,send,sends,receive,receives,aux,auxiliary',8,true,100},
  {'fx','Sound design / FX','Utility','fx,sfx,sound design,riser,impact,foley',9,false,50},
  {'buses','Buses / Groups','Utility','bus,buss,group,submix',2,true,80},
  {'reference','Reference','Utility','reference,ref,reference mix',1,false,120},
}
-- Keep the shipped lists so saved, untouched defaults can be upgraded while
-- user-edited lists remain authoritative (including deliberately removed words).
local previous_keywords={}
local additions={
  drums='drum kit,drumkit,drum set,drumset,drum loop,drum loops,drum stem',
  kick='kicks,kickdrum,kick drum,bassdrum',
  snare='snares,snare drum,snaredrum,rimshot,rim shot,rimshots,sidestick,side stick,cross stick',
  toms='rack toms,floor toms,high tom,low tom,mid tom',
  hats='hi hat open,hi hat closed,open hihat,closed hihat,hi hat pedal,pedal hat,hh open,hh closed,ohh,chh',
  cymbals='crashes,rides,splashes,china cymbal,china cymbals',
  overheads='over head,over heads,drum overhead,drum overheads',
  room='drum rooms,room microphones,drum ambience',
  percussion='percs,shakers,tamb,tambourines,congas,bongos,cowbell,cowbells,clave,claves,woodblock,wood block,triangle,triangles,djembe,cajon,timbale,timbales,guiro,cabasa,maraca,maracas,snap,snaps,finger snap,finger snaps',
  bass='electric bass,bass gtr,bass guitar di,bass di,bass amp,upright bass,double bass,fretless bass',
  synth_bass='synthbass,synthesized bass,synthesised bass,moog bass,reese bass',
  sub='subs,subbass,808s,808 bass',
  electric='electric guitars,electric gtrs,elec guitar,elec gtr,egtr,e gtr,rhythm guitar,rhythm gtr',
  acoustic='acoustic guitars,acoustic gtrs,ac guitar,agtr,a gtr,nylon guitar,steel string guitar',
  lead_guitar='lead guitars,lead gtrs,solo guitar,solo gtr',
  keys='keyb,kbd,keyboard bus,keyboards bus',
  piano='pianos,grand,upright piano,acoustic piano,baby grand',
  ep='electric pianos,electric keys,elec piano,epiano,e pian,e pno,fender rhodes,wurlie',
  organ='organs,hammond organ,b3,b 3,pipe organ',
  synth='synthesizers,synthesiser,synthesisers,analog synth,analogue synth,poly synth',
  pads='synth pad,synth pads,ambient pad,ambient pads,soundscape,soundscapes',
  strings='string ensemble,string quartet,violins,violas,cellos,violoncello,contrabasses,orchestral strings',
  brass='brass section,trumpets,trombones,horns,french horn,french horns,tubas,flugelhorn',
  woodwinds='flutes,clarinets,oboes,bassoons,saxes,saxophones,piccolo,english horn,bass clarinet',
  lead_vocal='lead vocals,lead voc,main vocals,main voc,lv,ld vox',
  backing='backing,backings,backing voc,backing vocalists,background vocals,background vox,background voc,bgvox,b vox,b voc',
  doubles='double vocal,double vocals,double vox,vox dbl,vocal dbl,dbl vox,dt vox,double track vocal,double tracked vocal',
  harmonies='vocal harmony,vocal harmonies,vox harmony,vox harmonies,harm vox,harm vocal',
  adlibs='ad lib vocal,ad lib vox,adlibs vocal,adlibs vox',
  choir='choirs,chorus vocals,vocal ensemble',
  returns='fx returns,effect return,effect returns,effects return,effects returns,aux return,aux returns,aux send,aux sends,rev,dly',
  fx='effects,sound effects,sound fx,risers,impacts,transition,transitions,whoosh,whooshes,downlifter,uplifter',
  buses='busses,buses,groups,sub mix,stem bus,stem buss,mix bus,mix buss,master bus',
  reference='references,reference track,reference tracks,ref track,ref mix',
}
for _,definition in ipairs(definitions) do
  local id=definition[1]
  previous_keywords[id]={[definition[4]]=true}
  if additions[id] then definition[4]=definition[4]..','..additions[id] end
end
previous_keywords.hats['hi hat,hi hats,hihat,hihats,hat,hats,hh']=true
previous_keywords.percussion['percussion,perc,shaker,tambourine,conga,bongo']=true
previous_keywords.drums['drum bus,drum buss,drums']=true
previous_keywords.drums['drum bus,drum buss,drums,readrum,readrumxt,readrum xt']=true
previous_keywords.returns['reverb,verb,delay,echo,fx return,return,returns,send,sends,receive,receives']=true
M.definitions=definitions
function M.defaults()
  local result={}
  for _,d in ipairs(definitions) do
    result[#result+1]={id=d[1],name=d[2],group=d[3],keywords=d[4],color=palette[d[5]],palette_slot=d[5],color_custom=false,enabled=d[6],priority=d[7] or 0,icon='@auto'}
  end
  return result
end
local function escape(s) return (tostring(s):gsub('%%','%%25'):gsub('|','%%7C'):gsub('\n','%%0A'):gsub('\r','%%0D')) end
local function unescape(s) return (s:gsub('%%(%x%x)',function(hex) return string.char(tonumber(hex,16)) end)) end
function M.encode(roles)
  local lines={}
  for _,r in ipairs(roles) do
    lines[#lines+1]=table.concat({r.id,r.enabled and '1' or '0',string.format('%06X',r.color),escape(r.keywords),escape(r.icon or ''),escape(r.name),escape(r.group),r.color_custom==false and '0' or '1','3'},'|')
  end
  return table.concat(lines,'\n')
end
function M.decode(text)
  local roles=M.defaults()
  local by_id={};for _,r in ipairs(roles) do by_id[r.id]=r end
  for line in tostring(text or ''):gmatch('[^\n]+') do
    local id,on,hex,words,icon,name,group,custom=line:match('^([^|]+)|([01])|(%x%x%x%x%x%x)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([01])|3$')
    if not id then id,on,hex,words,icon,name,group=line:match('^([^|]+)|([01])|(%x%x%x%x%x%x)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|2$') end
    local modern=id~=nil
    if not id then id,on,hex,words,icon,name,group=line:match('^([^|]+)|([01])|(%x%x%x%x%x%x)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$') end
    if not id then id,on,hex,words,icon=line:match('^([^|]+)|([01])|(%x%x%x%x%x%x)|([^|]*)|([^|]*)$') end
    local r=id and by_id[id]
    if not r and id and id:match('^custom_%d+$') then
      r={id=id,name='Custom role',group='Custom',priority=0,palette_slot=1,color_custom=true}
      roles[#roles+1]=r;by_id[id]=r
    end
    if r then
      r.color_custom=custom and custom=='1' or (custom==nil and tonumber(hex,16)~=r.color)
      r.enabled=on=='1';r.color=tonumber(hex,16);r.keywords=unescape(words);r.icon=unescape(icon)
      if not modern and r.icon=='' and not id:match('^custom_') then r.icon='@auto' end
      -- Upgrade the previous untouched default; preserve edited keyword lists.
      if previous_keywords[id] and previous_keywords[id][r.keywords] then
        for _,definition in ipairs(definitions) do if definition[1]==id then r.keywords=definition[4];break end end
      end
      if name and name~='' then r.name=unescape(name) end
    end
  end
  return roles
end
local function normalized(text)
  -- Preserve standalone numeric keywords such as 808, but split Kick01.
  text=tostring(text or ''):lower():gsub('(%a)(%d)','%1 %2'):gsub('(%d)(%a)','%1 %2')
  return ' '..text:gsub('[%p%s_]+',' '):match('^%s*(.-)%s*$')..' '
end
local context={drums={},buses={}}
for _,d in ipairs(definitions) do if context[d[1]] then
    for keyword in d[4]:gmatch('[^,;\n]+') do context[d[1]][normalized(keyword):sub(2,-2)]=true end
end end
local generic={bass={bass=true,['bass guitar']=true},electric={guitar=true,gtr=true,guitars=true},
    keys={keys=true,keyboard=true,keyboards=true,keyb=true,kbd=true},synth={synth=true,synths=true,synthesizer=true,synthesiser=true},
    lead_vocal={vocal=true,vocals=true,vox=true}}
local purpose={returns=true,fx=true,reference=true}
local specificity={keys=0,synth=1,bass=0,electric=0,lead_vocal=0}
local prepared=setmetatable({},{__mode='k'})
local function keywords_for(role)
  local source=tostring(role.keywords or '')
  local cached=prepared[role]
  if cached and cached.source==source then return cached.entries end
  local entries={}
  for keyword in source:gmatch('[^,;\n]+') do
    local pattern=normalized(keyword)
    if #pattern>2 then
      local words=0;for _ in pattern:gmatch('%S+') do words=words+1 end
      entries[#entries+1]={pattern=pattern,word=pattern:sub(2,-2),words=words}
    end
  end
  prepared[role]={source=source,entries=entries}
  return entries
end
function M.detect(name,roles)
  -- Sample names commonly put the instrument before a spaced dash and the
  -- sample description after it ("open hat - verb", "open hat - splash").
  local instrument=tostring(name or ''):match('^(.-)%s+%-%s*')
  if instrument then
    local primary,word=M.detect(instrument,roles)
    if primary and primary.group~='Utility' then return primary,word end
  end
  local text=normalized(name)
  local camel=normalized(tostring(name or ''):gsub('(%u)(%u%l)','%1 %2'):gsub('(%l)(%u)','%1 %2'))
  local candidates={}
  for _,r in ipairs(roles) do
    if r.enabled then
      local candidate
      for _,entry in ipairs(keywords_for(r)) do
        local pattern=entry.pattern
        if text:find(pattern,1,true) or camel:find(pattern,1,true) then
          local word=entry.word
          -- "Sub mix" is a routing phrase, not a sub-bass instrument.
          local kind=purpose[r.id] and 2 or (r.id=='buses' and word=='sub mix' and 1)
            or (context[r.id] and context[r.id][word] and 0 or 1)
          local score=kind*1000000+(r.priority or 0)*1000+entry.words*10
            +(word:match('^%d+$') and 0 or 1)+(kind==0 and r.id=='drums' and 100 or 0)
          if not candidate or score>candidate.score then candidate={role=r,word=word,score=score,kind=kind} end
        end
      end
      if candidate then candidates[#candidates+1]=candidate end
    end
  end
  local best,word,best_score,ambiguous
  for _,candidate in ipairs(candidates) do
    local r=candidate.role
    local shadowed=false
    if r.id=='sub' and candidate.word=='808' then
      local drum_context,bass_context=false,false
      for _,other in ipairs(candidates) do
        if other.role.id=='drums' and other.kind==0 then drum_context=true end
        if other.role.id~=r.id and other.role.group=='Bass' and other.kind==1 then bass_context=true end
      end
      -- An exported drum-track number is not evidence of a bass instrument.
      shadowed=drum_context and not bass_context
    end
    if generic[r.id] and generic[r.id][candidate.word] then
      for _,other in ipairs(candidates) do
        if other.role.id~=r.id and other.role.group==r.group and other.kind==1
            and (specificity[other.role.id] or 2)>(specificity[r.id] or 2) then shadowed=true;break end
      end
    end
    if not shadowed then
      if not best_score or candidate.score>best_score then
        best,word,best_score,ambiguous=r,candidate.word,candidate.score,false
      elseif candidate.score==best_score and best.id~=r.id then ambiguous=true end
    end
  end
  if ambiguous then return nil,'Ambiguous name' end
  return best,word
end
function M.by_id(roles,id) for _,r in ipairs(roles) do if r.id==id then return r end end end
return M
