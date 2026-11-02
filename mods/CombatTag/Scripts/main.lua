-- Combat Tag 0.1.4 - game-thread scheduling - Final Fantasy Resonance, Steam build 24250053.
-- All runtime Lua, input polling, timers, hooks, and adapter calls stay on the game thread.
-- No LoopAsync/ExecuteWithDelay/RegisterKeyBind runtime hand-offs: the installed
-- UE4SS build can race hook_lua and its registry from those background threads.
-- One bootstrap is queued below, as the last operation on the loading thread.
-- UI lifecycle revision: character-ui-only, 2026-10-25.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/')
local modDir=assert(source:match('^(.*)/Scripts/[^/]+$'),'Cannot locate CombatTag folder')
local D={}
function D.log(message)
 local line='[CombatTag] '..tostring(message)
 print(line..'\n')
 local f=io.open(modDir..'/CombatTag.log','a')
 if f then f:write(os.date('%Y-%m-%d %H:%M:%S '),line,'\n');f:close() end
end
function D.attempt(label,fn)
 local ok,result=xpcall(fn,debug.traceback)
 if not ok then D.log(label..' FAILED: '..tostring(result)) end
 return ok and result or nil
end
function D.readCost()
 local f=io.open(modDir..'/settings.ini','r')
 if not f then return true end
 local text=f:read('*a');f:close()
 return not text:match('ConsumeTurn%s*=%s*false')
end
function D.writeCost(value)
 local f=io.open(modDir..'/settings.ini','w')
 if not f then D.log('Unable to save turn-cost setting');return end
 f:write('ConsumeTurn=',tostring(value),'\n');f:close()
end
local loadError
D.bridge,loadError=package.loadlib(modDir..'/tag_bridge.dll','tag_bridge')
if not D.bridge then D.log('Native adapter failed to load: '..tostring(loadError));return end
local compatibleOk,compatible=pcall(D.bridge,0)
if not compatibleOk or compatible~=2 then
 D.log('Unsupported game/UE4SS build. Combat Tag is disabled. This version requires Steam build 24250053 and its supplied UE4SS runtime.')
 return
