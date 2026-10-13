import pathlib,subprocess,json,urllib.request,time,os,uuid,re
root=pathlib.Path(__file__).resolve().parent.parent
key=uuid.uuid4().hex
manifest=json.loads((root/'Resources/models.json').read_text())
model=pathlib.Path.home()/'Library/Application Support/Folio/Models'/next(x['file'] for x in manifest if x['id']=='writer')
log=open('/tmp/folio-memory-engine.log','w')
p=subprocess.Popen([str(root/'dist/Syllavane.app/Contents/Resources/Engines/llama/llama-server'),'-m',str(model),'--port','49254','--api-key',key,'-c','8192','--parallel','1','--jinja','--chat-template-kwargs','{"enable_thinking":false}'],stdout=log,stderr=log)
def req(path,data=None):
 return urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:49254'+path,data=None if data is None else json.dumps(data).encode(),headers={'Authorization':'Bearer '+key,'Content-Type':'application/json'}),timeout=120)
def obj(fields):return {'type':'object','properties':{k:{'type':'string'} for k in fields},'required':fields,'additionalProperties':False}
schema={'type':'object','properties':{'characters':{'type':'array','maxItems':12,'items':obj(['name','evidence'])},'relationships':{'type':'array','maxItems':16,'items':obj(['from','to','label','evidence'])}},'required':['characters','relationships'],'additionalProperties':False}
try:
 for _ in range(100):
  try:
   req('/health').close();break
  except Exception: time.sleep(.5)
 prompt='Mira meets her father Dev after ten years. I imagine her carefully setting down her bag, angry but unwilling to show it. Dev pours tea instead of apologizing. The room feels smaller than she remembers. Neither knows how to begin.'
 payload={'messages':[{'role':'system','content':json.loads(re.search(r'let output = try await models.complete\(system: ("(?:\\.|[^"\\])*")', (root/'Sources/FolioApp/Workspace.swift').read_text()).group(1))},{'role':'user','content':'Known names: Mira, Dev\nNarration:\n'+prompt}],'response_format':{'type':'json_schema','json_schema':{'name':'story_memory','strict':True,'schema':schema}},'max_tokens':1000,'temperature':.1,'chat_template_kwargs':{'enable_thinking':False}}
 result=json.load(req('/v1/chat/completions',payload));text=result['choices'][0]['message']['content'];print(text,flush=True)
 extraction=json.loads(text)
 assert {p['name'] for p in extraction['characters']}.issubset({'Mira','Dev'})
 assert any(r['evidence'] in prompt and r['from'] in ['Mira','Dev'] and r['to'] in ['Mira','Dev'] for r in extraction['relationships'])
 (root/'dist/memory-verification.json').write_text(json.dumps(extraction,indent=2))
finally:
 p.terminate();p.wait(timeout=10);log.close()
