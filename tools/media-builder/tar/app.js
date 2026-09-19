(() => {
  "use strict";
  const $ = id => document.getElementById(id);
  const ui = {drop:$("drop"),choose:$("choose"),openTar:$("openTar"),files:$("files"),tarFile:$("tarFile"),tracks:$("tracks"),summary:$("summary"),clear:$("clear"),name:$("name"),artist:$("artist"),cover:$("cover"),coverPreview:$("coverPreview"),build:$("build"),download:$("download"),status:$("status")};
  const state={files:[],url:"",coverBytes:null}, allowed=/\.(mp3|ogg|flac|wav)$/i;
  const encoder=new TextEncoder(),decoder=new TextDecoder();
  const cleanName=name=>name.replace(/[\\/:*?"<>|\u0000-\u001f]+/g,"_");
  const baseName=name=>name.replace(/\.[^.]+$/,"");
  const size=n=>n<1048576?(n/1024).toFixed(0)+" KiB":(n/1048576).toFixed(1)+" MiB";

  function invalidate(){if(state.url)URL.revokeObjectURL(state.url);state.url="";ui.download.hidden=true}
  function move(from,to){const file=state.files.splice(from,1)[0];state.files.splice(to,0,file);invalidate();render()}
  function render(){
    ui.tracks.replaceChildren();
    state.files.forEach((file,i)=>{
      const li=document.createElement("li");li.className="track";
      const label=document.createElement("span");label.className="track-name";label.textContent=file.name+" · "+size(file.size);
      const controls=document.createElement("span");controls.className="controls";
      [["↑",-1],["↓",1]].forEach(([text,direction])=>{const button=document.createElement("button");button.textContent=text;button.disabled=direction<0?i===0:i===state.files.length-1;button.onclick=()=>move(i,i+direction);controls.append(button)});
      const remove=document.createElement("button");remove.textContent="Remove";remove.onclick=()=>{state.files.splice(i,1);invalidate();render()};controls.append(remove);
      li.append(label,controls);ui.tracks.append(li);
    });
    ui.summary.textContent=state.files.length?state.files.length+" track"+(state.files.length===1?"":"s")+" · "+size(state.files.reduce((n,file)=>n+file.size,0)):"No tracks added.";
    ui.clear.disabled=!state.files.length;ui.build.disabled=!state.files.length;
  }
  function add(files){const accepted=[...files].filter(file=>allowed.test(file.name)),room=255-state.files.length,added=accepted.slice(0,room);state.files.push(...added);invalidate();render();ui.status.textContent=added.length?added.length+" file"+(added.length===1?"":"s")+" added."+(accepted.length>added.length?" "+(accepted.length-added.length)+" rejected: playlists support at most 255 tracks.":""):"No supported audio files were selected."}

  function showCover(bytes){
    const context=ui.coverPreview.getContext("2d"),image=context.createImageData(92,92);
    for(let i=0;i<8464;i++){const value=bytes?bytes[i]:0,j=i*4;image.data[j]=((value>>5)&7)*255/7;image.data[j+1]=((value>>2)&7)*255/7;image.data[j+2]=(value&3)*255/3;image.data[j+3]=255}
    context.putImageData(image,0,0);
  }
  async function setCover(file){
    if(!file){state.coverBytes=null;showCover(null);invalidate();return}
    const bitmap=await createImageBitmap(file),canvas=document.createElement("canvas");canvas.width=92;canvas.height=92;
    const context=canvas.getContext("2d",{willReadFrequently:true}),scale=Math.min(92/bitmap.width,92/bitmap.height);
    const width=Math.max(1,Math.round(bitmap.width*scale)),height=Math.max(1,Math.round(bitmap.height*scale));
    context.fillStyle="#000";context.fillRect(0,0,92,92);context.drawImage(bitmap,(92-width)>>1,(92-height)>>1,width,height);bitmap.close();
    const rgba=context.getImageData(0,0,92,92).data,bytes=new Uint8Array(8464);
    for(let i=0;i<8464;i++)bytes[i]=((rgba[i*4]>>5)<<5)|((rgba[i*4+1]>>5)<<2)|(rgba[i*4+2]>>6);
    state.coverBytes=bytes;showCover(bytes);invalidate();
  }

  function octal(n,width){const text=Math.floor(n).toString(8);if(text.length>width-1)throw Error("A file is too large for this USTAR profile.");return "0".repeat(width-1-text.length)+text+"\0"}
  function put(out,offset,length,text){const bytes=encoder.encode(text);if(bytes.length>length)throw Error("A filename is longer than the USTAR 100-byte limit.");out.set(bytes,offset)}
  function header(name,file){
    const out=new Uint8Array(512);put(out,0,100,name);put(out,100,8,"0000644\0");put(out,108,8,"0000000\0");put(out,116,8,"0000000\0");put(out,124,12,octal(file.size,12));put(out,136,12,octal(Math.floor(file.lastModified/1000)||0,12));out.fill(32,148,156);out[156]=48;
    put(out,257,6,"ustar\0");put(out,263,2,"00");put(out,265,32,"MiSTer");put(out,297,32,"MiSTer");let sum=0;for(const byte of out)sum+=byte;put(out,148,8,sum.toString(8).padStart(6,"0")+"\0 ");return out;
  }
  const pad=n=>new Uint8Array((512-n%512)%512);
  function kind(name){const ext=(name.match(/\.([^.]+)$/)||[])[1]?.toLowerCase();return ext==="mp3"?1:ext==="wav"?2:ext==="flac"?3:ext==="ogg"?4:0}
  function uniqueNames(files){const used=new Set();return files.map(file=>{const name=cleanName(file.name);let candidate=name,number=2;while(used.has(candidate.toLowerCase())){const dot=name.lastIndexOf(".");candidate=(dot<0?name:name.slice(0,dot))+" ("+number+++ ")"+(dot<0?"":name.slice(dot))}used.add(candidate.toLowerCase());return candidate})}

  function tarText(bytes,offset,length){let end=offset;while(end<offset+length&&bytes[end])end++;return decoder.decode(bytes.subarray(offset,end))}
  function tarOctal(bytes,offset,length){const text=tarText(bytes,offset,length).trim().replace(/\0/g,"");if(!/^[0-7]*$/.test(text))throw Error("The TAR contains an invalid numeric header field.");return text?parseInt(text,8):0}
  function parseTar(bytes){
    const entries=[];let offset=0;
    while(offset+512<=bytes.length){
      const block=bytes.subarray(offset,offset+512);if(block.every(byte=>byte===0))break;
      const name=tarText(block,0,100),prefix=tarText(block,345,155),fullName=prefix?prefix+"/"+name:name;
      const fileSize=tarOctal(block,124,12),modified=tarOctal(block,136,12)*1000,dataOffset=offset+512;
      if(!name||dataOffset+fileSize>bytes.length)throw Error("The TAR is truncated or has an invalid member header.");
      entries.push({name:fullName,size:fileSize,modified,dataOffset});offset=dataOffset+Math.ceil(fileSize/512)*512;
    }
    return entries;
  }
  async function openPlaylistTar(file){
    try{
      invalidate();ui.status.textContent="Opening "+file.name+"…";
      const bytes=new Uint8Array(await file.arrayBuffer()),entries=parseTar(bytes);
      const manifest=entries.find(entry=>/\.m3u$/i.test(entry.name));
      if(!manifest)throw Error("This is not a mixed playlist TAR: an M3U file is missing.");
      const manifestText=decoder.decode(bytes.subarray(manifest.dataOffset,manifest.dataOffset+manifest.size));
      const listed=manifestText.split(/\r?\n/).map(line=>line.trim()).filter(line=>line&&!line.startsWith("#"));
      const audioEntries=entries.filter(entry=>allowed.test(entry.name));
      if(!listed.length||listed.length>255||audioEntries.length!==listed.length)throw Error("The M3U and TAR audio-entry counts do not match, or exceed 255 tracks.");
      const normalized=name=>name.replace(/\\/g,"/").toLowerCase(),byName=new Map();
      for(const entry of audioEntries){const key=normalized(entry.name);if(byName.has(key))throw Error("Duplicate TAR filename: "+entry.name);byName.set(key,entry)}
      const restored=[];
      for(let i=0;i<listed.length;i++){
        const entry=byName.get(normalized(listed[i]));
        if(!entry)throw Error("M3U track not found in TAR: "+listed[i]);
        const blob=file.slice(entry.dataOffset,entry.dataOffset+entry.size);restored.push(new File([blob],entry.name,{lastModified:entry.modified}));
      }
      const playlistLine=manifestText.split(/\r?\n/).find(line=>line.startsWith("#PLAYLIST:"));
      const artistLine=manifestText.split(/\r?\n/).find(line=>line.startsWith("#ARTIST:"));
      const importedName=playlistLine?playlistLine.slice(10).trim():baseName(file.name);
      const coverEntry=entries.find(entry=>entry.name.toLowerCase()==="cover.art"&&entry.size===8464);
      state.coverBytes=coverEntry?bytes.slice(coverEntry.dataOffset,coverEntry.dataOffset+8464):null;showCover(state.coverBytes);
      state.files=restored;ui.name.value=cleanName(importedName||baseName(file.name)||"playlist");ui.artist.value=artistLine?artistLine.slice(8).trim():"";render();
      ui.status.textContent="Opened "+file.name+": "+restored.length+" tracks · audio preserved byte-for-byte.";
    }catch(error){ui.status.textContent="Could not open playlist: "+(error.message||String(error))}
  }

  function build(){
    try{
      invalidate();const names=uniqueNames(state.files),playlistName=cleanName(ui.name.value.trim()||"playlist"),artist=ui.artist.value.trim().replace(/[\r\n]/g," "),lines=["#EXTM3U","#PLAYLIST:"+playlistName];
      if(artist)lines.push("#ARTIST:"+artist);
      names.forEach((name,i)=>lines.push("#EXTINF:-1,"+baseName(state.files[i].name).replace(/[\r\n]/g," "),name));
      const playlist=encoder.encode(lines.join("\r\n")+"\r\n"),manifest={size:playlist.length,lastModified:Date.now()};
      const chunks=[header("playlist.m3u",manifest),playlist,pad(playlist.length)];
      if(state.coverBytes){const artwork={size:8464,lastModified:Date.now()};chunks.push(header("cover.art",artwork),state.coverBytes,pad(8464))}
      state.files.forEach((file,i)=>chunks.push(header(names[i],file),file,pad(file.size)));chunks.push(new Uint8Array(1024));const blob=new Blob(chunks,{type:"application/x-tar"});
      state.url=URL.createObjectURL(blob);ui.download.href=state.url;ui.download.download=playlistName+".tar";ui.download.hidden=false;ui.status.textContent="Playlist ready: "+size(blob.size)+" · source audio preserved byte-for-byte.";
    }catch(error){ui.status.textContent=error.message||String(error)}
  }

  ui.choose.onclick=()=>ui.files.click();ui.openTar.onclick=()=>ui.tarFile.click();
  ui.files.onchange=()=>{add(ui.files.files);ui.files.value=""};
  ui.tarFile.onchange=async()=>{if(ui.tarFile.files[0])await openPlaylistTar(ui.tarFile.files[0]);ui.tarFile.value=""};
  ui.cover.onchange=async()=>{try{await setCover(ui.cover.files[0]);ui.status.textContent=state.coverBytes?"Artwork ready: fitted to 92×92 RGB332.":"Artwork removed."}catch(error){ui.status.textContent="Could not read artwork: "+(error.message||String(error))}ui.cover.value=""};
  ui.clear.onclick=()=>{state.files=[];invalidate();render()};ui.build.onclick=build;
  ["dragenter","dragover"].forEach(type=>ui.drop.addEventListener(type,event=>{event.preventDefault();ui.drop.classList.add("drag")}));
  ["dragleave","drop"].forEach(type=>ui.drop.addEventListener(type,event=>{event.preventDefault();ui.drop.classList.remove("drag")}));
  ui.drop.addEventListener("drop",event=>{const files=[...event.dataTransfer.files];if(files.length===1&&/\.tar$/i.test(files[0].name))openPlaylistTar(files[0]);else add(files)});
  addEventListener("beforeunload",invalidate);showCover(null);render();
})();
