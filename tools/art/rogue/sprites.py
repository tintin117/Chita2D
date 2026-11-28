"""Bake Chita's Rogue using the costume and pose pixels from the supplied board."""
from functools import lru_cache
from math import cos, pi, sin, tau
from pathlib import Path
from sys import argv

import numpy as np
from PIL import Image, ImageDraw

PROJECT = Path(__file__).resolve().parents[3]
BOARD = Path(__file__).parent / 'sources/skeleton-reference.png'
OUTPUT = PROJECT / 'assets/isometric_character/11Rogue'
CELL = 128
SCALE = .69
FRAMES = 15

# Per-facing landmarks in the 88 × 100 cutouts from the reference board:
# skull, belt, weapon hand, free hand, knees and the planted boots.
CENTERS = [67,199,338,475,614,754,891,1040]
POSES = [
    ((55,21),(51,52),(31,60),(76,50),(36,69),(64,63),(30,85),(66,76),(24,73)),
    ((56,23),(54,55),(32,54),(73,59),(37,65),(67,69),(28,76),(72,84),(26,68)),
    ((42,22),(50,51),(37,46),(55,63),(38,63),(56,72),(34,69),(57,87),(21,49)),
    ((42,15),(48,49),(33,58),(44,48),(39,68),(57,64),(36,85),(61,76),(27,61)),
    ((45,12),(51,44),(25,47),(65,38),(30,59),(65,57),(25,74),(67,69),(22,49)),
    ((50,9),(51,43),(72,46),(30,37),(35,56),(67,55),(34,65),(72,72),(77,57)),
    ((57,12),(52,46),(73,52),(39,37),(43,57),(62,65),(39,75),(60,81),(85,41)),
    ((51,16),(45,55),(57,59),(32,39),(39,69),(52,66),(35,86),(52,77),(78,61)),
]
WALK_CLIPS = ('Run','RunBackwards','StrafeLeft','StrafeRight')
CLIPS = ('Idle',*WALK_CLIPS,'Melee','CastSpell','Special1')

# Screen-pixel offsets from the donor board to the roster's pitched view.
# Feet stay planted. The upper body leans toward its facing and foreshortens.
HEAD_PITCH = ((6,7),(0,8),(-6,7),(-6,5),(-5,3),(0,3),(5,3),(6,5))
WAIST_PITCH = ((1,3),(0,4),(-1,3),(-2,2),(-1,2),(0,1),(1,2),(2,2))
SKULL = {
    'front': ('  abbbc  ',' abbbbdc ','abbbbbddc','abbbbbbde',' abbdebee',' bbdeeede','  ddbdde ','   cddd  '),
    'side':  ('  abbbc  ',' abbbbdc ','abbbbbddc','abbbbbdde',' abbdbede',' abdddee ','  ddddce ','   cccc  '),
    'rear':  ('  abbbc  ',' abbbbdc ','abbbbbddc','abbbbbddc',' abbbbdec','  bdddec ','   cccc  '),
}
BONE = dict(a='#d8bf91', b='#baa77f', c='#665748', d='#908164', e='#3c3430')

@lru_cache(None)
def costume(facing):
    center = CENTERS[facing]
    source = Image.open(BOARD).convert('RGB')
    tile = source.crop((center-44,22,center+44,122))
    rgb = np.asarray(tile).astype(float)
    outside = np.concatenate((rgb[:,:4].reshape(-1,3),rgb[:,-4:].reshape(-1,3),rgb[-4:].reshape(-1,3)))
    background = np.median(outside,axis=0)
    distance = np.max(np.abs(rgb-background),axis=2)
    alpha = np.clip((distance-12)/22,0,1)
    alpha[alpha < .18] = 0
    # Remove the board's matte from the original antialiased silhouette.
    relief = np.clip((rgb-background*(1-alpha[:,:,None]))/np.maximum(.10,alpha[:,:,None]),0,255)
    # Group the reference's soft transitions into the clearer value steps used
    # by the in-game roster, while keeping the wrap, leather and bone colors.
    luminance = (relief[:,:,0]*.25 + relief[:,:,1]*.55 + relief[:,:,2]*.20)
    step = np.round(((luminance-58)*1.25+65)/9)*9
    relief = np.clip(relief+(step-luminance)[:,:,None],0,255)
    alpha = np.where(alpha >= .64,1.0,np.round(alpha*4)/4)
    data = np.dstack((relief,alpha*255)).astype(np.uint8)

    skull, belt, weapon, hand, knee_l, knee_r, boot_l, boot_r, tip = map(np.array, POSES[facing])
    yy,xx = np.mgrid[:tile.height,:tile.width]
    old_skull = (abs(xx-skull[0]) < 9) & (yy >= skull[1]-8) & (yy <= skull[1]+8)
    old_skull &= (relief[:,:,0] > 90) & (relief[:,:,0] > relief[:,:,2]+15)
    data[old_skull] = 0
    # Isolate the figure's costume. The held dagger is redrawn independently on
    # the same hand so the blade-tip glint stays attached throughout a strike.
    if facing in (0,1,2,5,6,7):
        direction = (tip-weapon)/np.linalg.norm(tip-weapon)
        start = weapon + direction*4.3
        blade_mask = Image.new('1', tile.size)
        paint = ImageDraw.Draw(blade_mask)
        paint.line((*start,*(tip+direction*2.0)), fill=1, width=4)
        data[np.asarray(blade_mask)] = 0

    outline = Image.fromarray(data)
    outline = outline.resize((round(tile.width*SCALE),round(tile.height*SCALE)),Image.Resampling.NEAREST)
    offset = np.array((round(64-belt[0]*SCALE),round(98-(boot_l[1]+boot_r[1])*.5*SCALE)))
    img = Image.new('RGBA',(CELL,CELL))
    img.paste(outline,tuple(offset))
    joints = np.array([skull,belt,weapon,hand,knee_l,knee_r,boot_l,boot_r,tip])*SCALE+offset
    return img,joints

