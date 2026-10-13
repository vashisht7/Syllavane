import pathlib,json,subprocess,time,urllib.request,urllib.error,uuid,os,math
root=pathlib.Path(__file__).resolve().parent.parent
models=pathlib.Path.home()/'Library/Application Support/Folio/Models'
manifest={x['id']:x for x in json.loads((root/'Resources/models.json').read_text())}
processes=[];logs=[];token=uuid.uuid4().hex
ports={'writer':49251,'embedding':49252,'speech':49253}
results={}
def request(kind,path,body=None,headers=None):
 h={'Authorization':'Bearer '+token};h.update(headers or {})
 if isinstance(body,dict): body=json.dumps(body).encode();h['Content-Type']='application/json'
 return urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:'+str(ports[kind])+path,data=body,headers=h),timeout=120)
def boot(kind,args):
 engine='whisper' if kind=='speech' else 'llama'
 packaged=root/'dist/Syllavane.app/Contents/Resources/Engines'/engine/(engine+'-server')
 executable=packaged if packaged.exists() else root/'vendor'/engine/'build/bin'/(engine+'-server')
 log=open('/tmp/folio-smoke-'+kind+'.log','w');logs.append(log)
 p=subprocess.Popen([str(executable),'-m',str(models/manifest[kind]['file']),'--host','127.0.0.1','--port',str(ports[kind])]+args,stdout=log,stderr=log,env={**os.environ,'FOLIO_ENGINE_TOKEN':token});processes.append(p)
 for i in range(180):
  if p.poll() is not None: raise RuntimeError(kind+' exited; see log')
  try:
   with request(kind,'/' if kind=='speech' else '/health') as response:
    if response.status==200: return
  except (urllib.error.URLError,TimeoutError): pass
  time.sleep(.5)
 raise RuntimeError(kind+' did not become ready')
try:
 boot('writer',['--api-key',token,'-c','8192','-ngl','99','-t','4','--parallel','1','--jinja','--chat-template-kwargs','{"enable_thinking":false}'])
 started=time.monotonic()
 with request('writer','/v1/chat/completions',{'messages':[{'role':'system','content':'Write only finished fiction prose. Close third person, restrained emotion, no invented backstory. /no_think'},{'role':'user','content':'Write 100 words: Mira meets her father after ten years. She is angry but hides it. They sit down for tea. End before either speaks.'}],'max_tokens':250,'temperature':.4,'stream':True,'chat_template_kwargs':{'enable_thinking':False}}) as response:
  chunks=[];first=None
  for line in response:
   if line.startswith(b'data: ') and b'[DONE]' not in line:
    event=json.loads(line[6:]);delta=event['choices'][0].get('delta',{}).get('content','') or ''
    if delta and first is None:first=time.monotonic()-started
    chunks.append(delta)
  text=''.join(chunks)
  assert len(text)>100,text
  results['writing']={'first_token_seconds':round(first or 0,2),'total_seconds':round(time.monotonic()-started,2),'output':text}
 print('Writing stream passed',flush=True)
 boot('embedding',['--api-key',token,'--embedding','--pooling','mean','-c','512','-b','512','-ub','512','-ngl','99','--parallel','1'])
 vectors=[]
 for text in ['She hides her anger behind a polite smile.','He conceals his fury while greeting his father.','The spaceship landed on a frozen planet.']:
  with request('embedding','/v1/embeddings',{'input':text,'model':'local'}) as response: vectors.append(json.load(response)['data'][0]['embedding'])
 def cosine(a,b):return sum(x*y for x,y in zip(a,b))/(math.sqrt(sum(x*x for x in a))*math.sqrt(sum(y*y for y in b)))
 related=cosine(vectors[0],vectors[1]);unrelated=cosine(vectors[0],vectors[2]);assert related>unrelated
 results['embeddings']={'dimensions':len(vectors[0]),'related_similarity':related,'unrelated_similarity':unrelated}
 print('Semantic retrieval passed',flush=True)
 boot('speech',['-t','4','-l','en'])
 boundary='FolioSmoke'+uuid.uuid4().hex
 body=('--'+boundary+'\r\nContent-Disposition: form-data; name="response_format"\r\n\r\njson\r\n--'+boundary+'\r\nContent-Disposition: form-data; name="file"; filename="sample.wav"\r\nContent-Type: audio/wav\r\n\r\n').encode()+(root/'vendor/whisper/samples/jfk.wav').read_bytes()+('\r\n--'+boundary+'--\r\n').encode()
 started=time.monotonic()
 with request('speech','/inference',body,{'Content-Type':'multipart/form-data; boundary='+boundary}) as response: transcript=json.load(response)['text']
 assert 'country' in transcript.lower(),transcript
 results['speech']={'seconds':round(time.monotonic()-started,2),'transcript':transcript}
 try:
  urllib.request.urlopen('http://127.0.0.1:'+str(ports['speech'])+'/inference',timeout=2)
  raise AssertionError('Unauthenticated speech request was not rejected')
 except urllib.error.HTTPError as e: assert e.code==401
 results['speech_auth']='passed'
 print('Offline speech transcription and auth passed',flush=True)
 (root/'dist/verification.json').write_text(json.dumps(results,indent=2))
finally:
 for process in processes:
  process.terminate()
 for process in processes:
  try:process.wait(timeout=5)
  except subprocess.TimeoutExpired:process.kill();process.wait()
 for log in logs:log.close()
