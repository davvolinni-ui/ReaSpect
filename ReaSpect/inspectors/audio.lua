local api=require('ReaSpect.core.reaper_api')
local prop=require('ReaSpect.widgets.property')
local selection=require('ReaSpect.core.item_selection')
local actions=require('ReaSpect.core.item_actions')
local controls=require('ReaSpect.widgets.controls')
local fades=require('ReaSpect.widgets.fades')
local M={}
local mode_labels,mode_values

local function db(volume)
  volume=math.abs(volume or 0)
  return volume<=1e-8 and -150 or 20*math.log(volume,10)
end

local function pitch_mode(take)
  return math.floor(reaper.GetMediaItemTakeInfo_Value(take,'I_PITCHMODE') or -1)
end

local function algorithm(take)
  local mode=pitch_mode(take)
  return mode<0 and -1 or (mode>>16)
end

local function draw_pitch_modes(ctx,state,takes)
  if not reaper.EnumPitchShiftModes then return end
  if not prop.section(ctx,state,'item_stretch','Stretch / Pitch',false) then return end
  if not mode_labels then
    mode_labels,mode_values={'Project default'},{-1}
    for mode=0,1023 do
      local ok,name=reaper.EnumPitchShiftModes(mode)
      if not ok then break end
      if name and name~='' then mode_labels[#mode_labels+1]=name;mode_values[#mode_values+1]=mode end
    end
  end
  local current=selection.shared(takes,algorithm)
  prop.enum(ctx,'Algorithm','##pitchalgorithm',current,mode_labels,mode_values,function(mode)
    selection.edit(takes,'Set take pitch algorithm',function(t,value)
      reaper.SetMediaItemTakeInfo_Value(t,'I_PITCHMODE',value<0 and -1 or (value<<16))
    end,mode)
  end,{default=-1})
  if type(current)=='number' and current>=0 and reaper.EnumPitchShiftSubModes then
    local labels,values={},{}
    for sub=0,1023 do
      local name=reaper.EnumPitchShiftSubModes(current,sub)
      if not name or name=='' then break end
      labels[#labels+1],values[#values+1]=name,sub
    end
    if #labels>0 then
      prop.enum(ctx,'Mode','##pitchsubmode',selection.shared(takes,function(t) return pitch_mode(t)&65535 end),labels,values,function(sub)
        selection.edit(takes,'Set take pitch algorithm mode',function(t,value)
          reaper.SetMediaItemTakeInfo_Value(t,'I_PITCHMODE',(current<<16)|value)
        end,sub)
      end,{default=0})
    end
  end
end

local function draw_actions(ctx,items)
  local normalize,reverse=actions.available('normalize'),actions.available('reverse')
  if not normalize and not reverse then return end
  local width=reaper.ImGui_GetContentRegionAvail(ctx)
  if normalize then
    if reaper.ImGui_Button(ctx,'Normalize…##normalize',reverse and (width-4)/2 or -1,22) then actions.queue('normalize',items) end
    prop.tooltip(ctx,'Open REAPER normalization: peak, RMS or LUFS for the selected audio events.')
  end
  if reverse then
    if normalize then reaper.ImGui_SameLine(ctx,0,4) end
    if reaper.ImGui_Button(ctx,'Reverse##reverse',-1,22) then actions.queue('reverse',items) end
    prop.tooltip(ctx,'Toggle playback direction for each selected audio take. Source files are unchanged.')
  end
end

function M.draw(ctx,state,items)
  local takes=selection.takes(items)
  if #takes==0 then return end
  local function shared(getter) return selection.shared(takes,getter) end
  local function edit(label,setter,value) selection.edit(takes,label,setter,value) end
  local function gain(t) return db(api.take.volume(t)) end
  local function set_gain(t,n)
    api.take.set_volume(t,(api.take.volume(t)<0 and -1 or 1)*10^(n/20))
  end
  local function pan(t) return api.take.pan(t)*100 end
  local function set_pan(t,n) api.take.set_pan(t,n/100) end
  prop.dual_number(ctx,'Gain','##takevol',shared(function(t) return db(api.take.volume(t)) end),
    'Pan','##takepan',shared(function(t) return api.take.pan(t)*100 end),
    function(v) edit('Set take gain',function(t,n)
      local polarity=api.take.volume(t)<0 and -1 or 1
      api.take.set_volume(t,polarity*10^(n/20))
    end,v) end,
    function(v) edit('Set take pan',api.take.set_pan,v/100) end,
    '%+.2f dB','%+.0f %%',
    {step=0.1,min=-150,max=60,default=0,on_delta=selection.delta_editor(takes,'Adjust take gain',gain,set_gain,-150,60),tooltip='Active take gain in dB; preserves take polarity.'},
    {step=1,min=-100,max=100,default=0,on_delta=selection.delta_editor(takes,'Adjust take pan',pan,set_pan,-100,100),tooltip='Take pan: −100% left, 0% center, +100% right.'})
  prop.dual_number(ctx,'Transpose','##pitch',shared(api.take.pitch),'Rate','##rate',shared(api.take.rate),
    function(v) edit('Set take transpose',api.take.set_pitch,v) end,
    function(v) edit('Set take playback rate',api.take.set_rate,v) end,
    '%+.2f st','%.3f x',
    {step=1,min=-96,max=96,default=0,on_delta=selection.delta_editor(takes,'Adjust take transpose',api.take.pitch,api.take.set_pitch,-96,96),tooltip='Semitones. Decimal values tune in cents: 0.01 st = 1 cent.'},
    {step=0.01,min=0.01,max=100,default=1,on_delta=selection.delta_editor(takes,'Adjust take rate',api.take.rate,api.take.set_rate,0.01,100),tooltip='Playback rate: 1 = original speed. Event boundaries stay in place.'})
  prop.row(ctx,'Fine tune',function()
    local width=reaper.ImGui_GetContentRegionAvail(ctx)
    local function tune_button(label,w,delta)
      local hit=reaper.ImGui_Button(ctx,label,w,20)
      local wheeled,amount=controls.wheel(ctx,0,0.01)
      if controls.right_click(ctx) then edit('Reset take transpose',api.take.set_pitch,0)
      elseif hit or wheeled then
        selection.delta_editor(takes,'Fine tune takes',api.take.pitch,api.take.set_pitch,-96,96)(wheeled and amount or delta)
      end
      prop.tooltip(ctx,'Adjust by one cent. Wheel preserves pitch differences; right-click resets transpose.')
    end
    tune_button('−1 ct##tunedown',(width-4)/2,-0.01)
    reaper.ImGui_SameLine(ctx,0,4)
    tune_button('+1 ct##tuneup',-1,0.01)
  end)
  prop.checkbox(ctx,'Preserve pitch','##preserve',shared(api.take.preserve_pitch),function(v) edit('Set preserve pitch',api.take.set_preserve_pitch,v) end,true)
  fades.draw(ctx,state,items)
  draw_actions(ctx,items)
  draw_pitch_modes(ctx,state,takes)
end

return M
