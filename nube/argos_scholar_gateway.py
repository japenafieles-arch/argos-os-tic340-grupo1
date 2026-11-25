#!/usr/bin/env python3
"""
ARGOS OS - Pasarela Académica en la Nube (HTTP -> HTTPS)
--------------------------------------------------------
Servicio multiusuario para ARGOS OS (Tecnológico Universitario Argos).
- Soporta múltiples usuarios simultáneos (ThreadingHTTPServer).
- Lee el puerto desde la variable de entorno PORT (por defecto 8080).
- Consulta Google Académico por HTTPS con respaldo automático a OpenAlex y Crossref.
- Caché en memoria (10 min) para respuestas instantáneas y protección anti-CAPTCHA.
- Devuelve texto plano compacto con Content-Length fijo para la pantalla VGA 80x25.
"""

import html
import json
import os
import re
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "0.0.0.0"
PORT = int(os.environ.get("PORT", "8080"))
MAX_RESULTS = 6
TIMEOUT_SCHOLAR = 5
TIMEOUT_API = 7
CACHE_TTL_SEG = 600
CACHE_MAX_ITEMS = 200

_cache = {}
_cache_lock = threading.Lock()


def crear_ssl_ctx():
    try:
        return ssl.create_default_context()
    except Exception:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx


SSL_CTX = crear_ssl_ctx()


def limpiar_texto(txt, max_len=260):
    if not txt:
        return ""
    txt = html.unescape(str(txt))
    txt = re.sub(r"<[^>]+>", " ", txt)
    reemplazos = {
        "\u2013": "-", "\u2014": "-", "\u2212": "-",
        "\u2018": "'", "\u2019": "'", "\u201c": '"', "\u201d": '"',
        "\u2026": "...", "\u00a0": " ", "\u200b": "", "\ufeff": "",
        "\r": " ", "\n": " ", "\t": " ",
    }
    for k, v in reemplazos.items():
        txt = txt.replace(k, v)
    permitidos = set("áéíóúñüÁÉÍÓÚÑÜ¿¡º°")
    out = []
    for ch in txt:
        code = ord(ch)
        if 32 <= code < 127 or ch in permitidos:
            out.append(ch)
        elif ch in "àâäãå": out.append("a")
        elif ch in "èêë": out.append("e")
        elif ch in "ìîï": out.append("i")
        elif ch in "òôöõ": out.append("o")
        elif ch in "ùû": out.append("u")
        elif ch in "ÀÂÄÃÅ": out.append("A")
        elif ch in "ÈÊË": out.append("E")
        elif ch in "ÌÎÏ": out.append("I")
        elif ch in "ÒÔÖÕ": out.append("O")
        elif ch in "ÙÛ": out.append("U")
        elif ch in "çÇ": out.append("c" if ch == "ç" else "C")
        else:
            out.append(" ")
    txt = re.sub(r"\s+", " ", "".join(out)).strip()
    if len(txt) > max_len:
        txt = txt[: max_len - 3].rstrip() + "..."
    return txt


def construir_apa(titulo, autores, anio, url):
    a = autores if autores else "Autor desconocido"
    y = anio if anio else "s.f."
    t = titulo if titulo else "Sin título"
    u = url if url else ""
    apa = f"{a} ({y}). {t}."
    if u:
        apa += f" {u}"
    return limpiar_texto(apa, 260)


