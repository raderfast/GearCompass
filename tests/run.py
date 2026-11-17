"""Run the addon in Lua 5.1, without a WoW installation."""
import sys
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.tools'))
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
fg = lua.table()
for file in ROOT.glob('*.lua'):
    lua.execute('assert(loadstring(...))', file.read_text(encoding='utf-8'))
for name in ('Core.lua', 'ATT.lua', 'Pawn.lua', 'Search.lua'):
    lua.execute((ROOT / name).read_text(encoding='utf-8'), 'GearCompass', fg)
lua.execute((ROOT / 'tests' / 'spec.lua').read_text(encoding='utf-8'), fg, (ROOT / 'Search.lua').read_text(encoding='utf-8'))
lua.execute((ROOT / 'Search.lua').read_text(encoding='utf-8'), 'GearCompass', fg)
lua.execute((ROOT / 'tests' / 'performance.lua').read_text(encoding='utf-8'), fg)
print('PASS: Lua 5.1 syntax, scoring, priorities, ATT catalog and async search')

for line in (ROOT / 'GearCompass.toc').read_text(encoding='utf-8').splitlines():
    if line.strip() and not line.startswith('#'):
        assert (ROOT / line.strip()).is_file(), line
bootstrap = LuaRuntime(unpack_returned_tuples=True)
bootstrap.execute('''
    SlashCmdList={}
    CreateFrame=function()
        return {RegisterEvent=function() end, SetScript=function(_,_,fn) onAddonLoaded=fn end}
    end
''')
namespace = bootstrap.table()
for name in ('Core.lua', 'UI.lua'):
    bootstrap.execute((ROOT / name).read_text(encoding='utf-8'), 'GearCompass', namespace)
bootstrap.execute('''
    onAddonLoaded(nil,"ADDON_LOADED","GearCompass")
    assert(GearCompass and GearCompassDB and GearCompassDB.weights)
    assert(SLASH_GEARCOMPASS1=="/gc" and SLASH_GEARCOMPASS2=="/gearcompass")
    assert(SlashCmdList.GEARCOMPASS==GearCompass.Open)
''')
print('PASS: GearCompass TOC paths, addon initialization, saved variables and slash commands')

pawn_test = LuaRuntime(unpack_returned_tuples=True)
pawn_namespace = pawn_test.table()
for name in ('Core.lua', 'ATT.lua', 'Pawn.lua', 'Search.lua'):
    pawn_test.execute((ROOT / name).read_text(encoding='utf-8'), 'GearCompass', pawn_namespace)
pawn_test.execute((ROOT / 'tests/pawn.lua').read_text(encoding='utf-8'), pawn_namespace)

ui_test = LuaRuntime(unpack_returned_tuples=True)
ui_test.execute((ROOT / 'tests/ui.lua').read_text(encoding='utf-8'))
ui_namespace = ui_test.table()
for name in ('Core.lua', 'Pawn.lua', 'UI.lua'):
    ui_test.execute((ROOT / name).read_text(encoding='utf-8'), 'GearCompass', ui_namespace)
ui_test.execute('runUITest(...)', ui_namespace)

if len(sys.argv) > 1:
    # Execute real Camelot (Forever) data with stub object constructors.
    # This checks data shape; it does not emulate ATT startup or WoW.
    reference = Path(sys.argv[1]) / 'AllTheThings'
    real = LuaRuntime(unpack_returned_tuples=True)
    app = real.execute((ROOT / 'tests' / 'att_reference.lua').read_text(encoding='utf-8'))
    for file in sorted((reference / 'db/Camelot/Categories').glob('*.lua')):
        real.execute('local code,name,app=...; assert(loadstring(code,name))("AllTheThings",app)', file.read_text(encoding='utf-8-sig'), '@' + str(file), app)
    real.execute('local app=...; for _,fn in ipairs(app.handlers) do fn(app.categories) end; app.index()', app)
    adapter = real.table()
    real.execute((ROOT / 'ATT.lua').read_text(encoding='utf-8'), 'GearCompass', adapter)
    catalog, skipped = adapter.Provider.Collect(app)
    count = len(list(catalog.keys()))
    assert count > 1000, count
    print(f'PASS: real ATT Forever data with stub constructors: {count} unique item IDs; {skipped} excluded references')

if len(sys.argv) > 2:
    # Run actual Pawn scoring/scale API functions; mock only tooltip acquisition
    # and the WoW host. Pawn's entire UI/startup is not emulated by this test.
    source = (Path(sys.argv[2]) / 'Pawn.lua').read_text(encoding='utf-8-sig')
    functions = []
    for name in ('PawnIsReady', 'PawnGetAllScalesEx', 'PawnGetAllScalesExComparer',
                 'PawnGetScaleTag', 'PawnGetScaleLocalizedName',
                 'PawnGetSingleValueFromItem', 'PawnGetItemValue'):
        match = re.search(r'^function ' + name + r'\([^\n]*\).*?^end\s*$', source, re.M | re.S)
        assert match, name
        functions.append(match.group())
    real_pawn = LuaRuntime(unpack_returned_tuples=True)
    host = (ROOT / 'tests/pawn_reference.lua').read_text(encoding='utf-8')
    real_pawn.execute(host + '\n' + '\n'.join(functions))
    adapter = real_pawn.table()
    real_pawn.execute((ROOT / 'Pawn.lua').read_text(encoding='utf-8'), 'GearCompass', adapter)
    real_pawn.execute('''
        local gc=...
        assert(#gc.Pawn.Scales()==2)
        local scorer=assert(gc.Pawn.CreateScorer("A"))
        assert(scorer.Score("item:1")==21)
        PawnCommon.Scales.A.Values.Strength=4
        assert(not scorer.Validate())
    ''', adapter)
    print('PASS: actual Pawn scale listing, export tags and base score calculation (tooltip data stubbed)')
