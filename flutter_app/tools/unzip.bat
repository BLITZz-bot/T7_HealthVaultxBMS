@echo off
python -c "import sys, zipfile, os; args = sys.argv[1:]; dest = '.'; zpath = None; i = 0; \
while i < len(args): \
    a = args[i]; \
    if a == '-d' and i+1 < len(args): dest = args[i+1]; i += 2; \
    elif a.startswith('-'): i += 1; \
    else: zpath = a; i += 1; \
os.makedirs(dest, exist_ok=True); \
zipfile.ZipFile(zpath, 'r').extractall(dest)" %*