end
local function initialize()
assert(IsInGameThread(),'CombatTag initialization must run on the game thread')
local S=CombatTag
if not S then S={cost=true,actors={},swaps=0};if D.readCost then S.cost=D.readCost() end end
CombatTag=S
S.epoch=S.epoch or 0
local G=assert(loadfile(modDir..'/Scripts/userdata_guard.lua'))()
local function valid(o) return o and G.protect(o):IsValid() end
local unwrap=G.unwrap
-- UObject and FText metatables are shared inside this mod's Lua state.
G.protect(StaticFindObject('/Script/mucha.Default__CPP_BFL_Unit'))
G.protect(FText('CombatTag'))
local function array(a)
 G.protect(a)
 local t={}
 if type(a)=='table' then for _,v in ipairs(a) do t[#t+1]=unwrap(v) end
 else for i=1,a:GetArrayNum() do t[#t+1]=unwrap(a[i]) end end
 return t
end
local function cdo(n) return G.protect(StaticFindObject('/Script/mucha.Default__'..n)) end
local function bridge(op,m,u,arg) return D.bridge(op,m:GetAddress(),u:GetAddress(),arg or 0) end
local function id(m,u) return bridge(1,m,u) end
local function name(uid)
 local r={};cdo('CPP_BFL_Unit'):GetUnitParameterById(r,uid,false)
 return r.Name:ToString()
end
local function active()
 local bm=FindFirstOf('CPP_BtlManager');local ui=FindFirstOf('CPP_UI_BattleSubsystem');local vm=FindFirstOf('CPP_VM_BtlCmd')
 if not valid(bm) or not valid(ui) or not ui.bDuringBattle or not valid(vm) or not vm.bDisplayCmd then return end
 if ui.BtlPhaseType~=0 or ui.BtlCmdManager.CmdType~=0 or cdo('CPP_BFL_Battle'):IsAutoBattle() then return end
 local m=bm.m_pUnitManager;local out=m.m_pCmdSelectUnit
 if not valid(out) or id(m,out)~=vm:GetTargetUnitUniqueId() or out.m_pUnitParameter:IsDead() then return end
 if not valid(out.m_pUnitParameter.m_pVision) then return end
 return m,ui,vm,out
end
local function hide(u,b)
 if valid(u) then u:SetActorHiddenInGame(b);u:SetVisibleOutline(false) end
end
local function relocate(u,reference)
 local pos=reference:K2_GetActorLocation()
 u:SetDefaultLocation(pos)
 u:K2_SetActorLocation(pos,false,{},true)
end
local function snapshotActor(u)
 local p=u.m_pUnitParameter;local skills={};p:GetPassiveSkillList(skills)
 return {id=p:GetUnitId(),hp=p:GetHitPoint(),mp=p:GetMagicPoint(),passives=array(skills)}
end
S.syncBench=function()
 local activeIds={}
 if valid(S.manager) then for _,u in ipairs(array(S.manager.m_UnitList)) do activeIds[u:GetAddress()]=true end end
 for uid,u in pairs(S.actors) do
  if valid(u) and not activeIds[u:GetAddress()] then
   local p=u.m_pUnitParameter
   cdo('CPP_BFL_SaveDataUnit'):SetSaveDataUnitHitPoint(uid,p:GetHitPoint())
   cdo('CPP_BFL_SaveDataUnit'):SetSaveDataUnitMagicPoint(uid,p:GetMagicPoint())
   D.log('BENCH saved '..uid..' HP='..p:GetHitPoint()..' MP='..p:GetMagicPoint())
  end
 end
end
S.cleanup=function()
 S.epoch=S.epoch+1;S.pendingChoice=nil;S.openPending=false
 local activeIds={}
 if valid(S.manager) then for _,u in ipairs(array(S.manager.m_UnitList)) do activeIds[u:GetAddress()]=true end end
 for _,u in pairs(S.actors) do
  if valid(u) and not activeIds[u:GetAddress()] then
   local v=u.m_pUnitParameter.m_pVision
   if valid(v) then v:K2_DestroyActor() end
   u:K2_DestroyActor()
  end
 end
 S.actors={};S.manager=nil;S.menu=nil;S.lastTimeline=nil
 D.log('Battle cache cleared')
end
S.swap=function(target)
 assert(IsInGameThread(),'Swap must run on the game thread')
 local m,ui,vm,out=active();assert(m,'Swap requires a normal command turn')
 D.log('SWAP start target='..tostring(target))
 if D.recordUI then D.recordUI(10,'before swap target='..target) end
 local outID=out.m_pUnitParameter:GetUnitId();assert(target~=outID,'Already active')
 for _,u in ipairs(array(m.m_UnitList)) do assert(u.m_pUnitParameter:GetUnitId()~=target,'Already active') end
 local task
 for _,t in ipairs(FindAllOf('CPP_BtlTaskCommand') or {}) do
  if valid(t.m_pActionUnit) and t.m_pActionUnit:GetAddress()==out:GetAddress() then task=t;break end
 end
 assert(task,'No active command task')
 local ov=out.m_pUnitParameter.m_pVision
 assert(valid(ov),'An equipped Vision is required')
 local del=StaticConstructObject(StaticFindObject('/Script/mucha.CPP_BtlUnitDestroyDelVal'),m)
 assert(valid(del),'UI event unavailable')
 local incoming=S.actors[target]
 local spawned=false
 if not valid(incoming) then
  local address=bridge(10,m,out,target);assert(address>0,'Spawn rejected '..address)
  for _,u in ipairs(array(m.m_UnitList)) do if u:GetAddress()==address then incoming=u;break end end
  spawned=true
 end
 assert(valid(incoming),'Missing incoming actor')
 if D.recordUI then D.recordUI(11,'incoming prepared spawned='..tostring(spawned)) end
 local ip=incoming.m_pUnitParameter;local iv=ip.m_pVision
 local function rollback()
  if spawned and bridge(13,m,incoming)==1 then
   if valid(iv) then iv:K2_DestroyActor() end
   incoming:K2_DestroyActor()
  end
 end
 if ip:IsDead() or not valid(iv) then rollback();error('Reserve is KO or has no equipped Vision') end
 local uid=id(m,out);local newuid=id(m,incoming)
 -- Only main battle actors have UI parameter VMs. Equipped Vision actors are
 -- deliberately excluded by the game's UI lookup. Deploying one creates an
 -- unbound ActionVM that crashes SyncActionState during a later bonus phase.
 local outgoingUI=ui.BtlUnitManager:GetUnitParamVM(uid)
 if not valid(outgoingUI) then rollback();error('Outgoing character UI data unavailable') end
 local check=D.bridge(14,ui:GetAddress(),outgoingUI:GetAddress(),1)
 if check<0 then rollback();error('UI retirement preflight failed '..check) end
 if valid(ui.BtlUnitManager:GetUnitParamVM(newuid)) then
  rollback();error('Incoming character already has UI data; refusing to overwrite it')
 end
 assert(ip:GetUnitId()==target,'Incoming actor identity mismatch')
 D.log('SWAP preflight target='..target..' outgoing='..outID..' incoming_uid='..newuid..' spawned='..tostring(spawned))
 local before=snapshotActor(incoming)
 relocate(incoming,out);relocate(iv,ov)
 D.log('SWAP stage=relocated')
 local result=bridge(11,m,out,incoming:GetAddress())
 if result~=newuid then rollback();error('Exchange failed '..result) end
 D.log('SWAP stage=actors-exchanged')
 S.actors[outID]=out;S.actors[target]=incoming;S.manager=m;S.swaps=S.swaps+1
 task.m_pActionUnit=incoming
 hide(out,true);hide(ov,true);hide(incoming,false);hide(iv,false);incoming:SetVisibleOutline(true)
 local cm=ui.BtlCmdManager
 cm.ActionUnitUniqueIdList={newuid};cm.ActionUnitIndex=0;cm.SpecificActionUnitUniqueId=newuid;ui.CurrentActionUnitUniqueId=newuid
 if D.recordUI then D.recordUI(12,'before callback retirement') end
 local removed=D.bridge(14,ui:GetAddress(),outgoingUI:GetAddress(),0)
 assert(removed>=0,'UI retirement failed '..removed)
 if D.recordUI then D.recordUI(13,'after callback retirement') end
 del.UniqueID=uid;ui.BtlUnitManager:HandleDestroyUnit(del)
 if D.recordUI then D.recordUI(14,'after outgoing character UI destroy') end
 assert(bridge(12,m,incoming)==1,'Incoming character UI deployment failed')
 D.log('SWAP stage=character-ui-rebuilt')
 if D.recordUI then D.recordUI(16,'after incoming character deploy') end
 local incomingUI=ui.BtlUnitManager:GetUnitParamVM(newuid)
 assert(valid(incomingUI) and valid(incomingUI.BtlUnitParam) and incomingUI.BtlUnitParam:GetAddress()==ip:GetAddress(),'Incoming UI did not bind to the character')
 assert(D.bridge(14,ui:GetAddress(),incomingUI:GetAddress(),1)>=0,'Incoming action UI has no valid parent')
 if S.lastTimeline then
  local event=StaticConstructObject(StaticFindObject('/Script/mucha.CPP_BtlTimelineUpdateDelVal'),m)
  if valid(event) then
   for field,values in pairs(S.lastTimeline) do
    local updated={};for _,value in ipairs(values) do updated[#updated+1]=value==uid and newuid or value end
    event[field]=updated
   end
   FindFirstOf('CPP_VM_BtlTimeLine'):HandleUpdateTimeline(event)
  end
 end
 vm:ClearCommandStack();vm:OpenCommand()
 D.log('SWAP stage=commands-refreshed')
 local after=snapshotActor(incoming)
 assert(before.hp==after.hp and before.mp==after.mp,'State changed during exchange')
 assert(table.concat(before.passives,',')==table.concat(after.passives,','),'Passives changed during exchange')
 D.log('TAG '..outID..' -> '..target..' hp='..after.hp..' mp='..after.mp..' cost='..tostring(S.cost)..' retired_ui_callbacks='..removed..' character_ui_only=true')
 if D.recordUI then D.recordUI(18,'swap completed') end
 if S.cost then vm:DecideActionKey({Category=1,ID=900000}) end
end
S.open=function()
 assert(IsInGameThread(),'Menu must run on the game thread')
 if S.pendingChoice then D.log('Menu blocked: confirmation pending');return end
 local dialogActive=cdo('CPP_BFL_Dialog'):IsDialogActive()
 if S.menu and not dialogActive then S.menu=nil;D.log('Cleared stale menu state') end
 if S.menu or dialogActive then D.log('Menu blocked: another dialog is active');return end
 D.log('MENU validating current command')
 local m,ui,vm,out=active();if not m then D.log('F7 unavailable: requires a normal command turn');return end
 if S.manager and (not valid(S.manager) or S.manager:GetAddress()~=m:GetAddress()) then S.cleanup() end
 S.manager=m
 local used={};for _,u in ipairs(array(m.m_UnitList)) do used[u.m_pUnitParameter:GetUnitId()]=true; if u.m_pUnitParameter:GetUnitId()<1010 and u.m_pUnitParameter:GetUnitId()>1000 then S.actors[u.m_pUnitParameter:GetUnitId()]=u end end
 D.log('MENU reading reserve roster')
 local entries={};local labels={};local roster={};cdo('CPP_BFL_SaveDataUnit'):GetSaveDataUnitParameterList(roster)
 for _,p in ipairs(array(roster)) do
  if p.JoinStatus==0 and p.IsUsable and not used[p.UnitId] then
   D.log('MENU candidate '..tostring(p.UnitId))
   local cached=S.actors[p.UnitId];local hp=p.HitPoint;local mp=p.MagicPoint
   if valid(cached) then hp=cached.m_pUnitParameter:GetHitPoint();mp=cached.m_pUnitParameter:GetMagicPoint() end
   if hp>0 and p.equipVisionId>0 then
    entries[#entries+1]=p.UnitId
    labels[#labels+1]=FText(name(p.UnitId)..' + '..name(p.equipVisionId)..'  |  HP '..hp..'  MP '..mp)
   end
  end
 end
 local toggle=#labels;labels[#labels+1]=FText('Swapping uses a turn: '..(S.cost and 'ON' or 'OFF'))
 local cancel=#labels;labels[#labels+1]=FText('Cancel')
 S.menu={entries=entries,labels=labels,toggle=toggle,cancel=cancel,out=out:GetAddress(),manager=m:GetAddress(),epoch=S.epoch,turn=out.m_pUnitParameter:GetActionCountInBattle()}
 D.log('MENU opening choices='..#entries)
 cdo('CPP_BFL_Dialog'):OpenChoiceDialog({TagName=FName('UI.Dialog.Choice.OK')})
end
if not S.hooks then
 S.hooks={}
 S.hooks.info={RegisterHook('/Script/mucha.CPP_BFL_Dialog:GetDialogChoiceInfo',function() end,function(ctx,ret,tag)
  if not S.menu or G.protect(G.protect(tag):get()).TagName:ToString()~='UI.Dialog.Choice.OK' then return end
  local r=G.protect(G.protect(ret):get());r.ChoiceTextList=S.menu.labels;r.DefaultIndex=0;r.CancelIndex=S.menu.cancel;return r
 end)}
 S.hooks.close={RegisterHook('/Script/mucha.CPP_DialogManager:HandleChoiceDialogClosed',function(ctx,result)
  local menu=S.menu;if not menu then return end
  D.log('MENU choice callback')
  S.menu=nil;local r=G.protect(G.protect(result):get());local index=r.ItemIndex
  D.log('MENU choice index='..tostring(index)..' decided='..tostring(r.IsDecided))
  if not r.IsDecided or index==menu.cancel then return end
  -- Store only scalar confirmation data across the delay, never remote params.
  local token={epoch=menu.epoch,manager=menu.manager,out=menu.out,turn=menu.turn,
   toggle=index==menu.toggle,target=menu.entries[index+1]}
  S.pendingChoice=token
  ExecuteInGameThreadWithDelay(150,function()
   if S.pendingChoice~=token then return end
   S.pendingChoice=nil
   D.attempt('choice action',function()
    local m,ui,vm,out=active()
    assert(m and S.epoch==token.epoch and m:GetAddress()==token.manager
     and out:GetAddress()==token.out and out.m_pUnitParameter:GetActionCountInBattle()==token.turn,
     'Turn or battle changed; selection discarded')
    assert(not cdo('CPP_BFL_Dialog'):IsDialogActive(),'Dialog is still active; selection discarded')
    if token.toggle then S.cost=not S.cost;if D.writeCost then D.writeCost(S.cost) end;S.open();return end
    assert(token.target,'Invalid choice');S.swap(token.target)
   end)
  end)
 end)}
 D.log('Combat Tag 0.1.4 ready: F7 / LB+RB; game-thread-only input and confirmation')
end
if not S.lifecycle then
 S.lifecycle=true
 RegisterHook('/Script/mucha.CPP_UI_BattleSubsystem:HandleBeginResult',function() D.attempt('sync reserves',S.syncBench) end)
 RegisterHook('/Script/mucha.CPP_UI_BattleSubsystem:HandleEndBtl',function()
  D.attempt('sync reserves',S.syncBench)
  D.attempt('clean reserves',S.cleanup)
 end)
 RegisterHook('/Script/mucha.CPP_UI_BattleSubsystem:HandleBeginGameOver',function() D.attempt('clean reserves',S.cleanup) end)
end
if not S.timelineHook then
 S.timelineHook=true
 RegisterHook('/Script/mucha.CPP_VM_BtlTimeLine:HandleUpdateTimeline',function(_,value)
  local ok=pcall(function()
    local v=G.protect(G.protect(value):get());S.lastTimeline={currentTimelines=array(v.currentTimelines),nextTimelines=array(v.nextTimelines),additionalTurnTimelines=array(v.additionalTurnTimelines)}
   end)
   if not ok then S.lastTimeline=nil;D.log('Timeline snapshot failed; cleared cached timeline') end
 end)
end
if not S.phaseAuditHook then
 S.phaseAuditHook=true
 RegisterHook('/Script/mucha.CPP_UI_BtlCmdManager:HandleBeginCommand',function() end,function()
  if S.swaps==0 or S.phaseAuditSwap==S.swaps then return end
  local ui=FindFirstOf('CPP_UI_BattleSubsystem')
  if valid(ui) and ui.bDuringBattle and ui.BtlPhaseType==1 then
   S.phaseAuditSwap=S.swaps
   D.log('Bonus-phase UI update completed after swap '..S.swaps)
  end
 end)
end
if not S.controllerLoop then
 S.controllerLoop=true
 local function requestOpen(label)
  if S.openPending or S.menu or S.pendingChoice then return end
  local token={epoch=S.epoch}
  S.openPending=token
  D.log(label..' received')
  ExecuteInGameThreadWithDelay(150,function()
   if S.openPending~=token then return end
   S.openPending=false
   if S.epoch==token.epoch then D.attempt(label,S.open) end
  end)
 end
 S.controllerHandle=LoopInGameThreadWithDelay(40,function()
  local ok,err=xpcall(function()
   local pc=S.pc
   if not valid(pc) then
    S.chordArmed=false;S.f7Down=false
    for _,p in ipairs(FindAllOf('PlayerController') or {}) do if p:IsLocalPlayerController() then pc=p;S.pc=p;break end end
   end
   if not valid(pc) then return end
   local f7=pc:IsInputKeyDown({KeyName=FName('F7')})
   if f7 and not S.f7Down then requestOpen('F7') end
   S.f7Down=f7
   local lb=pc:IsInputKeyDown({KeyName=FName('Gamepad_LeftShoulder')})
   local rb=pc:IsInputKeyDown({KeyName=FName('Gamepad_RightShoulder')})
   if lb and rb then S.chordArmed=true end
   if S.chordArmed and not lb and not rb then
    S.chordArmed=false;requestOpen('LB+RB')
   end
  end,debug.traceback)
  if not ok and not S.inputError then S.inputError=true;D.log('Controller poll error: '..tostring(err)) end
 end)
end
if modDir and not S.traceHooks then
 local path=modDir..'/Scripts/flight-recorder.lua'
 local f=io.open(path,'r')
 if f then f:close();D.attempt('start flight recorder',function() dofile(path)(D,S,modDir) end) end
end
return S
end

-- No work on the loading thread after this hand-off.
ExecuteInGameThread(function() D.attempt('initialize',initialize) end)
