#!/usr/bin/env python3
"""
Testa endpoints REST de aprovacao (painel + inbox) via Cloudflare Worker.
Uso: python test_aprov_rest.py --apr 000120 --sc 000008 --fil 01

Requer: pip install requests (ou use curl mode)
"""
import argparse
import hashlib
import sys

try:
    import requests
except ImportError:
    requests = None

API = "https://gentle-dawn-f83d.ciclomed.workers.dev/rest03"
AUTH = ("admin", "v1v2v3v4")


def md5(s: str) -> str:
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def token_sc_view(fil: str, sc: str) -> str:
    return md5(f"CICLO2026SC#{fil.strip()}#{sc.strip()}#VIEW#V")


def token_pc_view(fil: str, pc: str) -> str:
    return md5(f"CICLO2026PC#{fil.strip()}#{pc.strip()}#VIEW#V")


def token_inbox(apr: str) -> str:
    return md5(f"CICLO2026INBOX#{apr.strip()}")


def get(path: str, params: dict) -> None:
    url = f"{API}/{path}"
    print(f"\n>>> GET {path}")
    print("    params:", params)
    if requests:
        r = requests.get(url, params=params, auth=AUTH, timeout=30)
        print(f"    status: {r.status_code}")
        text = r.text[:2000]
        print("    body:", text)
        if r.status_code >= 400:
            sys.exit(1)
    else:
        import urllib.parse
        q = urllib.parse.urlencode(params)
        print(f"    curl: curl -u admin:v1v2v3v4 '{url}?{q}'")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--apr", default="000120", help="Codigo aprovador AK_USER")
    p.add_argument("--sc", default="", help="Numero SC para testar WSSCPAINEL")
    p.add_argument("--pc", default="", help="Numero PC para testar WSPCPAINEL")
    p.add_argument("--fil", default="01", help="Filial")
    p.add_argument("--status", default="P", choices=["P", "A", "R", "ALL"])
    args = p.parse_args()

    t_inbox = token_inbox(args.apr)
    print(f"Token inbox apr={args.apr}: {t_inbox}")

    get("WSAPROVINBOX", {
        "apr": args.apr,
        "t": t_inbox,
        "tipo": "ALL",
        "status": args.status,
    })

    if args.sc:
        t = token_sc_view(args.fil, args.sc)
        print(f"Token SC VIEW: {t}")
        get("WSSCPAINEL", {"sc": args.sc, "fil": args.fil, "token": t})

    if args.pc:
        t = token_pc_view(args.fil, args.pc)
        print(f"Token PC VIEW: {t}")
        get("WSPCPAINEL", {"pc": args.pc, "fil": args.fil, "token": t})

    print("\nOK - testes disparados (verifique status/body acima).")


if __name__ == "__main__":
    main()
