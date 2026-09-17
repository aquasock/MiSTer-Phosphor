(() => {
  "use strict";
  const RATE=44100,CHANNELS=2,BPS=16,CD_FRAME=588;
  const state={file:null,bytes:null,tracks:[],outputs:[],urls:[],zipUrl:null,busy:false};
  const $=id=>document.getElementById(id);
  const ui={drop:$("drop"),choose:$("choose"),file:$("file"),tracks:$("tracks"),summary:$("summary"),
    clear:$("clear"),split:$("split"),zip:$("zip"),name:$("name"),compression:$("compression"),
    progress:$("progress"),status:$("status")};
  const readU24=(a,o)=>(a[o]<<16)|(a[o+1]<<8)|a[o+2];
  function readU64(a,o){let n=0n;for(let i=0;i<8;i++)n=(n<<8n)|BigInt(a[o+i]);return n}
  function parseAlbum(bytes){
    if(bytes.length<42||String.fromCharCode(...bytes.subarray(0,4))!=="fLaC")throw Error("Not a native FLAC file.");
    let o=4,stream=null,cue=null,last=false;
    while(!last){if(o+4>bytes.length)throw Error("Truncated FLAC metadata.");
      last=!!(bytes[o]&128);const type=bytes[o]&127,len=readU24(bytes,o+1),data=o+4,end=data+len;
      if(end>bytes.length)throw Error("Truncated FLAC metadata block.");
      if(type===0){if(len!==34)throw Error("Invalid STREAMINFO block.");const packed=readU64(bytes,data+10);
        stream={rate:Number((packed>>44n)&0xfffffn),channels:Number((packed>>41n)&7n)+1,
          bits:Number((packed>>36n)&31n)+1,samples:Number(packed&0xfffffffffn)};}
      if(type===5)cue=bytes.subarray(data,end);o=end;
    }
    if(!stream)throw Error("Missing STREAMINFO metadata.");
    if(stream.rate!==RATE||stream.channels!==CHANNELS||stream.bits!==BPS)
      throw Error(`Needs 44.1 kHz / 16-bit / stereo; found ${stream.rate} Hz / ${stream.bits}-bit / ${stream.channels}ch.`);
    if(!stream.samples)throw Error("STREAMINFO does not contain a total sample count.");
    if(!cue||cue.length<396)throw Error("This FLAC has no usable embedded CUESHEET.");
    const count=cue[395];let p=396;const starts=[];
    for(let i=0;i<count;i++){
      if(p+36>cue.length)throw Error("Truncated CUESHEET track entry.");
      const offset=Number(readU64(cue,p)),number=cue[p+8],indexes=cue[p+35],trackSize=36+indexes*12;
      if(p+trackSize>cue.length)throw Error("Truncated CUESHEET index entry.");
      if(number>=1&&number<=99){let index01=null;
        for(let j=0;j<indexes;j++){const q=p+36+j*12;if(cue[q+8]===1)index01=Number(readU64(cue,q));}
        if(index01===null)throw Error(`CUESHEET track ${number} has no INDEX 01.`);
        starts.push({number,start:offset+index01});
      }else if(number===170&&offset!==stream.samples)throw Error("CUESHEET lead-out does not match the audio length.");
      p+=trackSize;
    }
    if(!starts.length)throw Error("The CUESHEET contains no audio tracks.");
    starts.sort((a,b)=>a.start-b.start);
    for(let i=0;i<starts.length;i++){
      const end=i+1<starts.length?starts[i+1].start:stream.samples;
      if(starts[i].start<0||end<=starts[i].start||end>stream.samples)throw Error("CUESHEET track boundaries are invalid.");
      starts[i].samples=end-starts[i].start;
    }
    return{...stream,tracks:starts};
  }
  function time(samples){const seconds=Math.round(samples/RATE),m=Math.floor(seconds/60);return `${m}:${String(seconds%60).padStart(2,"0")}`}
  const size=n=>n<1048576?(n/1024).toFixed(0)+" KiB":(n/1048576).toFixed(1)+" MiB";
  function status(text,value=0,max=1){ui.status.textContent=text;ui.progress.max=max;ui.progress.value=value}
  function release(){state.urls.forEach(URL.revokeObjectURL);state.urls=[];if(state.zipUrl)URL.revokeObjectURL(state.zipUrl);
    state.zipUrl=null;state.outputs=[];ui.zip.hidden=true;}
  function safeName(){return(ui.name.value.trim()||"album").replace(/[\\/:*?"<>|]+/g,"_")}
  function filename(index){return `${safeName()}-track-${String(index+1).padStart(2,"0")}.flac`}
  function refresh(){ui.tracks.replaceChildren();state.tracks.forEach((track,index)=>{
    const li=document.createElement("li");li.className="track";const body=document.createElement("div");body.className="track-main";
    const name=document.createElement("span");name.className="track-name";name.textContent=`Track ${String(track.number).padStart(2,"0")}`;
    const meta=document.createElement("span");meta.className="track-meta";meta.textContent=`${time(track.samples)} · ${track.samples.toLocaleString()} samples`;
    body.append(name,meta);li.append(body);if(state.outputs[index]){const a=document.createElement("a");a.href=state.urls[index];a.download=filename(index);
      a.textContent=`Download · ${size(state.outputs[index].length)}`;li.append(a)}ui.tracks.append(li);});
    ui.summary.textContent=state.file?`${state.file.name} · ${state.tracks.length} tracks · ${time(state.tracks.reduce((n,t)=>n+t.samples,0))}`:"No album loaded.";
    ui.split.disabled=state.busy||!state.file;ui.clear.disabled=state.busy||!state.file;
  }
  async function load(file){if(state.busy||!file)return;release();state.file=null;state.tracks=[];refresh();
    try{const bytes=new Uint8Array(await file.arrayBuffer()),album=parseAlbum(bytes);state.file=file;state.bytes=bytes;state.tracks=album.tracks;
      ui.name.value=file.name.replace(/\.flac$/i,"")||"album";status(`Ready to split ${state.tracks.length} tracks.`);}
    catch(error){state.bytes=null;status(error.message||String(error));ui.status.classList.add("error");}
    finally{refresh()}}
  function waitForFlac(){return new Promise((resolve,reject)=>{if(!window.Flac)return reject(Error("The bundled FLAC codec did not load."));
    if(Flac.isReady())return resolve();const timer=setTimeout(()=>reject(Error("Timed out loading the FLAC codec.")),15000);
    Flac.on("ready",()=>{clearTimeout(timer);resolve()});})}
  function join(chunks,total){const out=new Uint8Array(total);let o=0;for(const chunk of chunks){out.set(chunk,o);o+=chunk.length}return out}
  function makeEncoder(samples,level){const chunks=[];let length=0;const id=Flac.create_libflac_encoder(RATE,CHANNELS,BPS,level,samples,true);
    if(!id)throw Error("Could not create FLAC encoder.");Flac.FLAC__stream_encoder_set_blocksize(id,4096);
    const init=Flac.init_encoder_stream(id,(data,bytes)=>{const copy=data.slice();chunks.push(copy);length+=bytes},()=>{},false,0);
    if(init!==0){Flac.FLAC__stream_encoder_delete(id);throw Error(`Encoder initialization failed (${init}).`)}
    return{id,chunks,get length(){return length}}}
  function finishEncoder(enc){if(!Flac.FLAC__stream_encoder_finish(enc.id)){const code=Flac.FLAC__stream_encoder_get_state(enc.id);
      Flac.FLAC__stream_encoder_delete(enc.id);throw Error(`Encoder finish failed (${code}).`)}
    Flac.FLAC__stream_encoder_delete(enc.id);return join(enc.chunks,enc.length)}
  function decodeAndSplit(bytes,tracks,level){let sourceOffset=0,samplePos=0,trackIndex=0,failed=null,enc=makeEncoder(tracks[0].samples,level);
    const outputs=[];const id=Flac.create_libflac_decoder(true);if(!id)throw Error("Could not create FLAC decoder.");
    const read=max=>{const end=Math.min(bytes.length,sourceOffset+max),chunk=bytes.subarray(sourceOffset,end);sourceOffset=end;
      return{buffer:chunk,readDataLength:chunk.length,error:false}};
    const write=channels=>{try{const count=channels[0].byteLength>>1,l=new DataView(channels[0].buffer,channels[0].byteOffset,channels[0].byteLength),
        r=new DataView(channels[1].buffer,channels[1].byteOffset,channels[1].byteLength);let used=0;
      while(used<count){const track=tracks[trackIndex],remaining=track.start+track.samples-samplePos,take=Math.min(count-used,remaining),pcm=new Int32Array(take*2);
        for(let i=0;i<take;i++){pcm[i*2]=l.getInt16((used+i)*2,true);pcm[i*2+1]=r.getInt16((used+i)*2,true)}
        if(!Flac.FLAC__stream_encoder_process_interleaved(enc.id,pcm,take))throw Error("FLAC encoder rejected PCM data.");
        used+=take;samplePos+=take;if(samplePos===track.start+track.samples){outputs.push(finishEncoder(enc));trackIndex++;
          if(trackIndex<tracks.length)enc=makeEncoder(tracks[trackIndex].samples,level);}
      }}catch(error){failed=error}};
    const error=(code,msg)=>{failed=Error(`Decode error ${code}: ${msg}`)};
    const init=Flac.init_decoder_stream(id,read,write,error,()=>{});if(init!==0){Flac.FLAC__stream_decoder_delete(id);throw Error(`Decoder initialization failed (${init}).`)}
    const ok=Flac.FLAC__stream_decoder_process_until_end_of_stream(id),done=Flac.FLAC__stream_decoder_finish(id);Flac.FLAC__stream_decoder_delete(id);
    if(failed)throw failed;if(!ok||!done)throw Error("FLAC decoding did not finish cleanly.");
    if(trackIndex!==tracks.length)throw Error("Decoded audio ended before the final CUE track.");return outputs;
  }
  function crcTable(){const table=new Uint32Array(256);for(let n=0;n<256;n++){let c=n;for(let k=0;k<8;k++)c=(c&1)?0xedb88320^(c>>>1):c>>>1;table[n]=c>>>0}return table}
  const CRC=crcTable();function crc32(data){let c=0xffffffff;for(const b of data)c=CRC[(c^b)&255]^(c>>>8);return(c^0xffffffff)>>>0}
  function u16(a,o,n){a[o]=n&255;a[o+1]=(n>>>8)&255}function u32(a,o,n){a[o]=n&255;a[o+1]=(n>>>8)&255;a[o+2]=(n>>>16)&255;a[o+3]=(n>>>24)&255}
  function makeZip(files){const encoder=new TextEncoder(),locals=[],centrals=[];let offset=0,centralSize=0;
    files.forEach(file=>{const name=encoder.encode(file.name),crc=crc32(file.data),local=new Uint8Array(30+name.length+file.data.length);
      u32(local,0,0x04034b50);u16(local,4,20);u16(local,6,0x0800);u16(local,8,0);u32(local,14,crc);u32(local,18,file.data.length);u32(local,22,file.data.length);u16(local,26,name.length);local.set(name,30);local.set(file.data,30+name.length);locals.push(local);
      const central=new Uint8Array(46+name.length);u32(central,0,0x02014b50);u16(central,4,20);u16(central,6,20);u16(central,8,0x0800);u32(central,16,crc);u32(central,20,file.data.length);u32(central,24,file.data.length);u16(central,28,name.length);u32(central,42,offset);central.set(name,46);centrals.push(central);centralSize+=central.length;offset+=local.length;});
    const end=new Uint8Array(22);u32(end,0,0x06054b50);u16(end,8,files.length);u16(end,10,files.length);u32(end,12,centralSize);u32(end,16,offset);
    return new Blob([...locals,...centrals,end],{type:"application/zip"})}
  async function split(){if(state.busy||!state.file)return;state.busy=true;release();refresh();ui.status.classList.remove("error");
    try{await waitForFlac();status("Decoding album and encoding individual tracks…",0,1);await new Promise(requestAnimationFrame);
      state.outputs=decodeAndSplit(state.bytes,state.tracks,Number(ui.compression.value));state.urls=state.outputs.map(data=>URL.createObjectURL(new Blob([data],{type:"audio/flac"})));
      const zip=makeZip(state.outputs.map((data,i)=>({name:filename(i),data})));state.zipUrl=URL.createObjectURL(zip);ui.zip.href=state.zipUrl;ui.zip.download=safeName()+"-tracks.zip";ui.zip.hidden=false;
      status(`${state.outputs.length} tracks ready · ${size(state.outputs.reduce((n,x)=>n+x.length,0))} total`,1,1);
    }catch(error){console.error(error);status(error.message||String(error));ui.status.classList.add("error");release();}
    finally{state.busy=false;refresh()}}
  ui.choose.onclick=()=>ui.file.click();ui.file.onchange=()=>{load(ui.file.files[0]);ui.file.value=""};ui.split.onclick=split;
  ui.clear.onclick=()=>{release();state.file=null;state.bytes=null;state.tracks=[];refresh();status("Choose a MiSTer FLAC album to begin.")};
  ["dragenter","dragover"].forEach(type=>ui.drop.addEventListener(type,e=>{e.preventDefault();ui.drop.classList.add("drag")}));
  ["dragleave","drop"].forEach(type=>ui.drop.addEventListener(type,e=>{e.preventDefault();ui.drop.classList.remove("drag")}));
  ui.drop.addEventListener("drop",e=>load(e.dataTransfer.files[0]));ui.drop.addEventListener("keydown",e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();ui.file.click()}});refresh();
})();
