(() => {
  "use strict";
  const RATE=44100,TARGETS=[44100,48000],CHANNELS=2,BPS=16,CD_FRAME=588,MAX_TRACKS=99,MAX_SEEKS=512;
  const state={tracks:[],output:null,outputUrl:null,busy:false,convert:false,art:null,albumEdited:false,artistEdited:false,artEdited:false};
  const $=id=>document.getElementById(id);
  const ui={drop:$("drop"),choose:$("choose"),files:$("files"),tracks:$("tracks"),summary:$("summary"),
    clear:$("clear"),build:$("build"),download:$("download"),name:$("name"),album:$("album"),artist:$("artist"),
    cover:$("cover"),coverPreview:$("coverPreview"),convert:$("convert"),convertNote:$("convertNote"),compression:$("compression"),progress:$("progress"),status:$("status")};
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
    const packed=readU64(bytes,18),rate=Number((packed>>44n)&0xfffffn);
    const channels=Number((packed>>41n)&7n)+1,bits=Number((packed>>36n)&31n)+1;
    const samples=Number(packed&0xfffffffffn);
    if(!samples)throw Error("STREAMINFO does not contain a total sample count.");
    return{samples:samples,rate:rate,channels:channels,bits:bits,duration:samples/rate,audioOffset:end.audio,...sourceMetadata(bytes)};
  }
  const gcd=(a,b)=>{while(b){const t=a%b;a=b;b=t}return a};
  const rateName=hz=>(hz/1000).toFixed(hz%1000?1:0)+" kHz";
  const misalignment=t=>"Length is not CD-sector aligned (remainder "+(t.samples%CD_FRAME)+" of 588 samples).";
  // Decide the album format. Without conversion every track must already be 44.1 kHz / 16-bit / stereo and
  // CD-sector aligned. With conversion, tracks above 44.1 kHz (or 24-bit) are downsampled to one common rate:
  // 44.1 or 48 kHz, whichever needs fewer and simpler conversions (exact integer ratios first). A target that
  // would require upsampling any track is never chosen.
  function planAlbum(){
    const plan={rate:RATE,converting:false,converted:0};
    for(const t of state.tracks){t.issue=null;t.action="copy"}
    const usable=state.tracks.filter(t=>!t.error);
    if(!state.convert){
      for(const t of usable){
        if(t.rate!==RATE||t.channels!==CHANNELS||t.bits!==BPS)
          t.issue="Needs 44.1 kHz / 16-bit / stereo; found "+t.rate+" Hz / "+t.bits+"-bit / "+t.channels+"ch."+(t.channels===CHANNELS&&t.rate>=RATE?" Turn on conversion to downsample it.":"");
        else if(t.samples%CD_FRAME)t.issue=misalignment(t);
      }
      return plan;
    }
    for(const t of usable){
      if(t.channels!==CHANNELS)t.issue="Needs stereo; found "+t.channels+"ch.";
      else if(t.rate<RATE)t.issue="Sample rate "+t.rate+" Hz is below 44.1 kHz; only downsampling is supported.";
      else if(t.bits!==16&&t.bits!==24)t.issue="Needs 16- or 24-bit audio; found "+t.bits+"-bit.";
    }
    const ok=usable.filter(t=>!t.issue);
    const cost=(t,r)=>t.rate===r?(t.bits===BPS?0:.5):(t.rate%r===0?1:2);
    let best=null;
    for(const r of TARGETS){if(!ok.every(t=>t.rate>=r))continue;const c=ok.reduce((n,t)=>n+cost(t,r),0);if(!best||c<best.cost)best={rate:r,cost:c}}
    plan.rate=best?best.rate:RATE;
    for(const t of ok)if(t.rate!==plan.rate||t.bits!==BPS){t.action="convert";plan.converted++}
    plan.converting=plan.converted>0;
    if(!plan.converting)for(const t of ok)if(t.samples%CD_FRAME)t.issue=misalignment(t);
    return plan;
  }
  function time(seconds){const s=Math.round(seconds),h=Math.floor(s/3600),m=Math.floor(s%3600/60);
    return(h?String(h)+":":"")+String(m).padStart(h?2:1,"0")+":"+String(s%60).padStart(2,"0")}
  const size=n=>n<1048576?(n/1024).toFixed(0)+" KiB":(n/1048576).toFixed(1)+" MiB";
  function setStatus(text,value=0,max=1){ui.status.textContent=text;ui.progress.max=max;ui.progress.value=value}
  function invalidate(){if(state.outputUrl)URL.revokeObjectURL(state.outputUrl);state.output=null;state.outputUrl=null;ui.download.hidden=true}
  function move(from,to){const x=state.tracks.splice(from,1)[0];state.tracks.splice(to,0,x);invalidate();refresh()}
  function showCover(bytes){
    const context=ui.coverPreview.getContext("2d"),image=context.createImageData(92,92);
    for(let i=0;i<8464;i++){const value=bytes?bytes[i]:0,j=i*4;image.data[j]=((value>>5)&7)*255/7;image.data[j+1]=((value>>2)&7)*255/7;image.data[j+2]=(value&3)*255/3;image.data[j+3]=255}
    context.putImageData(image,0,0);
  }
  // Album fields follow the source tracks' tags until the user edits them.
  function autofill(){
    const first=(...keys)=>{for(const key of keys){const found=state.tracks.map(t=>t.tags&&t.tags[key]).find(Boolean);if(found)return found}return ""};
    if(!state.albumEdited)ui.album.value=first("album");
    if(!state.artistEdited)ui.artist.value=first("albumartist","artist");
    if(!state.artEdited){state.art=state.tracks.map(t=>t.art).find(Boolean)||null;showCover(state.art)}
  }
  function refresh(){
    const plan=planAlbum();autofill();ui.tracks.replaceChildren();
    state.tracks.forEach((track,index)=>{
      const li=document.createElement("li");li.className="track"+(track.error||track.issue?" error":"");
      const body=document.createElement("div"),name=document.createElement("span"),meta=document.createElement("span");
      name.className="track-name";name.textContent=(track.tags&&track.tags.title)||track.file.name;meta.className="track-meta";
      const credit=track.tags&&track.tags.artist?track.tags.artist+" · ":"";
      const route=track.action==="convert"?" · "+rateName(track.rate)+" / "+track.bits+"-bit → "+rateName(plan.rate)+" / 16-bit":"";
      meta.textContent=track.error||track.issue||(credit+time(track.duration)+" · "+size(track.file.size)+" · "+track.samples.toLocaleString()+" samples"+route);
      body.append(name,meta);const controls=document.createElement("div");controls.className="track-controls";
      [["↑",-1],["↓",1]].forEach(pair=>{const b=document.createElement("button");b.textContent=pair[0];
        b.title=pair[1]<0?"Move up":"Move down";b.disabled=state.busy||(pair[1]<0?index===0:index===state.tracks.length-1);
        b.onclick=()=>move(index,index+pair[1]);controls.append(b)});
      const remove=document.createElement("button");remove.textContent="Remove";remove.disabled=state.busy;
      remove.onclick=()=>{state.tracks.splice(index,1);invalidate();refresh()};controls.append(remove);
      li.append(body,controls);ui.tracks.append(li);
    });
    const valid=state.tracks.length>=2&&!state.tracks.some(t=>t.error||t.issue);
    const seconds=state.tracks.reduce((n,t)=>n+(t.duration||0),0);
    ui.summary.textContent=state.tracks.length?(state.tracks.length+" track"+(state.tracks.length===1?"":"s")+" · "+time(seconds)+" total"):"No tracks added.";
    ui.build.disabled=state.busy||!valid;ui.clear.disabled=state.busy||!state.tracks.length;
    ui.name.disabled=state.busy;ui.compression.disabled=state.busy;
    ui.album.disabled=state.busy;ui.artist.disabled=state.busy;ui.cover.disabled=state.busy;ui.convert.disabled=state.busy;
    ui.convertNote.textContent=!state.convert?"Off: tracks must already be 44.1 kHz / 16-bit / stereo and CD-sector aligned; audio is never altered.":
      plan.converting?"Target "+rateName(plan.rate)+" / 16-bit: "+plan.converted+" of "+state.tracks.length+" track"+(state.tracks.length===1?"":"s")+" will be resampled or requantized (lossy; 16-bit output is dithered; track markers snap back to the previous CD sector, up to 13 ms, and nothing is padded between tracks). Tracks already at the target format are copied unchanged."
      :"On, but nothing needs converting"+(state.tracks.length?" — every track is already "+rateName(plan.rate)+" / 16-bit and is copied unchanged.":".");
  }
  async function add(files){
    if(state.busy)return;const list=[...files],remaining=MAX_TRACKS-state.tracks.length;
    for(const file of list.slice(0,remaining)){const track={file:file,error:null,samples:0,duration:0};
      state.tracks.push(track);refresh();
      try{const bytes=new Uint8Array(await file.arrayBuffer());Object.assign(track,inspect(bytes))}
      catch(error){track.error=error.message||String(error)}
      if(track.picture)track.art=await toRgb332(new Blob([track.picture.data],{type:track.picture.mime})).catch(error=>{console.warn("Cover art could not be converted",error);return null});
      refresh();}
    setStatus(list.length>remaining?"Only "+MAX_TRACKS+" CUE tracks are supported.":
      state.tracks.some(t=>t.error||t.issue)?"Remove incompatible tracks before building.":"Ready to build.");
  }
  function waitForFlac(){return new Promise((resolve,reject)=>{
    if(!window.Flac)return reject(Error("The bundled FLAC codec did not load."));
    if(Flac.isReady())return resolve();const timer=setTimeout(()=>reject(Error("Timed out loading the FLAC codec.")),15000);
    Flac.on("ready",()=>{clearTimeout(timer);resolve()});
  })}
  // Decode one frame at a time, yielding to the page between frames so long conversions never freeze the UI.
  async function decode(bytes,onPcm,onProgress){
    let offset=0,failed=null,count=0;const id=Flac.create_libflac_decoder(true);if(!id)throw Error("Could not create FLAC decoder.");
    const read=max=>{const end=Math.min(bytes.length,offset+max),chunk=bytes.subarray(offset,end);offset=end;
      return{buffer:chunk,readDataLength:chunk.length,error:false}};
    const write=(channels,frame)=>{const samples=frame.blocksize,bits=frame.bitsPerSample,wide=channels[0].byteLength/samples>2,pcm=new Int32Array(samples*2);
      if(channels.length!==2||(bits!==16&&bits!==24)){failed=Error("Unsupported FLAC stream ("+channels.length+" channels, "+bits+"-bit).");return false}
      const l=new DataView(channels[0].buffer,channels[0].byteOffset,channels[0].byteLength);
      const r=new DataView(channels[1].buffer,channels[1].byteOffset,channels[1].byteLength);
      for(let i=0;i<samples;i++){pcm[i*2]=wide?l.getInt32(i*4,true):l.getInt16(i*2,true);pcm[i*2+1]=wide?r.getInt32(i*4,true):r.getInt16(i*2,true)}
      count+=samples;if(onPcm(pcm,samples,bits)===false&&!failed)failed=Error("FLAC encoder rejected PCM data.");return failed?false:undefined};
    const error=(code,msg)=>{failed=Error("Decode error "+code+": "+msg)};
    const init=Flac.init_decoder_stream(id,read,write,error,()=>{});
    if(init!==0){Flac.FLAC__stream_decoder_delete(id);throw Error("Decoder initialization failed ("+init+").")}
    let ok=true,yielded=performance.now();
    try{
      while(ok&&!failed&&Flac.FLAC__stream_decoder_get_state(id)!==4){
        ok=Flac.FLAC__stream_decoder_process_single(id);
        if(performance.now()-yielded>40){if(onProgress)onProgress(offset/bytes.length);await new Promise(r=>setTimeout(r));yielded=performance.now()}
      }
    }finally{var finish=Flac.FLAC__stream_decoder_finish(id);Flac.FLAC__stream_decoder_delete(id)}
    if(failed)throw failed;if(!ok||!finish)throw Error("FLAC decoding did not finish cleanly.");
    return count;
  }
  function besselI0(x){let sum=1,term=1;for(let k=1;k<80;k++){const h=x/(2*k);term*=h*h;sum+=term;if(term<1e-15*sum)break}return sum}
  // Streaming polyphase rational resampler: Kaiser-windowed sinc, about 96 dB stopband, flat to 20 kHz (48 kHz output:
  // 21.6 kHz), zero delay. The filter state runs across consecutive tracks, so a continuous recording stays continuous.
  function makeResampler(inRate,outRate){
    const g=gcd(inRate,outRate),L=outRate/g,M=inRate/g,beta=9.65,i0=besselI0(beta);
    // Alias-free and flat up to max(0.45 x output rate, 20 kHz); the transition band is centred on the output Nyquist frequency.
    const dfrac=1-2*Math.max(0.45*outRate,20000)/outRate,taps=Math.ceil(6.131/dfrac*M/L)+2,N=taps*L,c=N>>1,poly=new Float32Array(N);
    for(let m=0;m<N;m++){const k=m-c,x=Math.PI*k/M,r=k/c;
      poly[(m%L)*taps+Math.floor(m/L)]=(L/M)*(k===0?1:Math.sin(x)/x)*besselI0(beta*Math.sqrt(Math.max(0,1-r*r)))/i0}
    let wl=new Float64Array(taps+16384),wr=new Float64Array(taps+16384),len=taps,base=-taps,n=0,limit=Infinity;
    function run(){
      const bound=Math.max(0,Math.ceil((base+len)*L/M)-n+2),ol=new Float64Array(bound),or=new Float64Array(bound);let made=0;
      while(n<limit){
        const t=n*M+c,i=Math.floor(t/L);if(i>=base+len)break;
        const s=i-base,row=(t-i*L)*taps;let sl=0,sr=0;
        for(let k=0;k<taps;k++){const h=poly[row+k];sl+=h*wl[s-k];sr+=h*wr[s-k]}
        ol[made]=sl;or[made]=sr;made++;n++;
      }
      const keep=Math.max(base,Math.floor((n*M+c)/L)-taps+1),drop=keep-base;
      if(drop>0){wl.copyWithin(0,drop,len);wr.copyWithin(0,drop,len);len-=drop;base=keep}
      return{l:ol.subarray(0,made),r:or.subarray(0,made)};
    }
    function append(l,r,count){
      if(len+count>wl.length){const size=Math.max(wl.length*2,len+count),a=new Float64Array(size),b=new Float64Array(size);a.set(wl.subarray(0,len));b.set(wr.subarray(0,len));wl=a;wr=b}
      if(l){wl.set(l.subarray(0,count),len);wr.set(r.subarray(0,count),len)}else{wl.fill(0,len,len+count);wr.fill(0,len,len+count)}
      len+=count;
    }
    return{
      push(l,r,count){append(l,r,count);return run()},
      // totalIn is the run's exact input length; the tail is produced from implicit zero padding.
      finish(totalIn){limit=Math.ceil(totalIn*L/M);const need=Math.floor(((limit-1)*M+c)/L)+1-(base+len);if(need>0)append(null,null,need);return run()}
    };
  }
  // 16-bit output with TPDF dither (deterministic, so rebuilding gives the same file); out-of-range samples are clamped and counted.
  function makeQuantizer(){
    let seed=0x9e3779b9>>>0,clipped=0;
    const rnd=()=>{let x=seed;x^=x<<13;x^=x>>>17;x^=x<<5;seed=x>>>0;return seed/4294967296};
    return{clipped:()=>clipped,pack(l,r,n){
      const out=new Int32Array(n*2);
      for(let i=0;i<n;i++)for(let ch=0;ch<2;ch++){const q=Math.round((ch?r:l)[i]*32768+(rnd()-rnd()));out[i*2+ch]=q>32767?(clipped++,32767):q<-32768?(clipped++,-32768):q}
      return out}};
  }
  // Output length of every track. Converted runs of one source rate are resampled as a single stream, so track
  // boundaries fall on exact output positions; nothing is trimmed or padded between tracks.
  function layout(tracks,plan){
    const counts=[];let i=0;
    while(i<tracks.length){
      const t=tracks[i];let j=i+1;
      if(t.action==="copy"||t.rate===plan.rate){counts.push(t.samples);i=j;continue}
      const g=gcd(t.rate,plan.rate),L=plan.rate/g,M=t.rate/g,cuts=[0];let total=t.samples;
      while(j<tracks.length&&tracks[j].action==="convert"&&tracks[j].rate===t.rate){cuts.push(Math.ceil(total*L/M));total+=tracks[j].samples;j++}
      cuts.push(Math.ceil(total*L/M));
      for(let k=0;k<j-i;k++)counts.push(cuts[k+1]-cuts[k]);i=j;
    }
    return counts;
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
  async function toRgb332(blob){const pixels=new Uint8Array(92*92),image=await createImageBitmap(blob),canvas=document.createElement("canvas");canvas.width=92;canvas.height=92;
    const ctx=canvas.getContext("2d",{alpha:false});ctx.fillStyle="#000";ctx.fillRect(0,0,92,92);
    const scale=Math.min(92/image.width,92/image.height),w=Math.max(1,Math.round(image.width*scale)),h=Math.max(1,Math.round(image.height*scale));
    ctx.drawImage(image,(92-w)>>1,(92-h)>>1,w,h);image.close();const rgba=ctx.getImageData(0,0,92,92).data;
    for(let i=0;i<pixels.length;i++)pixels[i]=(rgba[i*4]&0xe0)|((rgba[i*4+1]>>3)&0x1c)|(rgba[i*4+2]>>6);
    return pixels}
  function albumApplication(tracks,meta){const data=new Uint8Array(11704);data.set([77,80,51,65,2,tracks.length,meta.art?1:0,0]);
    const album=cleanText(meta.album)||"Untitled Album",artist=cleanText(meta.artist)||"Unknown Artist";
    putText(data,8,album,31);data[39]=Math.min(album.length,31);
    putText(data,40,artist,31);data[71]=Math.min(artist.length,31);
    tracks.forEach((track,i)=>{const title=cleanText((track.tags&&track.tags.title)||track.file.name.replace(/\.flac$/i,""))||"UNTITLED";
      putText(data,72+i*32,title,31);data[72+i*32+31]=Math.min(title.length,31)});if(meta.art)data.set(meta.art,3240);return data}
  function injectMetadata(encoded,frames,starts,total,application){const parsed=metadataEnd(encoded),prefix=encoded.slice(0,parsed.audio);
    prefix[parsed.lastHeader]&=127;const seeks=block(3,seekTable(frames,parsed.audio)),app=block(2,application),cue=block(5,cueSheet(starts,total),true);
    return join([prefix,seeks,app,cue,encoded.subarray(parsed.audio)],prefix.length+seeks.length+app.length+cue.length+encoded.length-parsed.audio)}
  async function build(){
    if(state.busy)return;state.busy=true;invalidate();refresh();
    try{await waitForFlac();
      const plan=planAlbum(),tracks=state.tracks,counts=layout(tracks,plan);
      const starts=[];let cursor=0;counts.forEach(n=>{starts.push(cursor);cursor+=n});
      // Converted albums keep CD-sector CUESHEET offsets by moving each marker back to the previous sector (the audio
      // is not moved and no track start is ever cut off) and padding under one sector of silence after the last track.
      const total=plan.converting?Math.ceil(cursor/CD_FRAME)*CD_FRAME:cursor;
      if(plan.converting){for(let i=0;i<starts.length;i++){starts[i]=Math.floor(starts[i]/CD_FRAME)*CD_FRAME;
        if(i&&starts[i]<=starts[i-1])throw Error("Track "+(i+1)+" is too short to keep its own CD sector after conversion.")}
        if(starts[starts.length-1]>=total)throw Error("The last track is too short to keep its own CD sector after conversion.")}
      const chunks=[],frames=[];let bytesWritten=0,sampleWritten=0,fed=0;
      const enc=Flac.create_libflac_encoder(plan.rate,CHANNELS,BPS,Number(ui.compression.value),total,true);
      if(!enc)throw Error("Could not create FLAC encoder.");Flac.FLAC__stream_encoder_set_blocksize(enc,4096);
      const init=Flac.init_encoder_stream(enc,(data,bytes,samples)=>{const copy=data.slice();
        if(samples)frames.push({sample:sampleWritten,offset:bytesWritten,samples:samples});
        chunks.push(copy);bytesWritten+=bytes;sampleWritten+=samples},()=>{},false,0);
      if(init!==0){Flac.FLAC__stream_encoder_delete(enc);throw Error("Encoder initialization failed ("+init+").")}
      const feed=(pcm,samples)=>{if(samples&&!Flac.FLAC__stream_encoder_process_interleaved(enc,pcm,samples))return false;fed+=samples;return true};
      const quant=makeQuantizer();let resampler=null,runRate=0,runInput=0;
      const feedFloat=(o)=>o.l.length?feed(quant.pack(o.l,o.r,o.l.length),o.l.length):true;
      for(let i=0;i<tracks.length;i++){const track=tracks[i];
        const label=(track.action==="convert"?"Converting":"Decoding and encoding")+" track "+(i+1)+" of "+tracks.length+": "+track.file.name;
        setStatus(label,i,tracks.length+1);
        await new Promise(requestAnimationFrame);const bytes=new Uint8Array(await track.file.arrayBuffer());
        const progress=f=>setStatus(label,i+f,tracks.length+1);let decoded;
        if(track.action==="copy")decoded=await decode(bytes,(pcm,n)=>feed(pcm,n),progress);
        else{
          const resample=track.rate!==plan.rate;
          if(resample&&(!resampler||runRate!==track.rate)){resampler=makeResampler(track.rate,plan.rate);runRate=track.rate;runInput=0}
          decoded=await decode(bytes,(pcm,n,bits)=>{
            const l=new Float64Array(n),r=new Float64Array(n),scale=1/(1<<(bits-1));
            for(let k=0;k<n;k++){l[k]=pcm[k*2]*scale;r[k]=pcm[k*2+1]*scale}
            return feedFloat(resample?resampler.push(l,r,n):{l:l,r:r});
          },progress);
          if(resample)runInput+=decoded;
        }
        if(decoded!==track.samples)throw Error(track.file.name+" holds "+decoded+" samples but its header says "+track.samples+".");
        const next=tracks[i+1];
        if(resampler&&!(next&&next.action==="convert"&&next.rate===runRate)){if(!feedFloat(resampler.finish(runInput)))throw Error("FLAC encoder rejected PCM data.");resampler=null}
      }
      if(total>cursor&&!feed(new Int32Array((total-cursor)*2),total-cursor))throw Error("FLAC encoder rejected PCM data.");
      if(fed!==total)throw Error("Internal error: encoded "+fed+" of "+total+" samples.");
      const finalProgress=tracks.length;setStatus("Embedding CUESHEET, metadata, and artwork…",finalProgress,finalProgress+1);
      if(!Flac.FLAC__stream_encoder_finish(enc)){const code=Flac.FLAC__stream_encoder_get_state(enc);
        Flac.FLAC__stream_encoder_delete(enc);throw Error("Encoder finish failed ("+code+").")}
      const base=(ui.name.value.trim()||"album").replace(/[\\/:*?"<>|]+/g,"_");Flac.FLAC__stream_encoder_delete(enc);
      const encoded=join(chunks,bytesWritten),album=injectMetadata(encoded,frames,starts,total,albumApplication(tracks,{album:ui.album.value,artist:ui.artist.value,art:state.art}));
      const info=inspect(album);if(info.rate!==plan.rate||info.bits!==BPS||info.channels!==CHANNELS||info.samples!==total)throw Error("The built album failed verification.");
      state.output=new Blob([album],{type:"audio/flac"});state.outputUrl=URL.createObjectURL(state.output);
      ui.download.download=base+".flac";ui.download.href=state.outputUrl;ui.download.hidden=false;
      const note=plan.converting?" · "+plan.converted+" track"+(plan.converted===1?"":"s")+" converted to "+rateName(plan.rate)+" / 16-bit"+(quant.clipped()?" ("+quant.clipped().toLocaleString()+" samples clipped)":""):" · all samples preserved";
      setStatus("Album ready: "+size(album.length)+" · "+tracks.length+" tracks · "+time(total/plan.rate)+note,1,1);
    }catch(error){console.error(error);setStatus(error.message||String(error))}
    finally{state.busy=false;refresh()}
  }
  ui.choose.onclick=()=>ui.files.click();ui.files.onchange=()=>{add(ui.files.files);ui.files.value=""};
  ui.clear.onclick=()=>{state.tracks=[];state.albumEdited=state.artistEdited=state.artEdited=false;invalidate();refresh();setStatus("Add two or more tracks to begin.")};
  [["album","albumEdited"],["artist","artistEdited"]].forEach(([id,flag])=>{
    ui[id].oninput=()=>{state[flag]=true;invalidate()};
    ui[id].onchange=()=>{if(!ui[id].value.trim()){state[flag]=false;refresh()}}});
  ui.cover.onchange=async()=>{const file=ui.cover.files[0];
    try{if(file){state.art=await toRgb332(file);state.artEdited=true;showCover(state.art);invalidate();setStatus("Artwork ready: fitted to 92×92 RGB332.")}}
    catch(error){setStatus("Could not read artwork: "+(error.message||String(error)))}ui.cover.value=""};
  ui.convert.onchange=()=>{state.convert=ui.convert.checked;invalidate();refresh();if(state.tracks.length)setStatus(state.tracks.some(t=>t.error||t.issue)?"Remove incompatible tracks before building.":"Ready to build.")};
  ui.build.onclick=build;["dragenter","dragover"].forEach(type=>ui.drop.addEventListener(type,e=>{e.preventDefault();ui.drop.classList.add("drag")}));
  ["dragleave","drop"].forEach(type=>ui.drop.addEventListener(type,e=>{e.preventDefault();ui.drop.classList.remove("drag")}));
  ui.drop.addEventListener("drop",e=>add(e.dataTransfer.files));ui.drop.addEventListener("keydown",e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();ui.files.click()}});
  refresh();
})();