@lru_cache(None)
def motion_fields(facing):
    img,joints = costume(facing)
    y,x = np.mgrid[:CELL,:CELL]
    grid = np.stack((x,y),axis=-1)
    handles = joints[:-1]
    distance2 = np.sum((grid[:,:,None,:]-handles)**2,axis=-1)
    weights = 1/np.power(4.0+distance2,2.5)
    weights /= weights.sum(axis=2,keepdims=True)
    # Keep the world-footprint shadow under the moving pose.
    rgb = np.asarray(img)[:,:,:3].astype(np.int16)
    r,g,b = np.moveaxis(rgb,2,0)
    shadow = (r <= g+1) & (b <= g+1) & (y > joints[1,1]+8) & (r < 68)
    return grid,weights,shadow

def pose_offsets(facing, clip, frame):
    angle = (facing+1)*pi/4
    forward = np.array((cos(angle),sin(angle)*.79))
    lateral = np.array((-sin(angle),cos(angle)*.79))
    phase = frame*tau/FRAMES
    motion = np.zeros((8,2))
    motion[0] = np.array(HEAD_PITCH[facing]) + (0,.55*cos(phase))
    motion[1] = np.array(WAIST_PITCH[facing]) + (0,-.35*cos(phase))
    motion[2] = forward*2.0 + (0,1.5)
    motion[3] = forward*2.0 + (0,1.5)
    motion[4] = forward*1.1
    motion[5] = forward*1.1
    if clip in WALK_CLIPS:
        travel = {'Run':forward,'RunBackwards':-forward,'StrafeLeft':-lateral,'StrafeRight':lateral}[clip]
        motion[0] += travel*3.6 + (0,-1.4*abs(cos(phase)))
        motion[1] += travel*1.4 + (0,-1.2*abs(cos(phase)))
        for i, side in enumerate((-1,1)):
            step = sin(phase)*side
            motion[2+i] -= travel*step*3.5
    elif clip == 'Melee':
        thrust = (0,-.18,.56,1,1,.90,.70,.52,.36,.24,.14,.06,0,0,0)[frame]
        motion[0] += forward*4.1*thrust
        motion[1] += forward*2.6*thrust
        motion[2] = forward*15.0*thrust + (0,-7.0*thrust)
        motion[3] = -forward*3.5*thrust
        motion[5] = forward*5.2*thrust
        motion[7] = forward*5.2*thrust
    elif clip == 'CastSpell':
        thrust = max(0,1-frame/11)
        motion[0] += forward*7.2*thrust + (0,3.4*thrust)
        motion[1] += forward*3.8*thrust + (0,3.0*thrust)
        motion[2] = -forward*8.0*thrust
        motion[3] = forward*6.7*thrust + (0,-3.0*thrust)
        motion[4] = -forward*6.0*thrust
        motion[6] = -forward*10.0*thrust
        motion[5] = forward*2.0*thrust
        motion[7] = forward*4.0*thrust
    elif clip == 'Special1':
        flourish = sin(pi*(frame+1)/16)
        motion[0,1] -= 2*flourish
        motion[2] = -lateral*5.0*flourish + (0,-8*flourish)
        motion[3] = lateral*5.0*flourish + (0,-9*flourish)
    return forward,motion

@lru_cache(None)
def ranger_atlas(clip):
    return Image.open(PROJECT / 'assets/isometric_character/2Archer' / f'{clip}.png').convert('RGBA')

