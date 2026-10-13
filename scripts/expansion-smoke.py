"""Real-model test: actual production beat prompts, selection rules and expansion gate."""
import pathlib,tempfile,subprocess,json,urllib.request,time,uuid,os
root=pathlib.Path(__file__).resolve().parent.parent
notes="The next day Joseph couldn't understand what happened yesterday and how he should react for it. So he doesn't talk to his father George for... many days but certain days day comes that's his mother's anniversary, death anniversary."
schema={'type':'object','properties':{'sentences':{'type':'array','minItems':6,'maxItems':6,'items':{'type':'string'}}},'required':['sentences'],'additionalProperties':False}
with tempfile.TemporaryDirectory(prefix='folio-expand-') as directory:
 exe=pathlib.Path(directory)/'fixture'
 files=['Models.swift','Authoring.swift','NarrativeMemory.swift','WritingContext.swift','PromptBuilder.swift','Expansion.swift','AuthorMemory.swift','BookPDF.swift']
 subprocess.run(['swiftc','-o',str(exe)]+[str(root/'Sources/FolioCore'/f) for f in files]+[str(root/'scripts/expansion-fixture.swift')],check=True)
 def core(**data):return json.loads(subprocess.check_output([str(exe)],input=json.dumps(data).encode()))
 key=uuid.uuid4().hex;log=open('/tmp/folio-expanded-engine.log','w')
 process=subprocess.Popen([str(root/'dist/Syllavane.app/Contents/Resources/Engines/llama/llama-server'),'-m',os.environ.get('FOLIO_WRITER_TEST_PATH',str(pathlib.Path.home()/'Library/Application Support/Folio/Models'/next(x['file'] for x in json.loads((root/'Resources/models.json').read_text()) if x['id']=='writer'))),'--host','127.0.0.1','--port','49258','--api-key',key,'-c','8192','-ngl','99','--parallel','1','--jinja','--chat-template-kwargs','{"enable_thinking":false}'],stdout=log,stderr=log)
 def req(path,body=None):return urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:49258'+path,data=None if body is None else json.dumps(body).encode(),headers={'Authorization':'Bearer '+key,'Content-Type':'application/json'}),timeout=120)
 def complete(system,user,schema=None,seed=41):
  payload={'messages':[{'role':'system','content':system},{'role':'user','content':user}],'max_tokens':650 if schema else 180,'temperature':.65 if schema else .3,'repeat_penalty':1.0 if schema else 1.08,'seed':seed,'chat_template_kwargs':{'enable_thinking':False}}
  if schema:payload['response_format']={'type':'json_schema','json_schema':{'name':'candidates','strict':True,'schema':schema}}
  return json.load(req('/v1/chat/completions',payload))['choices'][0]['message']['content']
 try:
  for _ in range(150):
   try:req('/health').close();break
   except Exception:time.sleep(.3)
  beats=core(command='beats',notes=notes); paragraphs=[];records=[]
  for index,beat in enumerate(beats):
   context='\n'.join(beats[:index+1]);previous='\n\n'.join(paragraphs)
   prompt=core(command='prompt',notes=notes,anchor=beat,previous=previous,context='',style='Close third person, restrained emotion. Reveal uncertainty without resolving it.')
   edit=complete(prompt['anchorSystem'],'PRECEDING NOTES:\n'+'\n'.join(beats[:index])[-600:]+'\nBEAT:\n'+beat)
   anchor=core(command='anchor',notes=notes,beat=beat,text=edit,context=context)['text']
   usable=[];pool=[]
   for attempt in range(3):
    prompt=core(command='prompt',notes=notes,anchor=anchor,previous=previous,context='',style='Close third person, restrained emotion. Reveal uncertainty without resolving it.',retry=attempt>0)
    candidates=json.loads(complete(prompt['system'],prompt['user'],schema,seed=41+index+attempt))['sentences']
    pool+=candidates
    usable=core(command='select',notes=notes,beat=beat,context=context,previous=previous,candidates=pool)
    records.append({'beat':beat,'anchor':anchor,'attempt':attempt,'candidates':candidates,'selected':usable})
    if len(usable)>=2:break
   if not usable:print(json.dumps(records,indent=2),flush=True)
   assert usable,records[-1]
   paragraphs.append(anchor+' '+' '.join(usable))
  text='\n\n'.join(paragraphs);result=core(command='check',notes=notes,text=text,context='')
  print(json.dumps({'draft':text,'validation':result,'records':records},indent=2),flush=True)
  assert result['expanded'], 'The result is a copy edit instead of an expansion'
  assert not result['issues'],result['issues']
  assert len(text.split())>len(notes.split())*1.5
  (root/'dist/expansion-verification.json').write_text(json.dumps({'notes':notes,'draft':text,'validation':result,'records':records},indent=2))
 finally:process.terminate();process.wait(timeout=10);log.close()
