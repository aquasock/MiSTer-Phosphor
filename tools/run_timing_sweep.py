#!/usr/bin/env python3
"""Run eight-corner STA concurrently in isolated seed directories."""
import argparse,concurrent.futures,csv,json,pathlib,subprocess,time

def summarize(directory):
 records=[]
 with (directory/'corners.tsv').open() as file:
  for row in csv.DictReader(file,delimiter='\t'):
   row['timing']={}
   for kind in ['setup','hold','recovery','removal','mpw']:
    values=[]
    for line in (directory/row['directory']/f'{kind}_summary.rpt').read_text().splitlines():
     fields=line.split(';')
     if len(fields)>=5:
      try:values.append((float(fields[2]),float(fields[3])))
      except ValueError:pass
    if not values:raise RuntimeError(f'Missing {kind} results in {row["directory"]}')
    row['timing'][kind]={'slack':min(x[0] for x in values),'tns':sum(x[1] for x in values)}
   records.append(row)
 if len(records)!=8:raise RuntimeError(f'Expected eight corners, found {len(records)}')
 return {'minima':{kind:min(row['timing'][kind]['slack'] for row in records) for kind in records[0]['timing']},'corners':records}

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('build_root',type=pathlib.Path)
 parser.add_argument('--seeds',type=int,nargs='+',default=[52,61,87])
 parser.add_argument('--wait-for-compile',action='store_true')
 args=parser.parse_args();root=args.build_root.resolve()
 if len(set(args.seeds))!=len(args.seeds):parser.error('Seed directories must be distinct.')
 def run(seed):
  directory=root/f'seed{seed}'
  if args.wait_for_compile:
   while True:
    log=directory/'compile.log';text=log.read_text(errors='replace') if log.exists() else ''
    if 'Full Compilation was successful' in text:break
    if 'Error (' in text or 'Full Compilation was unsuccessful' in text:
     raise RuntimeError(f'Seed {seed} compilation failed; see {log}')
    time.sleep(5)
  print(f'Timing seed {seed} started',flush=True)
  with (directory/'timing.log').open('w') as log:
   subprocess.run(['quartus_sta','-t','tools/check_timing_corners.tcl'],cwd=directory,stdout=log,stderr=subprocess.STDOUT,check=True)
  result=summarize(directory/'timing_corners')
  print(f'Timing seed {seed} complete: {result["minima"]}',flush=True)
  return result
 results={};errors={}
 with concurrent.futures.ThreadPoolExecutor(max_workers=len(args.seeds)) as pool:
  futures={pool.submit(run,seed):seed for seed in args.seeds}
  for future in concurrent.futures.as_completed(futures):
   seed=str(futures[future])
   try:results[seed]=future.result()
   except Exception as error:errors[seed]=str(error);print(f'Timing seed {seed} failed: {error}',flush=True)
 (root/'timing_results.json').write_text(json.dumps(results,indent=2)+'\n')
 if errors:(root/'timing_errors.json').write_text(json.dumps(errors,indent=2)+'\n')
 passed=not errors and all(value['slack']>=0 and value['tns']==0 for result in results.values() for corner in result['corners'] for value in corner['timing'].values())
 print('All seeds pass constrained timing.' if passed else 'One or more seeds failed; inspect timing_results.json and logs.',flush=True)
 return 0 if passed else 1

if __name__=='__main__':raise SystemExit(main())