@lru_cache(None)
def ranger_hip_track(facing, clip, hip_y):
    band = np.asarray(ranger_atlas(clip).crop((0,facing*CELL+hip_y-2,CELL*FRAMES,facing*CELL+hip_y+3)),
                      dtype=np.int16)
    r,g,b,a = np.moveaxis(band,2,0)
    warm = (a>=224)&(r>18)&(r>g+4)&(r>b+7)
    centers = []
    for frame in range(FRAMES):
        waist = warm[:,frame*CELL+48:frame*CELL+79].sum(axis=0)
        area = np.convolve(waist,np.ones(7,dtype=int),mode='same')
        centers.append(48+np.argmax(area-abs(np.arange(len(area))-16)*.40))
    order = np.asarray(centers)
    weighted = sum(w*np.roll(order,d) for d,w in ((-2,1),(-1,2),(0,3),(1,2),(2,1)))
    return np.rint(weighted/9).astype(int)

def ranger_gait(facing, clip, frame):
    # All four locomotion clips share Chita's authored Ranger contact, passing,
    # and lift poses. Keep those pixels at their original coordinates.
    image = ranger_atlas(clip).crop((frame*CELL,facing*CELL,(frame+1)*CELL,(facing+1)*CELL))
    original = np.asarray(image).astype(np.int16)
    r,g,b,a = np.moveaxis(original,2,0)
    xgrid = np.arange(CELL)[None,:]
    ygrid = np.arange(CELL)[:,None]
    warm = (a>=224)&(r>18)&(r>g+4)&(r>b+7)
    hip_y = (73,74,74,72,70,69,74,73)[facing]
    pelvis_x = int(ranger_hip_track(facing,clip,hip_y)[frame])
    section = (ygrid>=hip_y-2)&(abs(xgrid-pelvis_x)<29)

    # Keep the warm limb pixels connected to the hips. A one-pixel bow or string
    # usually has no 2x2 body core, and isolated hand pixels never seed the mask.
    mask = warm & section
    core = mask.copy()
    for dy,dx in ((1,0),(0,1),(-1,0),(0,-1)):
        core &= np.roll(mask,(dy,dx),(0,1)) | np.roll(mask,(dx,-dy),(0,1))
    reached = core & (ygrid<=hip_y+2) & (abs(xgrid-pelvis_x)<8)
    if not reached.any():
        reached = mask & (ygrid<=hip_y+3) & (abs(xgrid-pelvis_x)<9)
    while True:
        surround = reached.copy()
        for dy,dx in ((1,0),(0,1),(-1,0),(0,-1),(1,1),(-1,1),(1,-1),(-1,-1)):
            surround |= np.roll(reached,(dy,dx),(0,1))
        expanded = surround & core
        if np.array_equal(expanded,reached):
            break
        reached = expanded
    limb = reached.copy()
    for dy,dx in ((1,0),(0,1),(-1,0),(0,-1)):
        limb |= np.roll(reached,(dy,dx),(0,1)) & mask
    limb &= (ygrid>=hip_y)

    cast_shadow = (a>0)&(a<255)&(r+g+b<15)&(ygrid>=hip_y+5)&(abs(xgrid-pelvis_x)<24)
    area = sum(np.roll(cast_shadow,(dy,dx),(0,1)).astype(np.uint8)
               for dy in (-1,0,1) for dx in (-1,0,1))
    cast_shadow &= area>=6
    ground = np.zeros_like(original,dtype=np.uint8)
    ground[cast_shadow,3] = (a[cast_shadow]*.78).astype(np.uint8)

    # Deflect the stock bare-leg tones into dark trousers and brown boot leather.
    shade = .46*r+.34*g+.20*b
    trousers = limb & (r>=84) & (g>=37)
    boots = limb & ~trousers
    ground[trousers,:3] = np.column_stack((shade[trousers]*.43+16, shade[trousers]*.41+16,
                                           shade[trousers]*.45+19)).astype(np.uint8)
    ground[boots,:3] = np.column_stack((shade[boots]*.85+13, shade[boots]*.67+9,
                                       shade[boots]*.51+9)).astype(np.uint8)
    ground[limb,3] = a[limb].astype(np.uint8)
    return Image.fromarray(ground), np.array((pelvis_x,hip_y+1))

def draw_skull(draw, facing, center):
    x,y = map(round,center)
    view = 'front' if facing == 1 else ('rear' if facing in (4,5,6) else 'side')
    for dy,line in enumerate(SKULL[view]):
        if facing in (2,3,4):
            line = line[::-1]
        for dx,tone in enumerate(line):
            if tone != ' ':
                draw.point((x+dx-4,y+dy-4),fill=BONE[tone])

