# "Chaos factor": a crude 2D free-for-all brawl (6 heroes, respawns, 60 s) on top of the 1v1 numbers in heroes.json.
# Adds what a 1v1 hides: splash / cleave / chain / pierce hitting several foes, area skills, ults charged by damage
# (dealt + 0.35 x taken), third parties stealing kills, and the Chaos Lord's x0.5-3.5 roll on everything.
# Score = (kills - deaths) per match, averaged over many random lobbies.
import json, random, math, sys, os
D=os.path.dirname(os.path.abspath(__file__))
H=json.load(open(sys.argv[2] if len(sys.argv)>2 else os.path.join(D,'heroes.json')))
X=json.load(open(os.path.join(D,'extra.json')))
for k in H: H[k].update(X.get(k,{}))
DT=0.05; R=800.0
def roll(h,rnd): return rnd.uniform(0.5,3.5) if h.get('chaos') else 1.0
def hitp(h,d,t):
    if h['kind']=='melee': return 0.8
    if h['kind']=='instant': return 0.95
    if h.get('homing'): return 0.85
    tt=d/h['proj']; rad=h.get('rad',20)+14; drift=0.45*t.h['speed']*tt
    return max(0.2,min(0.97,rad/(rad+drift)))
class P:
    def __init__(s,k,rnd):
        s.k=k; s.h=H[k]; s.rnd=rnd; s.kills=0; s.deaths=0; s.dealt=0; s.spawn()
        s.ult=0
    def spawn(s):
        a=s.rnd.uniform(0,2*math.pi); s.x=math.cos(a)*R*0.8; s.y=math.sin(a)*R*0.8
        s.hp=s.h['hp']; s.cd=0; s.rcd=1; s.stun=0; s.slow=0; s.dead=0; s.buff=0; s.lives=s.h.get('lives',0); s.weak=0
def dist(a,b): return math.hypot(a.x-b.x,a.y-b.y)
def damage(src, dst, amt, ps, t):
    if dst.dead>0 or amt<=0: return
    mult=1.0
    if src.buff>0: mult*=src.h['ult'].get('out',1)
    if dst.buff>0: mult*=dst.h['ult'].get('taken',1)
    if src.buff>0 and src.h['ult'].get('blind'): pass
    amt*=mult*src.h.get('out',1)*dst.h.get('taken',1)
    dst.hp-=amt; src.dealt+=amt
    src.ult+=amt; dst.ult+=amt*0.35*dst.h.get('ult_taken',1)
    if src.h.get('steal'): src.hp=min(src.h['hp'],src.hp+amt*src.h['steal'])
    if dst.hp<=0:
        if dst.lives>0: dst.lives-=1; dst.hp=min(67,dst.h['hp']); return
        dst.dead=3.0; dst.deaths+=1; src.kills+=1
def splash(src, center, radius, amt, ps, t, skip=None, stun=0, slow=0):
    for o in ps:
        if o is src or o.dead>0 or o is skip: continue
        if math.hypot(o.x-center[0],o.y-center[1])<=radius+14:
            damage(src,o,amt,ps,t)
            if stun: o.stun=max(o.stun,stun)
            if slow: o.slow=max(o.slow,slow)
