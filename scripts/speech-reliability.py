"""Offline speech fixtures. Synthetic fixtures test the engine, not microphone hardware."""
import pathlib, subprocess, tempfile, json, uuid, time, urllib.request, urllib.error, os, wave, re, random, math, array, sys
root = pathlib.Path(__file__).resolve().parent.parent
spec = next(x for x in json.loads((root/'Resources/models.json').read_text()) if x['id']=='speech')
port = 49263; token = uuid.uuid4().hex
records = []
with tempfile.TemporaryDirectory(prefix='syllavane-speech-') as tmp:
    directory = pathlib.Path(tmp)
    log = open(directory/'engine.log','w')
    process = subprocess.Popen([str(root/'dist/Syllavane.app/Contents/Resources/Engines/whisper/whisper-server'),'-m',str(pathlib.Path.home()/'Library/Application Support/Folio/Models'/spec['file']),'--host','127.0.0.1','--port',str(port),'-t','4','-l','en'],stdout=log,stderr=log,env={**os.environ,'FOLIO_ENGINE_TOKEN':token})
    def request(path, data=None, content=None, authorized=True):
        headers = {'Authorization':'Bearer '+token} if authorized else {}
        if content: headers['Content-Type'] = content
        return urllib.request.urlopen(urllib.request.Request(f'http://127.0.0.1:{port}'+path,data=data,headers=headers),timeout=90)
    def transcribe(wav):
        boundary = 'Fixture'+uuid.uuid4().hex
        body = b''
        for name,value in [('response_format','json'),('language','en'),('temperature','0.0'),('suppress_non_speech','true'),('prompt','Names: Joseph, George, Mira, Dev')]:
            body += f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="fixture.wav"\r\nContent-Type: audio/wav\r\n\r\n'.encode()+wav+f'\r\n--{boundary}--\r\n'.encode()
        with request('/inference',body,'multipart/form-data; boundary='+boundary) as response: return json.load(response)['text'].strip()
    try:
        for _ in range(180):
            if process.poll() is not None: raise RuntimeError('Speech engine exited')
            try:
                with request('/') as response:
                    if response.status == 200: break
            except urllib.error.URLError: time.sleep(.3)
        for index,text in enumerate([
            "Joseph could not understand what happened yesterday. He did not speak to his father George for many days, until his mother's death anniversary.",
            "Mira sees her father Dev after ten years. She is angry but hides it. Neither speaks yet.",
            "Tone down this paragraph. Keep the uncertainty. Do not add a reason for what happened."
        ]):
            aiff=directory/f'{index}.aiff'; wav=directory/f'{index}.wav'
            subprocess.run(['say','-o',str(aiff),text],check=True)
            subprocess.run(['afconvert','-f','WAVE','-d','LEI16@16000','-c','1',str(aiff),str(wav)],check=True)
            start=time.monotonic(); result=transcribe(wav.read_bytes())
            words=lambda s:set(re.findall(r"[a-z]+",s.lower()))
            coverage=len(words(text)&words(result))/len(words(text))
            assert coverage>=.8,(text,result,coverage)
            if index==0: assert 'joseph' in result.lower() and 'george' in result.lower() and 'anniversary' in result.lower()
            records.append({'input':text,'transcript':result,'word_coverage':coverage,'seconds':round(time.monotonic()-start,2)})
        # Controlled noise fixtures exercise recognition under reproducible degradation.
        with wave.open(str(directory/'0.wav'),'rb') as source:
            params=source.getparams(); pcm=array.array('h',source.readframes(source.getnframes()))
        if sys.byteorder!='little': pcm.byteswap()
        rms=math.sqrt(sum(x*x for x in pcm)/len(pcm))
        expected=records[0]['input']
        for snr in [20,10]:
            generator=random.Random(snr)
            sigma=rms/(10**(snr/20))
            noisy=array.array('h',(max(-32768,min(32767,round(x+generator.gauss(0,sigma)))) for x in pcm))
            if sys.byteorder!='little': noisy.byteswap()
            path=directory/f'noise-{snr}.wav'
            with wave.open(str(path),'wb') as destination:
                destination.setparams(params);destination.writeframes(noisy.tobytes())
            start=time.monotonic();result=transcribe(path.read_bytes())
            coverage=len(words(expected)&words(result))/len(words(expected))
            assert coverage>=.8,(snr,result,coverage)
            assert 'joseph' in result.lower() and 'george' in result.lower() and 'anniversary' in result.lower()
            records.append({'input':expected,'fixture':f'white noise {snr} dB SNR','transcript':result,'word_coverage':coverage,'seconds':round(time.monotonic()-start,2)})
        for route,body,content,auth in [('/inference',None,None,False),('/inference',b'bad audio','application/octet-stream',True)]:
            try: request(route,body,content,auth); raise AssertionError('Invalid request accepted')
            except urllib.error.HTTPError as error: assert error.code in ([401] if not auth else [400,415,422,500]),error.code
        (root/'dist/speech-evaluation.json').write_text(json.dumps({'fixtures':records,'auth':'passed','invalid_audio':'passed','hardware_microphone':'not covered'},indent=2))
        print(json.dumps(records,indent=2))
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill();process.wait()
        log.close()
