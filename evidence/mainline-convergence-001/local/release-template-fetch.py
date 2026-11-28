import io, urllib.request, zipfile, hashlib, json, zlib
from pathlib import Path
URL='https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
root=Path('/tmp/xeno-release-template')
head=urllib.request.urlopen(urllib.request.Request(URL,method='HEAD'),timeout=30)
asset_url=head.url
size=int(head.headers['Content-Length'])
class RemoteZip(io.RawIOBase):
    def __init__(self): self.pos=0; self.bytes=0; self.requests=0
    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos
    def seek(self,offset,whence=io.SEEK_SET):
        self.pos=offset if whence==io.SEEK_SET else self.pos+offset if whence==io.SEEK_CUR else size+offset
        return self.pos
    def read(self,n=-1):
        if n<0: n=size-self.pos
        n=min(n,size-self.pos)
        if n<=0:return b''
        end=self.pos+n-1
        req=urllib.request.Request(asset_url,headers={'Range':f'bytes={self.pos}-{end}'})
        with urllib.request.urlopen(req,timeout=90) as response:
            if response.status!=206: raise RuntimeError(f'Range not honored: {response.status}')
            raw=response.read(n+1)
        if len(raw)!=n: raise RuntimeError(f'Range length {len(raw)} != {n}')
        self.pos+=n; self.bytes+=n; self.requests+=1
        return raw
remote=RemoteZip()
with zipfile.ZipFile(remote) as archive:
    names=[x.filename for x in archive.infolist() if x.filename.endswith('/linux_release.x86_64') or x.filename=='linux_release.x86_64']
    if len(names)!=1: raise RuntimeError(str(names))
    info=archive.getinfo(names[0])
    print('Retrieving',info.filename,'compressed',info.compress_size,'uncompressed',info.file_size,flush=True)
    payload=archive.read(info)
    target=root/'linux_release.x86_64'
    target.write_bytes(payload);target.chmod(0o755)
    receipt={'official_asset_url':URL,'archive_bytes':size,'archive_full_sha256':'not recomputed: only exact member range retrieved','member':info.filename,'compressed_bytes':info.compress_size,'member_bytes':len(payload),'member_crc32':f'{zlib.crc32(payload)&0xffffffff:08x}','central_directory_crc32':f'{info.CRC:08x}','member_sha256':hashlib.sha256(payload).hexdigest(),'range_requests':remote.requests,'downloaded_bytes':remote.bytes}
    (root/'download-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps(receipt,indent=2),flush=True)
