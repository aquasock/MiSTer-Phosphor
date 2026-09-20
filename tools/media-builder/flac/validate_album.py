#!/usr/bin/env python3
"""Validate a FLAC album image against MiSTer_MP3's FPGA profile."""
from pathlib import Path
import argparse
def u24(b): return int.from_bytes(b,"big")
def main():
 p=argparse.ArgumentParser();p.add_argument("file",type=Path);a=p.parse_args();data=a.file.read_bytes()
 if data[:4]!=b"fLaC":raise SystemExit("FAIL: not native FLAC")
 pos=4;stream=cue=seeks=None
 while True:
  h=data[pos:pos+4]
  if len(h)!=4:raise SystemExit("FAIL: truncated metadata")
  last=bool(h[0]&128);kind=h[0]&127;length=u24(h[1:]);body=data[pos+4:pos+4+length]
  if len(body)!=length:raise SystemExit("FAIL: truncated metadata body")
  if kind==0:stream=body
  elif kind==3:seeks=body
  elif kind==5:cue=body
  pos+=4+length
  if last:break
 if stream is None or len(stream)!=34:raise SystemExit("FAIL: STREAMINFO")
 packed=int.from_bytes(stream[10:18],"big");rate=(packed>>44)&0xfffff;channels=((packed>>41)&7)+1;bits=((packed>>36)&31)+1;total=packed&0xfffffffff
 if rate not in(44100,48000) or (channels,bits)!=(2,16):raise SystemExit(f"FAIL: profile {rate} Hz/{bits}-bit/{channels}ch")
 if cue is None or len(cue)<396 or not cue[136]&128:raise SystemExit("FAIL: CD CUESHEET missing")
 if seeks is None or len(seeks)%18 or not 1<=len(seeks)//18<=512:raise SystemExit("FAIL: SEEKTABLE")
 count=cue[395]
 if not 2<=count<=100:raise SystemExit(f"FAIL: CUESHEET record count {count}")
 off=396;starts=[]
 for i in range(count):
  if off+36>len(cue):raise SystemExit("FAIL: truncated CUESHEET track")
  sample=int.from_bytes(cue[off:off+8],"big");number=cue[off+8];indices=cue[off+35];off+=36
  if number==170:
   if i!=count-1 or indices!=0 or sample!=total:raise SystemExit("FAIL: lead-out")
  else:
   if number!=i+1 or indices<1:raise SystemExit("FAIL: track numbering/index")
   if off+indices*12>len(cue) or cue[off+8]!=1:raise SystemExit("FAIL: INDEX 01")
   starts.append(sample)
  off+=indices*12
 if off!=len(cue)or not starts or starts[0]!=0 or starts!=sorted(set(starts)):raise SystemExit("FAIL: CUESHEET layout")
 if total%588 or any(s%588 for s in starts):raise SystemExit("FAIL: CUESHEET offsets are not CD-sector (588-sample) aligned")
 previous=-1
 for i in range(0,len(seeks),18):
  sample=int.from_bytes(seeks[i:i+8],"big");offset=int.from_bytes(seeks[i+8:i+16],"big");frame=int.from_bytes(seeks[i+16:i+18],"big")
  if sample<=previous or sample>=total or offset>=len(data)-pos or frame==0:raise SystemExit("FAIL: seek point")
  previous=sample
 print(f"PASS: {len(starts)} tracks, {total} samples, {len(seeks)//18} seek points, {len(data)} bytes")
if __name__=="__main__":main()
