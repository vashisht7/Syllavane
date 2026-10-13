import urllib.request,json,pathlib,hashlib,time,sys
root=pathlib.Path(__file__).resolve().parent.parent
out=pathlib.Path.home()/'Library/Application Support/Folio/Models'
out.mkdir(parents=True,exist_ok=True)
specs=[('writer','bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF','Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf','Qwen3 · 4B Instruct · Q4'),('embedding','second-state/All-MiniLM-L6-v2-Embedding-GGUF','all-MiniLM-L6-v2-ggml-model-f16.gguf','MiniLM · semantic search'),('speech','ggerganov/whisper.cpp','ggml-small.en.bin','Whisper Small · English')]
manifest_path=root/'Resources/models.json'
if manifest_path.exists() and '--refresh-manifest' not in sys.argv:
 manifest=json.loads(manifest_path.read_text())
else:
 manifest=[]
 for kind,repo,file,label in specs:
  data=json.load(urllib.request.urlopen('https://huggingface.co/api/models/'+repo+'?blobs=true'))
  entry=next(x for x in data['siblings'] if x['rfilename']==file)
  manifest.append(dict(id=kind,name=label,file=file,url='https://huggingface.co/'+repo+'/resolve/'+data['sha']+'/'+file,sha256=entry['lfs']['sha256'],bytes=entry['size'],license='Apache-2.0' if kind!='speech' else 'MIT'))
 (root/'Resources/models.json').write_text(json.dumps(manifest,indent=2))
for spec in manifest:
 dest=out/spec['file']
 if dest.exists() and dest.stat().st_size==spec['bytes']:
  digest=hashlib.sha256()
  with dest.open('rb') as f:
   for block in iter(lambda:f.read(1024*1024),b''): digest.update(block)
  if digest.hexdigest()==spec['sha256']:
   print('Verified existing',spec['name'],flush=True); continue
 print('Downloading',spec['name'],spec['bytes'],flush=True)
 temp=dest.with_suffix('.partial')
 for attempt in range(3):
  try:
   urllib.request.urlretrieve(spec['url'],temp)
   digest=hashlib.sha256()
   with temp.open('rb') as f:
    for block in iter(lambda:f.read(1024*1024),b''): digest.update(block)
   if digest.hexdigest()!=spec['sha256']: raise RuntimeError('Checksum mismatch')
   temp.replace(dest); print('Verified',dest.name,flush=True); break
  except Exception:
   if attempt==2: raise
   time.sleep(2)
