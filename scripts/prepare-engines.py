import pathlib,json,urllib.request,hashlib,subprocess
root=pathlib.Path(__file__).resolve().parent.parent
vendor=root/'vendor';vendor.mkdir(exist_ok=True)
for item in json.loads((root/'Resources/engines.json').read_text()):
 destination=vendor/item['name']
 if (destination/'CMakeLists.txt').exists(): continue
 archive=vendor/(item['name']+'.tar.gz')
 if not archive.exists(): urllib.request.urlretrieve('https://api.github.com/repos/'+item['repo']+'/tarball/'+item['tag'],archive)
 if hashlib.sha256(archive.read_bytes()).hexdigest()!=item['sha256']: raise RuntimeError('Source archive checksum mismatch: '+item['name'])
 destination.mkdir(exist_ok=True)
 subprocess.run(['tar','-xzf',str(archive),'-C',str(destination),'--strip-components=1'],check=True)
