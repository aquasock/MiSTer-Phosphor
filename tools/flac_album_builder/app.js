(() => {
  "use strict";
  const RATE=44100,CHANNELS=2,BPS=16,CD_FRAME=588,MAX_TRACKS=99,MAX_SEEKS=512;
  const state={tracks:[],output:null,outputUrl:null,busy:false};
  const $=id=>document.getElementById(id);
  const ui={drop:$("drop"),choose:$("choose"),files:$("files"),tracks:$("tracks"),summary:$("summary"),
    clear:$("clear"),build:$("build"),download:$("download"),name:$("name"),circular:$("circular"),trimMode:$("trim-mode"),
    compression:$("compression"),progress:$("progress"),status:$("status")};
  const readU24=(a,o)=>(a[o]<<16)|(a[o+1]<<8)|a[o+2];
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
    return{samples:samples,duration:samples/RATE,audioOffset:end.audio};
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
      name.className="track-name";name.textContent=track.file.name;meta.className="track-meta";
      meta.textContent=track.error||(time(track.duration)+" · "+size(track.file.size)+" · "+track.samples.toLocaleString()+" samples");
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
    ui.circular.disabled=state.busy;ui.trimMode.disabled=state.busy||!ui.circular.checked;
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
  function edgeAnalysis(bytes){let leading=0,trailing=0,seenNonzero=false,total=0,energy=0,sectorSamples=0;const sectors=[];
    decode(bytes,(pcm,samples)=>{for(let i=0;i<samples;i++){const zero=pcm[i*2]===0&&pcm[i*2+1]===0;
        if(zero){if(!seenNonzero)leading++;trailing++;}else{seenNonzero=true;trailing=0;}
        energy+=pcm[i*2]*pcm[i*2]+pcm[i*2+1]*pcm[i*2+1];sectorSamples++;total++;
        if(sectorSamples===CD_FRAME){sectors.push(energy/(CD_FRAME*CHANNELS));energy=0;sectorSamples=0;}}
      return true});
    const quietLimit=Math.pow(32768*Math.pow(10,-50/20),2);let leadingQuiet=0,trailingQuiet=0;
    for(const rms2 of sectors){if(rms2>quietLimit)break;leadingQuiet+=CD_FRAME;}
    for(let i=sectors.length-1;i>=0;i--){if(sectors[i]>quietLimit)break;trailingQuiet+=CD_FRAME;}
    return{leading,trailing,leadingQuiet,trailingQuiet,total};}
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
  function injectMetadata(encoded,frames,starts,total){const parsed=metadataEnd(encoded),prefix=encoded.slice(0,parsed.audio);
    prefix[parsed.lastHeader]&=127;const seeks=block(3,seekTable(frames,parsed.audio)),cue=block(5,cueSheet(starts,total),true);
    return join([prefix,seeks,cue,encoded.subarray(parsed.audio)],prefix.length+seeks.length+cue.length+encoded.length-parsed.audio)}
  async function build(){
    if(state.busy)return;state.busy=true;invalidate();refresh();
    const circular=ui.circular.checked,trimMode=ui.trimMode.value;
    try{await waitForFlac();let trimLeading=0,trimTrailing=0;
      if(circular){setStatus("Analyzing exact silence at the album boundaries…",0,state.tracks.length+3);
        await new Promise(requestAnimationFrame);
        const firstBytes=new Uint8Array(await state.tracks[0].file.arrayBuffer()),firstEdge=edgeAnalysis(firstBytes);
        setStatus("Analyzing the end of the final track…",1,state.tracks.length+3);await new Promise(requestAnimationFrame);
        const last=state.tracks.length-1,lastBytes=new Uint8Array(await state.tracks[last].file.arrayBuffer()),lastEdge=edgeAnalysis(lastBytes);
        trimLeading=trimMode==="tight"?firstEdge.leadingQuiet:Math.floor(firstEdge.leading/CD_FRAME)*CD_FRAME;
        trimTrailing=trimMode==="tight"?lastEdge.trailingQuiet:Math.floor(lastEdge.trailing/CD_FRAME)*CD_FRAME;
        if(trimLeading>=state.tracks[0].samples||trimTrailing>=state.tracks[last].samples)
          throw Error("Circular trimming would remove an entire track.");}
      const adjusted=state.tracks.map((t,i)=>t.samples-(i===0?trimLeading:0)-(i===state.tracks.length-1?trimTrailing:0));
      const total=adjusted.reduce((n,s)=>n+s,0),starts=[];let cursor=0;
      adjusted.forEach(samples=>{starts.push(cursor);cursor+=samples});
      const chunks=[],frames=[];let bytesWritten=0,sampleWritten=0;
      const enc=Flac.create_libflac_encoder(RATE,CHANNELS,BPS,Number(ui.compression.value),total,true);
      if(!enc)throw Error("Could not create FLAC encoder.");Flac.FLAC__stream_encoder_set_blocksize(enc,4096);
      const init=Flac.init_encoder_stream(enc,(data,bytes,samples)=>{const copy=data.slice();
        if(samples)frames.push({sample:sampleWritten,offset:bytesWritten,samples:samples});
        chunks.push(copy);bytesWritten+=bytes;sampleWritten+=samples},()=>{},false,0);
      if(init!==0){Flac.FLAC__stream_encoder_delete(enc);throw Error("Encoder initialization failed ("+init+").")}
      for(let i=0;i<state.tracks.length;i++){const track=state.tracks[i];
        const progressBase=circular?2:0;
        setStatus("Decoding and encoding track "+(i+1)+" of "+state.tracks.length+": "+track.file.name,i+progressBase,state.tracks.length+progressBase+1);
        await new Promise(requestAnimationFrame);const bytes=new Uint8Array(await track.file.arrayBuffer());
        let sourceSample=0;const keepStart=i===0?trimLeading:0,keepEnd=track.samples-(i===state.tracks.length-1?trimTrailing:0);
        decode(bytes,(pcm,samples)=>{const chunkStart=sourceSample,chunkEnd=sourceSample+samples;
          const from=Math.max(0,keepStart-chunkStart),to=Math.min(samples,keepEnd-chunkStart);sourceSample=chunkEnd;
          return to<=from||Flac.FLAC__stream_encoder_process_interleaved(enc,pcm.subarray(from*2,to*2),to-from)});}
      const finalProgress=state.tracks.length+(circular?2:0);
      setStatus("Finalizing metadata…",finalProgress,finalProgress+1);
      if(!Flac.FLAC__stream_encoder_finish(enc)){const code=Flac.FLAC__stream_encoder_get_state(enc);
        Flac.FLAC__stream_encoder_delete(enc);throw Error("Encoder finish failed ("+code+").")}
      Flac.FLAC__stream_encoder_delete(enc);const encoded=join(chunks,bytesWritten),album=injectMetadata(encoded,frames,starts,total);
      inspect(album);state.output=new Blob([album],{type:"audio/flac"});state.outputUrl=URL.createObjectURL(state.output);
      const base=(ui.name.value.trim()||"album").replace(/[\\/:*?"<>|]+/g,"_");
      ui.download.download=base+".flac";ui.download.href=state.outputUrl;ui.download.hidden=false;
      const trimmed=trimLeading+trimTrailing,trimNote=trimmed?" · trimmed "+(trimmed/RATE).toFixed(3)+
        " s (start "+(trimLeading/RATE).toFixed(3)+", end "+(trimTrailing/RATE).toFixed(3)+")":"";
      setStatus("Album ready: "+size(album.length)+" · "+state.tracks.length+" tracks · "+time(total/RATE)+trimNote,1,1);
    }catch(error){console.error(error);setStatus(error.message||String(error))}
    finally{state.busy=false;refresh()}
  }
  ui.choose.onclick=()=>ui.files.click();ui.files.onchange=()=>{add(ui.files.files);ui.files.value=""};
  ui.clear.onclick=()=>{state.tracks=[];invalidate();refresh();setStatus("Add two or more tracks to begin.")};
  ui.circular.onchange=()=>{invalidate();refresh()};ui.trimMode.onchange=invalidate;
  ui.build.onclick=build;["dragenter","dragover"].forEach(type=>ui.drop.addEventListener(type,e=>{e.preventDefault();ui.drop.classList.add("drag")}));
  ["dragleave","drop"].forEach(type=>ui.drop.addEventListener(type,e=>{e.preventDefault();ui.drop.classList.remove("drag")}));
  ui.drop.addEventListener("drop",e=>add(e.dataTransfer.files));ui.drop.addEventListener("keydown",e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();ui.files.click()}});
  refresh();
})();
