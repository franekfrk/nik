#!/usr/bin/env python3
"""Suggest nearby spellings, including adjacent transpositions; never execute input."""
import sys

def distance(a,b,limit):
    if abs(len(a)-len(b))>limit:return limit+1
    prevprev=None;prev=list(range(len(b)+1))
    for i,x in enumerate(a,1):
        row=[i]
        for j,y in enumerate(b,1):
            v=min(row[-1]+1,prev[j]+1,prev[j-1]+(x!=y))
            if prevprev is not None and j>1 and x==b[j-2] and a[i-2]==y:v=min(v,prevprev[j-2]+1)
            row.append(v)
        if min(row)>limit:return limit+1
        prevprev,prev=prev,row
    return prev[-1]

if __name__=='__main__':
    query=sys.argv[1]
    if 2<=len(query)<=80:
        limit=1 if len(query)<=4 else 2
        matches=[]
        for name in set(sys.stdin.read().splitlines()):
            d=distance(query,name,limit)
            if d<=limit:matches.append((d,name))
        for _,name in sorted(matches)[:3]:print(name)
