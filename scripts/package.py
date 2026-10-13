import pathlib,shutil,subprocess,plistlib,re,os
root=pathlib.Path(__file__).resolve().parent.parent
app=root/'dist/Syllavane.app'; contents=app/'Contents'; resources=contents/'Resources'
resources.mkdir(parents=True,exist_ok=True); (contents/'MacOS').mkdir(exist_ok=True)
binpath=subprocess.check_output(['swift','build','-c','release','--show-bin-path'],cwd=root,text=True).strip().splitlines()[-1]
shutil.copy2(pathlib.Path(binpath)/'Folio',contents/'MacOS/Folio')
for file in ['models.json','AppIcon.icns','THIRD_PARTY.md']:
 if (root/'Resources'/file).exists(): shutil.copy2(root/'Resources'/file,resources/file)
shutil.copytree(root/'Resources/Licenses',resources/'Licenses',dirs_exist_ok=True)
shutil.copy2(root/'LICENSE',resources/'Licenses/Folio-MIT.txt')
for engine in ['llama','whisper']:
 dest=resources/'Engines'/engine
 if dest.exists(): shutil.rmtree(dest)
 dest.mkdir(parents=True)
 source=root/'vendor'/engine/'build/bin'
 for path in source.iterdir():
  if path.suffix=='.dylib' or path.name==engine+'-server':
   if path.is_symlink(): os.symlink(os.readlink(path),dest/path.name)
   else: shutil.copy2(path,dest/path.name)
 for path in dest.iterdir():
  if path.is_symlink(): continue
  load=subprocess.check_output(['otool','-l',str(path)],text=True)
  paths=re.findall(r'cmd LC_RPATH\n\s*cmdsize \d+\n\s*path (.*?) \(offset',load)
  for rp in paths:
   if not rp.startswith('@'): subprocess.run(['install_name_tool','-delete_rpath',rp,str(path)],check=True,capture_output=True)
  if '@loader_path' not in paths: subprocess.run(['install_name_tool','-add_rpath','@loader_path',str(path)],check=True,capture_output=True)
  deps=subprocess.check_output(['otool','-L',str(path)],text=True)
  if '/opt/homebrew/' in deps: raise RuntimeError('Unbundled dependency: '+str(path))
  subprocess.run(['codesign','--force','--sign','-',str(path)],check=True,capture_output=True)
plist={'CFBundleName':'Syllavane','CFBundleDisplayName':'Syllavane','CFBundleIdentifier':'studio.folio.writer','CFBundleVersion':'11','CFBundleShortVersionString':'0.11.0','CFBundleExecutable':'Folio','CFBundlePackageType':'APPL','CFBundleIconFile':'AppIcon','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'NSMicrophoneUsageDescription':'Syllavane uses your microphone to transcribe scene directions entirely on this Mac. Audio is never sent to a cloud service.','NSAppTransportSecurity':{'NSAllowsLocalNetworking':True},'NSPrincipalClass':'NSApplication','NSSupportsAutomaticGraphicsSwitching':True}
with (contents/'Info.plist').open('wb') as f: plistlib.dump(plist,f)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(app)