def match(keys, seed):
    rnd=random.Random(seed); ps=[P(k,rnd) for k in keys]; t=0
    while t<60:
        t+=DT
        for p in ps:
            if p.dead>0:
                p.dead-=DT
                if p.dead<=0: p.spawn()
                continue
            for a in ('cd','rcd','stun','slow','buff'): setattr(p,a,max(0,getattr(p,a)-DT))
            if p.stun>0: continue
            h=p.h
            live=[o for o in ps if o is not p and o.dead<=0]
            if not live: continue
            tgt=min(live,key=lambda o: dist(p,o)*(0.6+0.4*o.hp/o.h['hp'])+rnd.uniform(0,80))
            d=dist(p,tgt); ux=(tgt.x-p.x)/max(d,1); uy=(tgt.y-p.y)/max(d,1)
            reach=h['reach']; rate=(h['ult'].get('rate',1) if p.buff>0 else 1)
            want=reach*(0.62 if h['kind']!='melee' else 0.6)
            spd=h['speed']*(0.6 if p.slow>0 else 1)
            threat=min(live,key=lambda o: dist(p,o)-o.h['reach'])
            if h['kind']!='melee' and dist(p,threat)<threat.h['reach']*1.4 and threat.h['reach']<reach:
                vx=(p.x-threat.x)/max(dist(p,threat),1); vy=(p.y-threat.y)/max(dist(p,threat),1); m=0.9
            elif d>want: vx,vy,m=ux,uy,1
            else: vx,vy,m=-uy,ux,0.4
            p.x+=vx*spd*m*DT; p.y+=vy*spd*m*DT
            r=math.hypot(p.x,p.y)
            if r>R: p.x*=R/r; p.y*=R/r
            if h.get('dot') and d<=h.get('dot_range',reach): splash(p,(p.x,p.y),h.get('dot_range',reach),h['dot']*DT,ps,t)
            if p.buff>0 and h['ult'].get('dot'): splash(p,(p.x,p.y),h['ult']['dot_range'],h['ult']['dot']*DT,ps,t)
            # ult
            u=h['ult']
            if p.ult>=u['cost'] and d<=max(u.get('range',0),u.get('aoe',0)*0.8,300):
                p.ult=0
                if u.get('buff'): p.buff=u['buff']
                if u.get('aoe'):
                    c=(p.x,p.y) if u.get('range',1)==0 else (tgt.x,tgt.y)
                    if rnd.random()<u.get('p',0.85):
                        st=u.get('stun',0) or u.get('stun_roll',0)*roll(h,rnd)
                        for o in ps:
                            if o is p or o.dead>0 or math.hypot(o.x-c[0],o.y-c[1])>u['aoe']+14: continue
                            dmg=u.get('dmg',0)+u.get('dmg_frac',0)*o.h['hp']
                            if dmg: damage(p,o,dmg,ps,t)
                            if st: o.stun=max(o.stun,st)
                            if u.get('slow'): o.slow=max(o.slow,u['slow'])
                elif u.get('dmg') and rnd.random()<u.get('p',0.85): damage(p,tgt,u['dmg'],ps,t)
            # rmb
            rm=h.get('rmb')
            if rm and p.rcd<=0 and d<=rm['range']:
                p.rcd=rm['cd']
                if rm.get('gap'):
                    g=max(0,min(rm['gap'],d-reach*0.5)); p.x+=ux*g; p.y+=uy*g
                if rnd.random()<rm.get('p',0.8):
                    k=roll(h,rnd)
                    rad=h.get('rmb_aoe',0)
                    if rad: splash(p,(tgt.x,tgt.y),rad,rm['dmg']*k,ps,t,stun=rm.get('stun',0)*k,slow=rm.get('slow',0))
                    else:
                        damage(p,tgt,rm['dmg']*k,ps,t)
                        if rm.get('stun'): tgt.stun=max(tgt.stun,rm['stun']*k)
                        if rm.get('slow'): tgt.slow=max(tgt.slow,rm['slow'])
                    if rm.get('heal'): p.hp=min(h['hp'],p.hp+rm['heal'])
            # basic
            if p.cd<=0 and d<=reach:
                p.cd=h['cd']/rate
                if rnd.random()<hitp(h,d,tgt):
                    dmg=h['dmg']*roll(h,rnd)
                    damage(p,tgt,dmg,ps,t)
                    others=[o for o in live if o is not tgt]
                    if h.get('aoe'): splash(p,(tgt.x,tgt.y),h['aoe'],dmg,ps,t,skip=tgt)
                    if h.get('cleave'):
                        for o in others:
                            od=dist(p,o)
                            if od<=reach and ((o.x-p.x)*ux+(o.y-p.y)*uy)/max(od,1)>math.cos(h['cleave']*1.4): damage(p,o,dmg,ps,t)
                    if h.get('chain'):
                        cur=tgt; f=1
                        for _ in range(h['chain']):
                            nxt=[o for o in others if dist(cur,o)<230]
                            if not nxt: break
                            cur=min(nxt,key=lambda o:dist(cur,o)); others.remove(cur); f*=0.75; damage(p,cur,dmg*f,ps,t)
                    if h.get('pierce'):
                        for o in others[:h['pierce']]:
                            od=dist(p,o)
                            if od<reach and abs((o.x-p.x)*uy-(o.y-p.y)*ux)<40 and (o.x-p.x)*ux+(o.y-p.y)*uy>d: damage(p,o,dmg,ps,t)
    return ps
N=int(sys.argv[1]) if len(sys.argv)>1 else 300
ids=list(H); sc={k:[0,0,0,0] for k in ids}
for s in range(N):
    rnd=random.Random(s*7+1); keys=rnd.sample(ids,6)
    for p in match(keys,s):
        a=sc[p.k]; a[0]+=p.kills; a[1]+=p.deaths; a[2]+=p.dealt; a[3]+=1
rank=sorted(ids,key=lambda k:-(sc[k][0]-sc[k][1])/sc[k][3])
print(f"{'hero':11} {'K-D/match':>9} {'K/D':>5} {'dmg/match':>9}")
for k in rank:
    a=sc[k]; print(f"{k:11} {(a[0]-a[1])/a[3]:9.2f} {a[0]/max(a[1],1):5.2f} {a[2]/a[3]:9.0f}")