def buscar_google_scholar(query, limit):
    q = urllib.parse.quote_plus(query)
    url = f"https://scholar.google.com/scholar?hl=es&as_sdt=0%2C5&q={q}"
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/124.0.0.0 Safari/537.36"
        ),
        "Accept-Language": "es-EC,es;q=0.9,en;q=0.8",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    }
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT_SCHOLAR, context=SSL_CTX) as resp:
        raw = resp.read().decode("utf-8", errors="replace")

    low = raw.lower()
    if "gs_captcha" in low or "unusual traffic" in low or "no soy un robot" in low:
        raise RuntimeError("Google Scholar solicitó CAPTCHA")

    bloques = raw.split('class="gs_ri"')
    resultados = []
    for blk in bloques[1:]:
        if len(resultados) >= limit:
            break
        blk = blk[:6000]
        m_title = re.search(r'<h3[^>]*class="gs_rt"[^>]*>(.*?)</h3>', blk, re.S)
        if not m_title:
            continue
        h3 = m_title.group(1)
        m_href = re.search(r'href="([^"]+)"', h3)
        link = html.unescape(m_href.group(1)) if m_href else ""
        h3_clean = re.sub(r'<span[^>]*class="gs_ct[^"]*"[^>]*>.*?</span>', "", h3, flags=re.S)
        titulo = limpiar_texto(h3_clean, 140)
        if not titulo:
            continue

        m_meta = re.search(r'<div[^>]*class="gs_a"[^>]*>(.*?)</div>', blk, re.S)
        meta = limpiar_texto(m_meta.group(1), 160) if m_meta else ""
        m_year = re.search(r"\b(19\d{2}|20\d{2})\b", meta)
        anio = m_year.group(1) if m_year else "s.f."
        autores = meta.split(" - ")[0].strip() if " - " in meta else meta
        autores = limpiar_texto(autores, 100)

        m_snip = re.search(r'<div[^>]*class="gs_rs"[^>]*>(.*?)</div>', blk, re.S)
        snippet = limpiar_texto(m_snip.group(1), 220) if m_snip else "Sin resumen disponible."

        m_cit = re.search(r'(?:Citado por|Cited by)\s+(\d+)', blk, re.I)
        citas = m_cit.group(1) if m_cit else "0"

        if not link:
            link = f"https://scholar.google.com/scholar?q={urllib.parse.quote_plus(titulo)}"

        resultados.append({
            "title": titulo,
            "authors": autores or "Autor no especificado",
            "year": anio,
            "cites": citas,
            "url": limpiar_texto(link, 140),
            "snippet": snippet,
            "apa": construir_apa(titulo, autores, anio, link),
        })

    if not resultados:
        raise RuntimeError("Sin resultados parseables en Google Scholar")
    return "Google Scholar", resultados


def reconstruir_abstract_openalex(inv_idx):
    if not isinstance(inv_idx, dict) or not inv_idx:
        return ""
    palabras = {}
    for palabra, posiciones in inv_idx.items():
        for pos in posiciones:
            if pos < 45:
                palabras[pos] = palabra
    if not palabras:
        return ""
    return " ".join(palabras[k] for k in sorted(palabras.keys()))


def buscar_openalex(query, limit):
    q = urllib.parse.quote_plus(query)
    url = f"https://api.openalex.org/works?search={q}&per-page={limit}&sort=relevance_score:desc"
    headers = {"User-Agent": "ARGOS-OS-Scholar/7.2 (mailto:argos@tecnologicoargos.edu.ec)"}
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT_API, context=SSL_CTX) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="replace"))

    resultados = []
    for w in data.get("results", [])[:limit]:
        titulo = limpiar_texto(w.get("display_name") or w.get("title") or "", 140)
        if not titulo:
            continue
        anio = str(w.get("publication_year") or "s.f.")
        citas = str(w.get("cited_by_count") or 0)

        auths = []
        for a in w.get("authorships", [])[:4]:
            name = (a.get("author") or {}).get("display_name")
            if name:
                auths.append(name)
        if len(w.get("authorships", [])) > 4:
            auths.append("et al.")
        autores = limpiar_texto(", ".join(auths), 100) or "Autor no especificado"

        link = w.get("doi") or ""
        if not link:
            loc = w.get("primary_location") or {}
            link = loc.get("landing_page_url") or ""
        if not link:
            link = f"https://scholar.google.com/scholar?q={urllib.parse.quote_plus(titulo)}"

        abs_txt = reconstruir_abstract_openalex(w.get("abstract_inverted_index"))
        venue = ((w.get("primary_location") or {}).get("source") or {}).get("display_name") or ""
        if abs_txt:
            snippet = limpiar_texto(abs_txt, 220)
        elif venue:
            snippet = limpiar_texto(f"Publicado en: {venue}.", 220)
        else:
            snippet = "Artículo indexado en índice académico abierto."

        resultados.append({
            "title": titulo,
            "authors": autores,
            "year": anio,
            "cites": citas,
            "url": limpiar_texto(link, 140),
            "snippet": snippet,
            "apa": construir_apa(titulo, autores, anio, link),
        })

    return "Google Scholar / OpenAlex", resultados


