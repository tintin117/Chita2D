# Crude 1v1 duel sim on a line, to rank heroes. Not the game: it models movement speed, reach, attack rate,
# projectile speed / homing (hit chance vs a strafing target), kiting in a bounded arena, dashes, the RMB as a
# periodic burst with its CC, and a few passives. Ults are left out (fights here are one exchange).
import random, math, json, sys
H = json.load(open(sys.argv[2] if len(sys.argv)>2 and sys.argv[2].endswith('.json') else __import__('os').path.join(__import__('os').path.dirname(__file__), 'heroes.json')))
DT=0.05; ARENA=1300.0; DASH=240.0; DASH_RE=2.5
def hitp(h, dist, tgt):
    if h['kind']=='melee': return 0.85
    if h['kind']=='instant': return 0.95
    if h.get('homing'): return 0.88           # a dash shakes it off
    t = dist / h['proj']
    rad = h.get('rad', 20) + 14
    drift = 0.45 * tgt['speed'] * t          # how far a strafing target slips during the flight
    return max(0.2, min(0.97, rad / (rad + drift)))
def duel(a, b, seed):
    rnd = random.Random(seed)
    S = [dict(h=a, hp=a['hp'], pos=0.0, cd=0, rcd=1.0, dash=2, dre=0, stun=0, slow=0, lives=a.get('lives', 0)),
         dict(h=b, hp=b['hp'], pos=700.0, cd=0, rcd=1.0, dash=2, dre=0, stun=0, slow=0, lives=b.get('lives', 0))]
    t=0
    while t<40:
        t+=DT
        for i in (0,1):
            me, op = S[i], S[1-i]; h=me['h']; oh=op['h']
            for k in ('cd','rcd','stun','slow'): me[k]=max(0,me[k]-DT)
            if me['dash']<2:
                me['dre']-=DT
                if me['dre']<=0: me['dash']+=1; me['dre']=DASH_RE
            if me['stun']>0: continue
            d = abs(me['pos']-op['pos']); sgn = 1 if op['pos']>me['pos'] else -1
            reach = h['reach']
            spd = h['speed'] * (0.6 if me['slow']>0 else 1.0)
            # movement: close to ~85% of reach, or kite away from a closer-reaching threat
            want = reach*0.85
            if oh['reach'] < reach and d < max(oh['reach']*1.6, want*0.7):   # a shorter-reach foe is near: back off
                step = -sgn*spd*0.9*DT
                edge = abs(me['pos'] + step - 650) > ARENA/2
                if edge: step *= 0.35                                  # cornered: circling only half works
                me['pos'] += step
                if d < oh['reach']*1.2 and me['dash']>0 and rnd.random()<0.2: me['pos'] += -sgn*DASH*(0.4 if edge else 1); me['dash']-=1
            elif d > want:
                me['pos'] += sgn*min(spd*DT, d-want)
                if h['kind']=='melee' and d>reach+120 and me['dash']>0 and rnd.random()<0.08: me['pos']+=sgn*min(DASH,d-reach*0.6); me['dash']-=1
            d = abs(me['pos']-op['pos'])
            # RMB
            r = h.get('rmb')
            if r and me['rcd']<=0 and d <= r['range']:
                me['rcd']=r['cd']
                if r.get('gap'): me['pos'] += sgn*max(0,min(r['gap'], d-reach*0.5))
                if rnd.random() < r.get('p',0.8):
                    dmg = r['dmg'] * (rnd.uniform(0.5,3.5) if h.get('chaos') else 1)
                    hit(op, dmg*h.get('out',1), rnd)
                    if r.get('stun'): op['stun']=max(op['stun'], r['stun']*(rnd.uniform(0.5,3.5) if h.get('chaos') else 1))
                    if r.get('slow'): op['slow']=max(op['slow'], r['slow'])
                    if r.get('heal'): me['hp']=min(h['hp'], me['hp']+r['heal'])
            # basic
            if me['cd']<=0 and d <= reach:
                me['cd']=h['cd']
                if rnd.random() < hitp(h, d, oh):
                    dmg = h['dmg']
                    if h.get('chaos'): dmg *= rnd.uniform(0.5,3.5)
                    if h.get('range_bonus'): dmg += d*h['range_bonus']
                    hit(op, dmg*h.get('out',1), rnd)
                    if h.get('steal'): me['hp']=min(h['hp'], me['hp']+dmg*h['steal'])
            # passive damage over time while in contact (burn, trail, stride...)
            if h.get('dot') and d <= h.get('dot_range', reach): hit(op, h['dot']*DT, rnd)
        for i in (0,1):
            if S[i]['hp']<=0:
                if S[i]['lives']>0: S[i]['lives']-=1; S[i]['hp']=min(67,S[i]['h']['hp']); continue
                return 1-i, t
    return (0 if S[0]['hp']/S[0]['h']['hp'] > S[1]['hp']/S[1]['h']['hp'] else 1), t
def hit(o, dmg, rnd):
    o['hp'] -= dmg * o['h'].get('taken',1)
ids=list(H)
N=int(sys.argv[1]) if len(sys.argv)>1 else 60
wins={k:0 for k in ids}; games={k:0 for k in ids}; mat={}
for a in ids:
    for b in ids:
        if a>=b: continue
        w=0; tt=0
        for s in range(N):
            if s%2: r,t = duel(H[a],H[b],s)
            else:
                r,t = duel(H[b],H[a],s); r=1-r
            w += (r==0); tt+=t
        mat[(a,b)]=w/N; wins[a]+=w; wins[b]+=N-w; games[a]+=N; games[b]+=N
rank=sorted(ids,key=lambda k:-wins[k]/games[k])
for k in rank: print(f"{k:11} {wins[k]/games[k]*100:5.1f}%")
if '-m' in sys.argv:
    print(' '*11+''.join(f"{k[:5]:>6}" for k in rank))
    for a in rank:
        row=''
        for b in rank:
            if a==b: row+='     -'
            else: row+=f"{(mat[(a,b)] if (a,b) in mat else 1-mat[(b,a)])*100:6.0f}"
        print(f"{a:11}{row}")