def draw_dagger(draw, at, direction, flash):
    dx,dy = direction/np.linalg.norm(direction)
    x,y = at
    hilt = (x+dx*2,y+dy*2)
    tip = (x+dx*10,y+dy*10)
    draw.line((x-dx*1.5,y-dy*1.5,*hilt),fill='#6d543e',width=2)
    draw.line((hilt[0]-dy*1.5,hilt[1]+dx*1.5,hilt[0]+dy*1.5,hilt[1]-dx*1.5),fill='#9f927f')
    draw.polygon([tip,(hilt[0]+dy,hilt[1]-dx),(hilt[0]-dy,hilt[1]+dx)],fill='#728aa1')
    draw.line((*hilt,*tip),fill='#b4cbd7')
    if flash:
        tx,ty = map(round,tip)
        draw.line((tx-dx*4,ty-dy*4,tx+dx*6,ty+dy*6),fill=(188,214,240,216))
        draw.line((tx-2,ty,tx+2,ty),fill='#dce9f2')
        draw.line((tx,ty-2,tx,ty+2),fill='#f5f3ea')

def draw_pose(facing,clip,frame):
    source,joints = costume(facing)
    forward,offsets = pose_offsets(facing,clip,frame)
    grid,weights,shadow = motion_fields(facing)
    shade = np.asarray(source).copy()
    shade[~shadow] = 0
    shade[shadow,3] = (shade[shadow,3]*.74).astype(np.uint8)
    subject = np.asarray(source).copy()
    subject[shadow] = 0
    if clip in WALK_CLIPS:
        ground,hip = ranger_gait(facing,clip,frame)
        height,width = subject.shape[:2]
        yy,xx = np.mgrid[:height,:width]
        belt_x,belt_y = joints[1]
        sleeve = np.zeros_like(shadow)
        for hand_x,hand_y in joints[2:4]:
            if abs(hand_x-belt_x)>7:
                sleeve |= ((xx-hand_x)**2+(yy-hand_y)**2)<34
        subject[(yy>belt_y+3)&~sleeve] = 0
        correction = hip-joints[1]-offsets[1]
        offsets[0] += correction*(1,.69)
        offsets[1:4] += correction
    else:
        ground = Image.fromarray(shade)
    field = np.sum(weights[:,:,:,None]*offsets,axis=2)
    uv = np.rint(grid-field).astype(int).clip(0,CELL-1)
    shifted = subject[uv[:,:,1],uv[:,:,0]]
    raw = ground
    raw.alpha_composite(Image.fromarray(shifted))

    skull = joints[0]+offsets[0]
    pl = ImageDraw.Draw(raw)
    # Cobalt smoke under the skull joins the collar and unreadable neck gap.
    x,y = map(round,skull)
    neck = joints[0] + offsets[1] + (0,10)
    collar = (round(neck[0]), max(y+5,round(neck[1])))
    pl.line((x,y+2,x-1,y+4,*collar),fill='#304b80',width=2)
    pl.point((x-1,y+4),fill='#567cbc')
    draw_skull(pl,facing,skull)

    weapon = Image.new('RGBA',(CELL,CELL))
    flash = clip == 'Melee' and frame in (2,3,4,5)
    heading = forward if flash or clip=='Melee' and 2<=frame<=7 else joints[-1]-joints[2]
    draw_dagger(ImageDraw.Draw(weapon),joints[2]+offsets[2],heading,flash)
    if facing in (4,5) and clip not in ('Melee',):
        weapon.alpha_composite(raw)
        return weapon
    raw.alpha_composite(weapon)
    return raw

def build(clips=CLIPS):
    OUTPUT.mkdir(exist_ok=True)
    for clip in clips:
        atlas = Image.new('RGBA',(CELL*FRAMES,CELL*8))
        for facing in range(8):
            for frame in range(FRAMES):
                atlas.paste(draw_pose(facing,clip,frame),(frame*CELL,facing*CELL))
        atlas.save(OUTPUT/f'{clip}.png',optimize=True)
    if 'Idle' in clips:
        build_portrait()

def build_portrait():
    pose = draw_pose(0,'Idle',0)
    pose = pose.crop(pose.getbbox())
    scale = min(115/pose.width, 120/pose.height)
    pose = pose.resize((round(pose.width*scale),round(pose.height*scale)),Image.Resampling.NEAREST)
    icon = Image.new('RGBA',(144,144))
    icon.alpha_composite(pose,((144-pose.width)//2,134-pose.height))
    icon.save(OUTPUT/'Portrait.png')

if __name__ == '__main__':
    clips = tuple(clip for clip in argv[1:] if clip != 'Portrait')
    if clips or len(argv)==1:
        build(clips or CLIPS)
    if 'Portrait' in argv[1:]:
        build_portrait()
