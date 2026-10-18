-- Musical role themes, independent of the ordinary track palette.
-- Shade positions are semantic IDs, never track order or enabled-role count.
local M={}
M.presets={
  {id='classic',name='Classic',colors={Drums=0xC68A48,Bass=0x73965B,Guitars=0x588DB8,Keys=0x8A79B6,Orchestral=0xAC9864,Vocals=0xBD718D,Utility=0x579F98},reference=0x92979E,buses=0x788393},
  {id='cool',name='Cool',colors={Drums=0x579FD0,Bass=0x9275CB,Guitars=0x48ADAA,Keys=0xC676A1,Orchestral=0x82A66C,Vocals=0xD5A452,Utility=0xAA6D7C},reference=0x94A0AC,buses=0x6D8093},
  {id='neon',name='Neon',colors={Drums=0xEB4B91,Bass=0x36C7CD,Guitars=0x95C83D,Keys=0xEF943C,Orchestral=0x518DEA,Vocals=0xB36BE8,Utility=0xD8C947},reference=0xADB4BF,buses=0x7589A6},
  {id='soft',name='Soft',colors={Drums=0xB6A2D8,Bass=0xA6BE8F,Guitars=0xD9AD8C,Keys=0x91B7D6,Orchestral=0xD0C58D,Vocals=0xD39DB4,Utility=0x8AC3BA},reference=0xB2B6BF,buses=0xA0A7B9},
  {id='earth',name='Earth',colors={Drums=0xB46F53,Bass=0x8B945A,Guitars=0x648D85,Keys=0xB59B55,Orchestral=0xAD8190,Vocals=0x88698E,Utility=0x63829C},reference=0x92918B,buses=0x7D8584},
}
-- Fixed identity positions within the same 0–40% tint range as folder shades.
local positions={drums=0,kick=0.05,snare=0.10,toms=0.15,hats=0.20,cymbals=0.25,overheads=0.30,room=0.35,percussion=0.40,
  bass=0,synth_bass=0.20,sub=0.40,electric=0,acoustic=0.20,lead_guitar=0.40,
  keys=0,piano=0.08,ep=0.16,organ=0.24,synth=0.32,pads=0.40,strings=0,brass=0.20,woodwinds=0.40,
  lead_vocal=0,backing=0.08,doubles=0.16,harmonies=0.24,adlibs=0.32,choir=0.40,returns=0,fx=0.20,buses=0,reference=0}
local fallbacks={
  classic={0x788393,0x92979E,0x8A9383,0x9D9184,0x938797,0x809895},
  cool={0x718B9F,0x8796AA,0x8D84A2,0x809D99,0xA29589,0xA18898},
  neon={0x7B8FA8,0x9CA9B8,0x759E9F,0xA691AC,0xA6A17D,0x9A889D},
  soft={0xA0A7B9,0xB2B6BF,0xACB9AE,0xC0B2A4,0xB6AABE,0xA6BCBA},
  earth={0x7D8584,0x92918B,0x8B937B,0xA08A78,0x937F8C,0x7B9294},
}
for _,preset in ipairs(M.presets) do preset.fallback=fallbacks[preset.id] end
function M.find(id)
  id=({studio='classic',muted='cool',vivid='neon',pastel='soft'})[id] or id
  for _,preset in ipairs(M.presets) do if preset.id==id then return preset end end
end
function M.shade(rgb,id)
  local amount=positions[id]
  if amount==nil then
    -- Stable supplementary shades for user-created roles, independent of order.
    local hash=0;for i=1,#tostring(id) do hash=(hash*31+tostring(id):byte(i))%65521 end
    amount=({0.08,0.16,0.24,0.32,0.40})[hash%5+1]
  end
  local function channel(value) return math.floor(value+(255-value)*amount+0.5) end
  return (channel((rgb>>16)&255)<<16)|(channel((rgb>>8)&255)<<8)|channel(rgb&255)
end
function M.color(id,role,flat)
  local preset=M.find(id)
  if not preset then return end
  if role.id=='reference' then return preset.reference end
  if role.id=='buses' then return preset.buses end
  local base=preset.colors[role.group]
  return base and (flat and base or M.shade(base,role.id))
end
return M
