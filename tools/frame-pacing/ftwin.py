# ftwin.py TRACE.txt EVENTS.txt [SECONDS]: per input event, the frames in the
# next SECONDS (default 1.0): count, wall intervals, CPU time of the busy
# threads and GPU job time per client in that window.
import re,sys,collections,bisect
ts=lambda l:float(re.search(r"\s(\d+\.\d+):",l).group(1))
W=float(sys.argv[3]) if len(sys.argv)>3 else 1.0
fl=[];sw=[];cur={};jobs=[];run={};q={}
for l in open(sys.argv[1]):
    if "drm_vblank_event_delivered" in l: fl.append(ts(l))
    elif "sched_switch:" in l:
        m=re.search(r"\[(\d+)\].*sched_switch:\s+(.+?):(\d+) .*==> (.+?):(\d+) ",l)
        if not m: continue
        cpu,pc,pp,nc,np_=m.groups(); t=ts(l)
        if cpu in cur and cur[cpu][1][1]!="0": sw.append((cur[cpu][0],t,cur[cpu][1]))
        cur[cpu]=(t,(nc,np_))
    elif "drm_sched_job_queue" in l:
        m=re.search(r"fence=(\S+),",l); q[m.group(1)]=l.split("-")[0].strip()
    elif "drm_sched_job_run" in l: run[re.search(r"fence=(\S+),",l).group(1)]=ts(l)
    elif "drm_sched_job_done" in l:
        fe=re.search(r"fence=(\S+) ",l).group(1)
        if fe in run: jobs.append((run[fe],ts(l),q.get(fe,"?")))
ev=[float(x) for x in open(sys.argv[2])]
for t in ev:
    a,b=t,t+W
    f=[x for x in fl if a<=x<b]
    iv=[round((y-x)*1000,1) for x,y in zip(f,f[1:])]
    cpu=collections.Counter()
    for s,e,k in sw:
        if e>a and s<b: cpu[k]+=min(e,b)-max(s,a)
    g=collections.Counter()
    for s,e,c in jobs:
        if e>a and s<b: g[c]+=min(e,b)-max(s,a)
    print(f"event {t:.3f}: {len(f)} frames, first after {((f[0]-t)*1000 if f else -1):.0f} ms, intervals ms {iv[:14]}")
    print("   cpu ms:", ", ".join(f"{k[0]}:{k[1]} {v*1000:.0f}" for k,v in cpu.most_common(6)))
    print("   gpu ms:", ", ".join(f"{k} {v*1000:.0f}" for k,v in g.most_common(4)))
