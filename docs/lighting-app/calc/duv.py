import math
def planck_uv(T):  # Krystek 1985, valid 1000-15000K, CIE1960 uv
    u=(0.860117757+1.54118254e-4*T+1.28641212e-7*T*T)/(1+8.42420235e-4*T+7.08145163e-7*T*T)
    v=(0.317398726+4.22806245e-5*T+4.20481691e-8*T*T)/(1-2.89741816e-5*T+1.61456053e-7*T*T)
    return u,v
def xy_to_uv(x,y):
    d=-2*x+12*y+3; return 4*x/d, 6*y/d
def uv_to_xy(u,v):
    d=2*u-8*v+4; return 3*u/d, 2*v/d
def daylight_xy(T):
    if T<=7000: x=-4.6070e9/T**3+2.9678e6/T**2+0.09911e3/T+0.244063
    else: x=-2.0064e9/T**3+1.9018e6/T**2+0.24748e3/T+0.237040
    y=-3*x*x+2.870*x-0.275; return x,y
def cct_duv(u,v):
    best=None
    for T in range(1500,20001,5):
        pu,pv=planck_uv(T); d=math.hypot(u-pu,v-pv)
        if best is None or d<best[0]: best=(d,T,pu,pv)
    d,T,pu,pv=best
    # sign: above locus (greater v) positive
    pu2,pv2=planck_uv(T+5); tx,ty=pu2-pu,pv2-pv
    cross=tx*(v-pv)-ty*(u-pu)
    return T, (d if cross>0 else -d)
def tristim(x,y,Y=1.0): return x*Y/y, Y, (1-x-y)*Y/y
print("Govee EPREL x,y=0.313,0.337 ->", cct_duv(*xy_to_uv(0.313,0.337)))
print("D65 0.3127,0.3290 ->", cct_duv(*xy_to_uv(0.3127,0.3290)))
for T in (4000,4500,5000,5500,6000,6500):
    print("daylight",T,"->",cct_duv(*xy_to_uv(*daylight_xy(T))))
# mixing two planckian whites
def mix(Tw,Tc,frac_c):
    xw,yw=uv_to_xy(*planck_uv(Tw)); xc,yc=uv_to_xy(*planck_uv(Tc))
    Xw,Yw,Zw=tristim(xw,yw,1-frac_c); Xc,Yc,Zc=tristim(xc,yc,frac_c)
    X,Y,Z=Xw+Xc,Yw+Yc,Zw+Zc; s=X+Y+Z; return X/s,Y/s
for Tw in (2700,3000,4000):
    worst=0;rows=[]
    for i in range(1,100):
        x,y=mix(Tw,6500,i/100); T,d=cct_duv(*xy_to_uv(x,y))
        if 3990<=T<=6510: rows.append((T,d))
    # report duv near 4000,5000,6000
    for tgt in (4000,5000,6000):
        r=min(rows,key=lambda r:abs(r[0]-tgt)) if rows else None
        print(f"mix {Tw}K+6500K at ~{tgt}K: CCT {r[0]} Duv {r[1]:+.4f}")
