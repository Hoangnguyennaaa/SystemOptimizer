import urllib.request
import re

url = 'https://github.com/Hoangnguyennaaa/SystemOptimizer/actions/runs/40182525085'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req) as resp:
        content = resp.read().decode('utf-8', errors='ignore')
        print(f"Content length: {len(content)}")
        # Look for step summary or logs embedded in JSON
        for line in content.splitlines():
            if any(k in line.lower() for k in ['clang', 'error:', 'failed', 'build failure', 'tweak.m']):
                print("LINE:", line[:150])
except Exception as e:
    print("Error:", e)
