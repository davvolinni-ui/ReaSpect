local api=require('ReaSpect.core.reaper_api')
local prop=require('ReaSpect.widgets.property')
local selection=require('ReaSpect.core.item_selection')
local actions=require('ReaSpect.core.item_actions')
local M={}

function M.draw(ctx,state,items)
  local takes=selection.takes(items)
  if #takes==0 then return end
  prop.dual_number(ctx,'Transpose','##midipitch',selection.shared(takes,api.take.pitch),
    'Rate','##midirate',selection.shared(takes,api.take.rate),
    function(v) selection.edit(takes,'Set MIDI take transpose',api.take.set_pitch,math.floor(v+0.5)) end,
    function(v) selection.edit(takes,'Set MIDI take rate',api.take.set_rate,v) end,
    '%+.0f st','%.3f x',{step=1,quantum=1,min=-127,max=127,default=0,
      on_delta=selection.delta_editor(takes,'Adjust MIDI transpose',api.take.pitch,api.take.set_pitch,-127,127,1),tooltip='Transpose MIDI take playback in semitones.'},
    {step=0.01,min=0.01,max=100,default=1,on_delta=selection.delta_editor(takes,'Adjust MIDI rate',api.take.rate,api.take.set_rate,0.01,100),tooltip='MIDI take playback rate. Event boundaries stay in place.'})
  if actions.available('midi_editor') then
    if reaper.ImGui_Button(ctx,'Open MIDI editor##event_midi_editor',-1,23) then actions.queue('midi_editor',items) end
  end
  -- Audio channel modes are not MIDI output-channel remapping. Keep note
  -- editing and channel assignment in REAPER's dedicated MIDI editor.
  if reaper.MIDI_CountEvts then
    local notes,cc=0,0
    for _,take in ipairs(takes) do
      local ok,n,c=reaper.MIDI_CountEvts(take)
      if ok then notes=notes+n;cc=cc+c end
    end
    reaper.ImGui_TextDisabled(ctx,string.format('%d notes · %d CC events',notes,cc))
  end
end

return M
