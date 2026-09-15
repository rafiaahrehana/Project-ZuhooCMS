import io,re,glob,os,sys
BS=chr(92)
def norm(p): return p.replace(BS,'/')
def check(path):
    s=io.open(path,encoding='utf-8',newline='').read()
    i=0;n=len(s);stack=[];line=1
    pairs={'(':')','[':']','{':'}'};closing={')':'(',']':'[','}':'{'}
    while i<n:
        c=s[i]
        if c=='\n': line+=1;i+=1;continue
        if c=='/' and i+1<n and s[i+1]=='/':
            while i<n and s[i]!='\n': i+=1
            continue
        if c=='/' and i+1<n and s[i+1]=='*':
            i+=2
            while i+1<n and not (s[i]=='*' and s[i+1]=='/'):
                if s[i]=='\n': line+=1
                i+=1
            i+=2;continue
        if c in "'"+'"':
            triple=s[i:i+3] in ("'''",'"""');q=s[i:i+3] if triple else c;i+=len(q)
            while i<n:
                if s[i]==BS: i+=2;continue
                if s[i]=='\n': line+=1
                if s[i:i+len(q)]==q: i+=len(q);break
                if s[i]=='$' and i+1<n and s[i+1]=='{':
                    depth=1;i+=2
                    while i<n and depth:
                        if s[i]=='{':depth+=1
                        elif s[i]=='}':depth-=1
                        elif s[i]=='\n':line+=1
                        i+=1
                    continue
                i+=1
            continue
        if c in pairs: stack.append((c,line));i+=1;continue
        if c in closing:
            if not stack or stack[-1][0]!=closing[c]: return f'{path}: unexpected {c} line {line}'
            stack.pop();i+=1;continue
        i+=1
    if stack: return f'{path}: unclosed {stack[-1][0]} from line {stack[-1][1]}'
    return None
files=[norm(f) for f in glob.glob('lib/**/*.dart',recursive=True)+glob.glob('test/*.dart')]
bad=[r for r in (check(f) for f in files) if r]
for r in bad: print(r)
crlf=sum(1 for f in files if io.open(f,'rb').read().find(b'\r\n')>=0)
print(f'balance {len(files)} | {len(bad)} problems | CRLF {crlf}')
defs={}
for f in files:
    if not f.startswith('lib/'): continue
    s=io.open(f,encoding='utf-8',newline='').read()
    names=set(re.findall(r'^(?:abstract\s+)?(?:final\s+)?(?:class|enum|mixin|extension|typedef)\s+([A-Za-z_][A-Za-z0-9_]*)',s,re.M))
    names|=set(re.findall(r'^(?:final|const)\s+(?:[^=;]*?\s)?([a-zA-Z_][A-Za-z0-9_]*)\s*=',s,re.M))
    names|=set(re.findall(r'^[A-Za-z_][A-Za-z0-9_<>,?\s]*\s+([a-z_][A-Za-z0-9_]*)\s*\(',s,re.M))
    defs[f]=names
prob=0
for t in files:
    if not t.startswith('lib/'): continue
    s=io.open(t,encoding='utf-8',newline='').read()
    for m in re.finditer(r"^import\s+'([^']+)'(?:\s+show\s+([^;]+))?;",s,re.M):
        path,show=m.group(1),m.group(2)
        if path.startswith('package:') or path.startswith('dart:'): continue
        r=norm(os.path.normpath(os.path.join(os.path.dirname(t),path)))
        if r not in defs: print(f'MISSING FILE {path} <- {t}');prob+=1;continue
        syms=[y.strip() for y in show.split(',')] if show else sorted(defs[r])
        body=s.replace(m.group(0),'')
        if show:
            for x in syms:
                if x not in defs[r]: print(f'MISSING SYMBOL "{x}" in {path} <- {t}');prob+=1
        if 'bos_tokens' in path or 'app_theme' in path: continue
        if syms and not any(re.search(r'\b'+re.escape(x)+r'\b',body) for x in syms):
            print(f'UNUSED IMPORT {path} <- {t}');prob+=1
print('import problems:',prob)
