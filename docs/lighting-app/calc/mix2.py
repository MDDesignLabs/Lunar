import importlib.util,sys
spec=importlib.util.spec_from_file_location("d","duv.py"); 
src=open("duv.py").read().split("print(")[0]
exec(src)
def mixxy(a,b,f):
    Xa,Ya,Za=tristim(*a,1-f); Xb,Yb,Zb=tristim(*b,f); X,Y,Z=Xa+Xb,Ya+Yb,Za+Zb; s=X+Y+Z; return X/s,Y/s
w=uv_to_xy(*planck_uv(4000)); d65=(0.3127,0.3290)
rows=[]
for i in range(1,200):
    T,d=cct_duv(*xy_to_uv(*mixxy(w,d65,i/200))); rows.append((T,-d))
for t in (4500,5000,5500,6000):
    r=min(rows,key=lambda r:abs(r[0]-t)); print(t,r)