def buscar_crossref(query, limit):
    q = urllib.parse.quote_plus(query)
    url = f"https://api.crossref.org/works?query={q}&rows={limit}"
    headers = {"User-Agent": "ARGOS-OS-Scholar/7.2 (mailto:argos@tecnologicoargos.edu.ec)"}
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT_API, context=SSL_CTX) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="replace"))

    resultados = []
    items = (data.get("message") or {}).get("items", [])
    for it in items[:limit]:
        tit_list = it.get("title") or []
        titulo = limpiar_texto(tit_list[0] if tit_list else "", 140)
        if not titulo:
            continue
        anio = "s.f."
        for campo in ("published-print", "published-online", "created"):
            dp = (it.get(campo) or {}).get("date-parts")
            if dp and dp[0] and dp[0][0]:
                anio = str(dp[0][0])
                break
        citas = str(it.get("is-referenced-by-count") or 0)
        auths = []
        for a in it.get("author", [])[:4]:
            fam = a.get("family") or ""
            giv = a.get("given") or ""
            full = f"{giv} {fam}".strip()
            if full:
                auths.append(full)
        autores = limpiar_texto(", ".join(auths), 100) or "Autor no especificado"
        link = it.get("URL") or f"https://scholar.google.com/scholar?q={urllib.parse.quote_plus(titulo)}"
        pub = limpiar_texto(it.get("publisher") or "", 100)
        snippet = limpiar_texto(it.get("abstract") or (f"Editorial: {pub}." if pub else "Registro Crossref."), 220)

        resultados.append({
            "title": titulo,
            "authors": autores,
            "year": anio,
            "cites": citas,
            "url": limpiar_texto(link, 140),
            "snippet": snippet,
            "apa": construir_apa(titulo, autores, anio, link),
        })

    return "Google Scholar / Crossref", resultados


def buscar_academico(query, limit=MAX_RESULTS):
    key = (query.lower().strip(), limit)
    ahora = time.time()
    with _cache_lock:
        ent = _cache.get(key)
        if ent and (ahora - ent[0]) < CACHE_TTL_SEG:
            return ent[1], ent[2]

    for fn in (buscar_google_scholar, buscar_openalex, buscar_crossref):
        try:
            fuente, res = fn(query, limit)
            if res:
                with _cache_lock:
                    if len(_cache) >= CACHE_MAX_ITEMS:
                        _cache.clear()
                    _cache[key] = (ahora, fuente, res)
                return fuente, res
        except Exception:
            continue
    return "Sin conexión", []


def formatear_respuesta(fuente, resultados):
    lineas = [
        f"SOURCE: {limpiar_texto(fuente, 48)}",
        f"COUNT: {len(resultados)}",
    ]
    for r in resultados:
        lineas.append("---")
        lineas.append(f"TITLE: {limpiar_texto(r['title'], 140)}")
        lineas.append(f"AUTHORS: {limpiar_texto(r['authors'], 100)}")
        lineas.append(f"YEAR: {limpiar_texto(r['year'], 6)}")
        lineas.append(f"CITES: {limpiar_texto(r['cites'], 10)}")
        lineas.append(f"URL: {limpiar_texto(r['url'], 140)}")
        lineas.append(f"SNIPPET: {limpiar_texto(r['snippet'], 220)}")
        lineas.append(f"APA: {limpiar_texto(r['apa'], 260)}")
    lineas.append("END")
    return "\n".join(lineas) + "\n"


class ArgosScholarHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def enviar_texto(self, codigo, texto):
        data = texto.encode("utf-8", errors="replace")
        self.send_response(codigo)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)
        self.close_connection = True

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path in ("/", "/health"):
            self.enviar_texto(200, "OK ARGOS-SCHOLAR-GATEWAY v2.0 (Cloud Ready)\n")
            return

        if parsed.path == "/search":
            qs = urllib.parse.parse_qs(parsed.query)
            q = (qs.get("q") or [""])[0].strip()
            try:
                n = int((qs.get("n") or [str(MAX_RESULTS)])[0])
                n = max(1, min(n, MAX_RESULTS))
            except ValueError:
                n = MAX_RESULTS

            if not q:
                self.enviar_texto(400, "ERROR: falta parametro q\n")
                return

            print(f"[ARGOS-GW] '{q}' (n={n}) desde {self.client_address[0]}", flush=True)
            fuente, res = buscar_academico(q, n)
            print(f"[ARGOS-GW] -> {len(res)} resultado(s) via {fuente}", flush=True)
            self.enviar_texto(200, formatear_respuesta(fuente, res))
            return

        self.enviar_texto(404, "Rutas: /health  |  /search?q=tema\n")

    def log_message(self, fmt, *args):
        pass


def main():
    puerto = PORT
    if len(sys.argv) > 1:
        try:
            puerto = int(sys.argv[1])
        except ValueError:
            pass
    srv = ThreadingHTTPServer((HOST, puerto), ArgosScholarHandler)
    print("============================================================", flush=True)
    print("  ARGOS OS - Pasarela Académica v2.0 (Multiusuario + Caché)", flush=True)
    print(f"  Escuchando en http://0.0.0.0:{puerto}", flush=True)
    print("============================================================", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n[ARGOS-GW] Pasarela detenida.", flush=True)
        srv.server_close()


if __name__ == "__main__":
    main()

