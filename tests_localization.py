"""Check bilingual notification lookup and sorting behavior in emulated Lua 5.1."""
from pathlib import Path
import xml.etree.ElementTree as ET
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parent
for language in ['en','de']:
 texts={t.attrib['name']:t.attrib['text'] for t in ET.parse(root/f'l10n/l10n_{language}.xml').findall('texts/text')}
 assert set(texts)=={'input_CDS_SORT_CONTRACTS','cds_sortComplete','cds_noContracts'}
 lua=LuaRuntime(unpack_returned_tuples=True)
 lua.globals().translated=lambda key,env: texts[key] if env=='CDS' else (_ for _ in ()).throw(AssertionError(env))
 lua.execute('''
g_currentModName='CDS'; Logging={info=function()end}; PlayerInputComponent={}; Utils={appendedFunction=function()return function()end end}
FSBaseMission={INGAME_NOTIFICATION_OK=1};MissionStatus={RUNNING=1,FINISHED=2}
g_localPlayer={rootNode=1};getWorldTranslation=function()return 0,0,0 end
g_i18n={getText=function(self,key,env)return translated(key,env)end,getDistance=function()return 1 end}
created={};notices={};missions={}
g_currentMission={getFarmId=function()return 1 end,addIngameNotification=function(self,kind,msg)table.insert(notices,msg)end,
 hud={removeSideNotificationProgressBar=function()end,markSideNotificationProgressBarForDrawing=function()end,
 addSideNotificationProgressBar=function(self,title,text,progress)table.insert(created,title);return {title=title,text=text,progress=progress}end}}
g_missionManager={getMissionsByFarmId=function()return missions end}
''')
 lua.execute((root/'scripts/ContractDistanceSort.lua').read_text(encoding='utf-8'))
 lua.execute('''
ContractDistanceSort.sortActiveContracts()
assert(notices[1]==g_i18n:getText('cds_noContracts','CDS'))
function mission(title,x) return {farmId=1,status=1,progressBar={title=title,text='',progress=0.5},getWorldPosition=function()return x,0 end} end
missions={mission('Far',100),mission('Near',10)}
ContractDistanceSort.sortActiveContracts()
assert(created[1]=='Near — 10 m' and created[2]=='Far — 100 m')
assert(missions[1].progressBar.title=='Far — 100 m')
assert(notices[2]==g_i18n:getText('cds_sortComplete','CDS'))
ContractDistanceSort.sortActiveContracts()
assert(created[3]=='Near — 10 m')
''')
print('PASS English/German notification scope, empty contracts, nearest-first sorting and repeat sorting')
