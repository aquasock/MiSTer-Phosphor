(() => {
  "use strict";
  const RATE=44100,CHANNELS=2,BPS=16,CD_FRAME=588,MAX_TRACKS=99,MAX_SEEKS=512;
  const state={tracks:[],output:null,outputUrl:null,busy:false};
  const $=id=>document.getElementById(id);
  const ui={drop:$("drop"),choose:$("choose"),files:$("files"),tracks:$("tracks"),summary:$("summary"),
    clear:$("clear"),build:$("build"),download:$("download"),name:$("name"),
    compression:$("compression"),progress:$("progress"),status:$("status")};
  const readU24=(a,o)=>(a[o]<<16)|(a[o+1]<<8)|a[o+2];
  const readU32LE=(a,o)=>(a[o]|(a[o+1]<<8)|(a[o+2]<<16)|(a[o+3]<<24))>>>0;
  const readU32BE=(a,o)=>((a[o]<<24)|(a[o+1]<<16)|(a[o+2]<<8)|a[o+3])>>>0;
  function readU64(a,o){let n=0n;for(let i=0;i<8;i++)n=(n<<8n)|BigInt(a[o+i]);return n}
  function writeU64(a,o,n){n=BigInt(n);for(let i=7;i>=0;i--){a[o+i]=Number(n&255n);n>>=8n}}
  function metadataEnd(bytes){
    if(bytes.length<42||String.fromCharCode(...bytes.subarray(0,4))!=="fLaC")throw Error("Not a native FLAC file.");
    let o=4,last=false,lastHeader=0;
    while(!last){if(o+4>bytes.length)throw Error("Truncated FLAC metadata.");
      lastHeader=o;last=!!(bytes[o]&128);const len=readU24(bytes,o+1);o+=4+len;
      if(o>bytes.length)throw Error("Truncated FLAC metadata block.");}
    return{audio:o,lastHeader};
  }
  function sourceMetadata(bytes){
    const decoder=new TextDecoder("utf-8"),tags={},pictures=[];let o=4,last=false;
    while(!last){last=!!(bytes[o]&128);const type=bytes[o]&127,len=readU24(bytes,o+1),data=o+4,end=data+len;
      if(type===4&&len>=8){let p=data,vendor=readU32LE(bytes,p);p+=4+vendor;if(p+4<=end){const count=readU32LE(bytes,p);p+=4;
        for(let i=0;i<count&&p+4<=end;i++){const n=readU32LE(bytes,p);p+=4;if(p+n>end)break;const item=decoder.decode(bytes.subarray(p,p+n)),eq=item.indexOf("=");p+=n;
          if(eq>0){const key=item.slice(0,eq).toLowerCase();if(tags[key]===undefined)tags[key]=item.slice(eq+1)}}}}
      if(type===6&&len>=32){let p=data;const pictureType=readU32BE(bytes,p);p+=4;const mimeLen=readU32BE(bytes,p);p+=4;
        if(p+mimeLen+4<=end){const mime=decoder.decode(bytes.subarray(p,p+mimeLen));p+=mimeLen;const descLen=readU32BE(bytes,p);p+=4+descLen;
          if(p+20<=end){const width=readU32BE(bytes,p),height=readU32BE(bytes,p+4);p+=16;const dataLen=readU32BE(bytes,p);p+=4;
            if(p+dataLen<=end&&mime.startsWith("image/"))pictures.push({pictureType,mime,width,height,data:bytes.slice(p,p+dataLen)})}}}
      o=end;
    }
    pictures.sort((a,b)=>(a.pictureType===3?0:1)-(b.pictureType===3?0:1));
    return{tags,picture:pictures[0]||null};
  }
  function inspect(bytes){
    const end=metadataEnd(bytes),type=bytes[4]&127,len=readU24(bytes,5);
    if(type!==0||len!==34)throw Error("STREAMINFO must be the first FLAC metadata block.");
    const packed=readU64(bytes,18),sampleRate=Number((packed>>44n)&0xfffffn);
    const channels=Number((packed>>41n)&7n)+1,bits=Number((packed>>36n)&31n)+1;
    const samples=Number(packed&0xfffffffffn);
    if(sampleRate!==RATE||channels!==CHANNELS||bits!==BPS)
      throw Error("Needs 44.1 kHz / 16-bit / stereo; found "+sampleRate+" Hz / "+bits+"-bit / "+channels+"ch.");
    if(!samples)throw Error("STREAMINFO does not contain a total sample count.");
    if(samples%CD_FRAME)throw Error("Length is not CD-sector aligned (remainder "+(samples%CD_FRAME)+" of 588 samples).");
    return{samples:samples,duration:samples/RATE,audioOffset:end.audio,...sourceMetadata(bytes)};
  }
  function time(seconds){const s=Math.round(seconds),h=Math.floor(s/3600),m=Math.floor(s%3600/60);
    return(h?String(h)+":":"")+String(m).padStart(h?2:1,"0")+":"+String(s%60).padStart(2,"0")}
  const size=n=>n<1048576?(n/1024).toFixed(0)+" KiB":(n/1048576).toFixed(1)+" MiB";
  function setStatus(text,value=0,max=1){ui.status.textContent=text;ui.progress.max=max;ui.progress.value=value}
  function invalidate(){if(state.outputUrl)URL.revokeObjectURL(state.outputUrl);state.output=null;state.outputUrl=null;ui.download.hidden=true}
  function move(from,to){const x=state.tracks.splice(from,1)[0];state.tracks.splice(to,0,x);invalidate();refresh()}
  function refresh(){
    ui.tracks.replaceChildren();
    state.tracks.forEach((track,index)=>{
      const li=document.createElement("li");li.className="track"+(track.error?" error":"");
      const body=document.createElement("div"),name=document.createElement("span"),meta=document.createElement("span");
      name.className="track-name";name.textContent=(track.tags&&track.tags.title)||track.file.name;meta.className="track-meta";
      const credit=track.tags&&track.tags.artist?track.tags.artist+" · ":"";
      meta.textContent=track.error||(credit+time(track.duration)+" · "+size(track.file.size)+" · "+track.samples.toLocaleString()+" samples");
      body.append(name,meta);const controls=document.createElement("div");controls.className="track-controls";
      [["↑",-1],["↓",1]].forEach(pair=>{const b=document.createElement("button");b.textContent=pair[0];
        b.title=pair[1]<0?"Move up":"Move down";b.disabled=state.busy||(pair[1]<0?index===0:index===state.tracks.length-1);
        b.onclick=()=>move(index,index+pair[1]);controls.append(b)});
      const remove=document.createElement("button");remove.textContent="Remove";remove.disabled=state.busy;
      remove.onclick=()=>{state.tracks.splice(index,1);invalidate();refresh()};controls.append(remove);
      li.append(body,controls);ui.tracks.append(li);
    });
    const valid=state.tracks.length>=2&&!state.tracks.some(t=>t.error);
    const seconds=state.tracks.reduce((n,t)=>n+(t.duration||0),0);
    ui.summary.textContent=state.tracks.length?(state.tracks.length+" track"+(state.tracks.length===1?"":"s")+" · "+time(seconds)+" total"):"No tracks added.";
    ui.build.disabled=state.busy||!valid;ui.clear.disabled=state.busy||!state.tracks.length;
    ui.name.disabled=state.busy;ui.compression.disabled=state.busy;
  }
  async function add(files){
    if(state.busy)return;const list=[...files],remaining=MAX_TRACKS-state.tracks.length;
    for(const file of list.slice(0,remaining)){const track={file:file,error:null,samples:0,duration:0};
      state.tracks.push(track);refresh();
      try{const bytes=new Uint8Array(await file.arrayBuffer());Object.assign(track,inspect(bytes))}
      catch(error){track.error=error.message||String(error)}refresh();}
    setStatus(list.length>remaining?"Only "+MAX_TRACKS+" CUE tracks are supported.":
      state.tracks.some(t=>t.error)?"Remove incompatible tracks before building.":"Ready to build.");
  }
  function waitForFlac(){return new Promise((resolve,reject)=>{
    if(!window.Flac)return reject(Error("The bundled FLAC codec did not load."));
    if(Flac.isReady())return resolve();const timer=setTimeout(()=>reject(Error("Timed out loading the FLAC codec.")),15000);
    Flac.on("ready",()=>{clearTimeout(timer);resolve()});
  })}
  function decode(bytes,onPcm){
    let offset=0,failed=null;const id=Flac.create_libflac_decoder(true);if(!id)throw Error("Could not create FLAC decoder.");
    const read=max=>{const end=Math.min(bytes.length,offset+max),chunk=bytes.subarray(offset,end);offset=end;
      return{buffer:chunk,readDataLength:chunk.length,error:false}};
    const write=channels=>{const samples=channels[0].byteLength>>1,pcm=new Int32Array(samples*2);
      const l=new DataView(channels[0].buffer,channels[0].byteOffset,channels[0].byteLength);
      const r=new DataView(channels[1].buffer,channels[1].byteOffset,channels[1].byteLength);
      for(let i=0;i<samples;i++){pcm[i*2]=l.getInt16(i*2,true);pcm[i*2+1]=r.getInt16(i*2,true)}
      if(!onPcm(pcm,samples))failed=Error("FLAC encoder rejected PCM data.");};
    const error=(code,msg)=>{failed=Error("Decode error "+code+": "+msg)};
    const init=Flac.init_decoder_stream(id,read,write,error,()=>{});
    if(init!==0){Flac.FLAC__stream_decoder_delete(id);throw Error("Decoder initialization failed ("+init+").")}
    const ok=Flac.FLAC__stream_decoder_process_until_end_of_stream(id);
    const finish=Flac.FLAC__stream_decoder_finish(id);Flac.FLAC__stream_decoder_delete(id);
    if(failed)throw failed;if(!ok||!finish)throw Error("FLAC decoding did not finish cleanly.");
  }
  function block(type,data,last=false){const out=new Uint8Array(4+data.length);out[0]=(last?128:0)|type;
    out[1]=(data.length>>>16)&255;out[2]=(data.length>>>8)&255;out[3]=data.length&255;out.set(data,4);return out}
  function cueSheet(starts,total){const data=new Uint8Array(396+starts.length*48+36);data[136]=128;data[395]=starts.length+1;let o=396;
    starts.forEach((start,i)=>{writeU64(data,o,start);data[o+8]=i+1;data[o+35]=1;data[o+44]=1;o+=48});
    writeU64(data,o,total);data[o+8]=170;return data}
  function seekTable(frames,audioOffset){if(!frames.length)throw Error("Encoder produced no FLAC frames.");
    const step=Math.max(1,Math.ceil(frames.length/MAX_SEEKS)),chosen=[];for(let i=0;i<frames.length&&chosen.length<MAX_SEEKS;i+=step)chosen.push(frames[i]);
    const data=new Uint8Array(chosen.length*18);let o=0;chosen.forEach(f=>{writeU64(data,o,f.sample);writeU64(data,o+8,f.offset-audioOffset);
      data[o+16]=(f.samples>>>8)&255;data[o+17]=f.samples&255;o+=18});return data}
  function join(chunks,total){const out=new Uint8Array(total);let o=0;for(const c of chunks){out.set(c,o);o+=c.length}return out}
  function cleanText(value){return String(value||"")
    .replace(/[\u2018\u2019\u201a\u201b]/g,"'").replace(/[\u201c\u201d\u201e\u201f]/g,'"')
    .replace(/[\u2010-\u2015]/g,"-").replace(/\u2026/g,"...")
    .replace(/[\u0000-\u001f\u007f-\uffff]/g," ").trim()}
  function putText(out,offset,value,length){const bytes=new TextEncoder().encode(cleanText(value));out.set(bytes.subarray(0,length),offset)}
  async function artwork(picture){const pixels=new Uint8Array(92*92);if(!picture)return{pixels,valid:false};
    try{const image=await createImageBitmap(new Blob([picture.data],{type:picture.mime})),canvas=document.createElement("canvas");canvas.width=92;canvas.height=92;
      const ctx=canvas.getContext("2d",{alpha:false});ctx.fillStyle="#000";ctx.fillRect(0,0,92,92);
      const scale=Math.min(92/image.width,92/image.height),w=Math.max(1,Math.round(image.width*scale)),h=Math.max(1,Math.round(image.height*scale));
      ctx.drawImage(image,(92-w)>>1,(92-h)>>1,w,h);image.close();const rgba=ctx.getImageData(0,0,92,92).data;
      for(let i=0;i<pixels.length;i++)pixels[i]=(rgba[i*4]&0xe0)|((rgba[i*4+1]>>3)&0x1c)|(rgba[i*4+2]>>6);
      return{pixels,valid:true}}catch(error){console.warn("Cover art could not be converted",error);return{pixels,valid:false}}}
  function albumApplication(tracks,art){const data=new Uint8Array(11704);data.set([77,80,51,65,2,tracks.length,art.valid?1:0,0]);
    const first=key=>tracks.map(t=>t.tags&&t.tags[key]).find(Boolean)||"";
    const album=cleanText(first("album")||"Untitled Album"),artist=cleanText(first("albumartist")||first("artist")||"Unknown Artist");
    putText(data,8,album,31);data[39]=Math.min(album.length,31);
    putText(data,40,artist,31);data[71]=Math.min(artist.length,31);
    tracks.forEach((track,i)=>{const title=cleanText((track.tags&&track.tags.title)||track.file.name.replace(/\.flac$/i,""))||"UNTITLED";
      putText(data,72+i*32,title,31);data[72+i*32+31]=Math.min(title.length,31)});data.set(art.pixels,3240);return data}
  function injectMetadata(encoded,frames,starts,total,application){const parsed=metadataEnd(encoded),prefix=encoded.slice(0,parsed.audio);
    prefix[parsed.lastHeader]&=127;const seeks=block(3,seekTable(frames,parsed.audio)),app=block(2,application),cue=block(5,cueSheet(starts,total),true);
    return join([prefix,seeks,app,cue,encoded.subarray(parsed.audio)],prefix.length+seeks.length+app.length+cue.length+encoded.length-parsed.audio)}
  async function build(){
    if(state.busy)return;state.busy=true;invalidate();refresh();
    try{await waitForFlac();
      const total=state.tracks.reduce((n,t)=>n+t.samples,0),starts=[];let cursor=0;
      state.tracks.forEach(track=>{starts.push(cursor);cursor+=track.samples});
      const chunks=[],frames=[];let bytesWritten=0,sampleWritten=0;
      const enc=Flac.create_libflac_encoder(RATE,CHANNELS,BPS,Number(ui.compression.value),total,true);
      if(!enc)throw Error("Could not create FLAC encoder.");Flac.FLAC__stream_encoder_set_blocksize(enc,4096);
      const init=Flac.init_encoder_stream(enc,(data,bytes,samples)=>{const copy=data.slice();
        if(samples)frames.push({sample:sampleWritten,offset:bytesWritten,samples:samples});
        chunks.push(copy);bytesWritten+=bytes;sampleWritten+=samples},()=>{},false,0);
      if(init!==0){Flac.FLAC__stream_encoder_delete(enc);throw Error("Encoder initialization failed ("+init+").")}
      for(let i=0;i<state.tracks.length;i++){const track=state.tracks[i];
        setStatus("Decoding and encoding track "+(i+1)+" of "+state.tracks.length+": "+track.file.name,i,state.tracks.length+1);
        await new Promise(requestAnimationFrame);const bytes=new Uint8Array(await track.file.arrayBuffer());
        decode(bytes,(pcm,samples)=>Flac.FLAC__stream_encoder_process_interleaved(enc,pcm,samples));}
      const finalProgress=state.tracks.length;setStatus("Embedding CUESHEET, metadata, and artwork…",finalProgress,finalProgress+1);
      const cover=await artwork(state.tracks.map(t=>t.picture).find(Boolean));
      if(!Flac.FLAC__stream_encoder_finish(enc)){const code=Flac.FLAC__stream_encoder_get_state(enc);
        Flac.FLAC__stream_encoder_delete(enc);throw Error("Encoder finish failed ("+code+").")}
      const base=(ui.name.value.trim()||"album").replace(/[\\/:*?"<>|]+/g,"_");Flac.FLAC__stream_encoder_delete(enc);
      const encoded=join(chunks,bytesWritten),album=injectMetadata(encoded,frames,starts,total,albumApplication(state.tracks,cover));
      inspect(album);state.output=new Blob([album],{type:"audio/flac"});state.outputUrl=URL.createObjectURL(state.output);
      ui.download.download=base+".flac";ui.download.href=state.outputUrl;ui.download.hidden=false;
      setStatus("Album ready: "+size(album.length)+" · "+state.tracks.length+" tracks · "+time(total/RATE)+" · all samples preserved",1,1);
    }catch(error){console.error(error);setStatus(error.message||String(error))}
    finally{state.busy=false;refresh()}
  }
  ui.choose.onclick=()=>ui.files.click();ui.files.onchange=()=>{add(ui.files.files);ui.files.value=""};
  ui.clear.onclick=()=>{state.tracks=[];invalidate();refresh();setStatus("Add two or more tracks to begin.")};
  ui.build.onclick=build;["dragenter","dragover"].forEach(type=>ui.drop.addEventListener(type,e=>{e.preventDefault();ui.drop.classList.add("drag")}));
  ["dragleave","drop"].forEach(type=>ui.drop.addEventListener(type,e=>{e.preventDefault();ui.drop.classList.remove("drag")}));
  ui.drop.addEventListener("drop",e=>add(e.dataTransfer.files));ui.drop.addEventListener("keydown",e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();ui.files.click()}});
  refresh();
})();
