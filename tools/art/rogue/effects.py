from pathlib import Path
import numpy as np
from math import tau
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[3] / 'assets/isometric_projecttile/Spells/Rogue'
root.mkdir(exist_ok=True)
def bake_smoke():
    cell_size = 176
    columns, frames, fps = 8, 56, 12
    source = np.asarray(Image.open(Path(__file__).parent / 'sources/crimson-soot.png').convert('RGBA'),
                        dtype=np.float32)/255
    screen_y,screen_x = np.mgrid[:cell_size,:cell_size]
    x = (screen_x+.5-cell_size*.5)/(cell_size*.5)
    y = (screen_y+.5-cell_size*.5)/(cell_size*.5)
    radius = np.hypot(x,y)
    edge = np.clip((1-radius)/.075,0,1)
    atlas = Image.new('RGBA',(cell_size*columns, cell_size*((frames+columns-1)//columns)))
    rng = np.random.default_rng(147)
    # The first few frames shed a fine fan of airborne droplets into the haze.
    droplets = tuple(zip(rng.uniform(-np.pi,np.pi,52), rng.uniform(.45,1.15,52),
                         rng.uniform(.18,.60,52), rng.uniform(.02,.14,52)))

    # The painted crest drives the eruption. Secondary curls shear past it and
    # rise at different speeds. Each tuple sets center, width, height and opacity.
    banks = (
        (-.31,.47,1.20,.77,.53),
        (.37,.34,1.18,.73,.60),
        (-.44,.02,1.13,.71,.44),
        (.32,-.36,1.18,.73,.59),
        (-.14,-.28,1.29,.83,.44),
        (.00,.03,1.83,1.25,.92),
        (.27,-.49,.91,.71,.39),
        (-.38,-.47,.91,.75,.44),
        (.50,.10,.84,.57,.34),
    )
    for frame in range(frames):
        t = frame/fps
        bloom = 1-np.exp(-11*(t+.035))
        surge = np.exp(-max(0,t-.23)*1.25)
        fade = np.clip((4.77-t)/.57,0,1)
        rgba = np.zeros((cell_size,cell_size,4),np.float32)
        for i,(cx,cy,width,height,weight) in enumerate(banks):
            phase = i*1.79
            travel = t*(.11+.009*i)
            drift_x = (np.sin(travel*4+phase)-np.sin(phase))*.16
            drift_y = -.18*np.sin(t*.87+i*.21)+.18*np.sin(i*.21)
            wave = .12*np.sin(3*y+t*2+phase) + .064*np.sin(9*y-4*x+t*1.1)
            roll = .09*np.cos(5*x+t*1.7+phase)
            stretch = (.57+.43*bloom) * (1+.14*np.sin(t*1.9+i))
            u = (x-cx*bloom-drift_x+wave)/(width*stretch)+.5
            v = (y-cy*bloom-drift_y+roll)/(height*stretch)+.5
            if i%3==1:
                u = 1-u
            ix = np.clip(np.rint(u*175).astype(int),0,175)
            iy = np.clip(np.rint(v*79).astype(int),0,79)
            painted = source[iy,ix]
            in_bank = (u>=0)&(u<=1)&(v>=0)&(v<=1)
            swirl = .83+.17*np.sin(16*x-14*y+t*2+phase)
            density = painted[:,:,3]*in_bank*edge*weight*swirl*bloom*fade
            heat = (.41+.59*surge)*(1.0 if i==5 else .70+.05*(i%3))
            ash = (.13 + (painted[:,:,0]+painted[:,:,1])*.18)
            vapor = np.stack((ash*1.12,ash*.60,ash*.67),axis=2)
            red_crest = np.clip((painted[:,:,0]-painted[:,:,1])*.85,0,.42)*surge
            vivid = np.clip(painted[:,:,:3]*(1.43,.70,.69) + red_crest[:,:,None]*(1,.03,.03),0,1)
            color = vivid*heat+(1-heat)*vapor
            mix = density[:,:,None]
            rgba[:,:,:3] = rgba[:,:,:3]*(1-mix)+color*mix
            rgba[:,:,3] = rgba[:,:,3]*(1-density)+density
        alpha = rgba[:,:,3]
        pixels = np.zeros((cell_size,cell_size,4),dtype=np.uint8)
        color = rgba[:,:,:3]/np.maximum(alpha[:,:,None],1e-5)
        pixels[:,:,:3] = (np.round(np.clip(color,0,1)*31)*8).astype(np.uint8)
        pixels[:,:,3] = (np.round(alpha*24)*10).astype(np.uint8)
        pixels[pixels[:,:,3]==0] = 0
        cel = Image.fromarray(pixels)
        grit = Image.new('RGBA',cel.size)
        ink = ImageDraw.Draw(grit)
        for heading,speed,lifetime,delay in droplets:
            age = t-delay
            if not 0 < age < lifetime:
                continue
            distance = .13+speed*(1-np.exp(-7*age))*.73
            dx = distance*np.cos(heading)
            dy = distance*np.sin(heading)-.09*np.sin(4*age)
            if np.hypot(dx,dy) >= .96:
                continue
            point = (round((1+dx)*(cell_size-1)*.5),round((1+dy)*(cell_size-1)*.5))
            color = (206,21,49,round(214*(1-age/lifetime)))
            ink.point(point,fill=color)
            if speed>.93 and age<.23:
                ink.point((point[0],point[1]+1),fill=color)
        cel.alpha_composite(grit)
        atlas.paste(cel,(cell_size*(frame%columns),cell_size*(frame//columns)))
    atlas.save(root / 'SmokeScreen.png', optimize=True)

impact = Image.new('RGBA', (160, 32))
for frame in range(5):
    cell = Image.new('RGBA', (32, 32))
    draw = ImageDraw.Draw(cell)
    alpha = [255, 255, 204, 128, 65][frame]
    length = [11, 15, 15, 12, 7][frame]
    x = 14 + frame
    draw.polygon([(x-length,16),(x-3,14),(x,10),(x+2,14),(x+length,16),
                  (x+2,17),(x,21),(x-2,18)], fill=(156,193,222,alpha))
    if frame < 4:
        draw.polygon([(x-8,16),(x-2,15),(x,12),(x+1,15),(x+9,16),
                      (x+1,17),(x,19),(x-1,17)], fill=(245,246,235,alpha))
    for offset in range(3):
        draw.point((x+4+offset*2+frame,13-offset*2),fill=(212,230,245,alpha))
    impact.paste(cell,(frame*32,0))
impact.save(root / 'SilverImpact.png')

icons = Image.new('RGBA', (16,64))
for i in range(4):
    icon = Image.new('RGBA',(16,16))
    d = ImageDraw.Draw(icon)
    d.rounded_rectangle((0,0,15,15), radius=2, fill='#191c2d', outline='#485069')
    if i == 0:
        d.polygon([(3,11),(5,13),(7,10),(13,3),(9,4),(5,9)],fill='#98aecb')
        d.line((7,9,13,3),fill='#eef5ff')
        d.line((2,12,5,9),fill='#bc8d63')
    if i == 1:
        for x, c in [(3,'#434d79'),(6,'#566a9b'),(9,'#a2b8e3')]:
            d.line((x,10,x+3,7,x+1,5,x+4,4),fill=c,width=2)
        d.point((13,4),fill='#e3f3ff')
    if i == 2:
        d.ellipse((4,3,11,10),fill='#d5c49e')
        d.rectangle((6,9,9,11),fill='#b49e7e')
        d.point((6,7),fill='#292630')
        d.point((9,7),fill='#292630')
        d.line((7,12,8,13,8,14),fill='#577fc4')
    if i == 3:
        d.polygon([(2,11),(2,8),(5,7),(5,4),(9,3),(12,5),(12,7),(14,9),(13,12),(9,13),(4,12)],fill='#502433')
        d.polygon([(3,10),(6,8),(6,5),(9,5),(11,8),(10,10),(13,10),(11,12),(6,11)],fill='#b33e4d')
        d.line((6,9,8,7,9,7),fill='#f06765')
    icons.paste(icon,(0,i*16))
icons.save(root / 'SkillIcons.png')

if __name__ == '__main__':
    bake_smoke()
