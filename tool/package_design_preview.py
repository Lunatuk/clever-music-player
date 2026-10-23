"""Package actual Flutter preview renders into a self-contained offline gallery.

PowerShell:
  $env:CMP_EXPORT_DESIGN_PREVIEW = 'dist/clever-music-player-core-62-design-preview'
  flutter test test/design_preview_test.dart
  python tool/package_design_preview.py $env:CMP_EXPORT_DESIGN_PREVIEW

Uses only the standard library; does not modify the rendered PNGs.
"""

import argparse
import base64
import hashlib
import json
import struct
from pathlib import Path


def package(directory: Path) -> dict:
    images, manifest = {}, {}
    for variant in ("dark", "light"):
        for device in ("phone", "desktop"):
            for page in ("home", "library", "player", "queue"):
                name = f"{variant}-{device}-{page}"
                data = (directory / f"{name}.png").read_bytes()
                assert data[:8] == b"\x89PNG\r\n\x1a\n", name
                width, height = struct.unpack(">II", data[16:24])
                assert (width, height) == (
                    (585, 1266) if device == "phone" else (1920, 1200)
                ), name
                images[name] = "data:image/png;base64," + base64.b64encode(data).decode()
                manifest[f"{name}.png"] = {
                    "width": width,
                    "height": height,
                    "bytes": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                }
    html = TEMPLATE.replace("__IMAGES__", json.dumps(images, separators=(",", ":")))
    (directory / "index.html").write_text(html, encoding="utf-8")
    report = {"renderer": "Flutter widget test, Segoe UI on Windows",
              "syntheticData": True, "externalRequests": False, "images": manifest}
    (directory / "renders.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    return {"images": len(images), "htmlBytes": len(html.encode("utf-8"))}


TEMPLATE = """<!doctype html>
<html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Clever Music Player — компоновка и оформление</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#e9e6de;color:#282e29;font:16px/1.5 system-ui,sans-serif}
main{max-width:1500px;margin:auto;padding:32px 24px}h1{font-size:clamp(25px,4vw,38px);line-height:1.15;margin:0 0 14px}
p{max-width:850px;margin:8px 0;color:#515b53}nav{display:flex;flex-wrap:wrap;gap:18px;margin:24px 0}
fieldset{border:0;padding:0;margin:0}legend{font-size:12px;color:#515b53;margin-bottom:6px}
button{font:inherit;border:1px solid #8d968c;background:transparent;color:inherit;border-radius:12px;padding:8px 14px;cursor:pointer}
button[aria-pressed=true]{background:#293d32;color:#fff;border-color:#293d32}button:focus-visible{outline:3px solid #456b9a;outline-offset:3px}
.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}.card{min-width:0}.card h2{font-size:20px;margin:0}
.card p{font-size:13px;min-height:42px}img{display:block;width:100%;border-radius:16px;box-shadow:0 10px 25px #242d2818}
.image{border:0;background:transparent;padding:0;width:100%;text-align:initial;display:block}
.desktop{grid-template-columns:1fr}.desktop .card{padding:16px;background:#f5f1e8;border-radius:18px}
footer{font-size:13px;margin-top:24px;color:#515b53}dialog{border:0;border-radius:16px;padding:12px;max-width:96vw;max-height:96vh;background:#e9e6de}
dialog::backdrop{background:#101713b3}dialog img{width:auto;max-width:90vw;max-height:84vh;object-fit:contain;box-shadow:none}dialog button{margin-bottom:10px}
@media(max-width:800px){.grid{grid-template-columns:1fr}.card{max-width:500px;margin:auto;width:100%}.desktop .card{max-width:none}main{padding:24px 16px}}
</style>
<main><h1>Clever Music Player<br>Компоновка и оформление</h1>
<p>По референсам пользователя: мобильное приложение и desktop Яндекс Музыки периода декабря 2023 — первой половины 2025 года. Взята компоновка; музыка, обложки и бренд здесь вымышленные.</p>
<p>Здесь — настоящие снимки Flutter-макетов. Интерактивное демо находится в APK62: «О версии» → «Варианты дизайна». Оно не запускает музыку и не меняет медиатеку.</p>
<nav aria-label="Параметры просмотра">
<fieldset><legend>Устройство</legend><button data-device="phone" aria-pressed="true">Телефон</button> <button data-device="desktop" aria-pressed="false">Компьютер</button></fieldset>
<fieldset><legend>Экран</legend><button data-page="home" aria-pressed="true">Главная</button> <button data-page="library" aria-pressed="false">Коллекция</button> <button data-page="player" aria-pressed="false">Плеер</button> <button data-page="queue" aria-pressed="false">Очередь</button></fieldset>
</nav><section class="grid" aria-live="polite" aria-label="Две темы одного оформления"></section>
<footer>Нажми на снимок, чтобы увеличить. Галерея работает без интернета. Обложки нарисованы для демо; коллекция пользователя не используется. В APK доступны тема, свой акцентный цвет, анимации, плотность строк и скругление обложек. Параметры сохраняются; новые экраны пока работают с демо-данными.</footer>
</main><dialog><button id="close">Закрыть</button><img alt="Увеличенный макет"></dialog>
<script>
const images=__IMAGES__;
const variants=[['dark','Тёмная тема','Главная с Волной, коллекция, очередь и плеер.'],['light','Светлая тема','Та же компоновка на общей системе параметров оформления.']];
const pages={home:'Главная',library:'Коллекция',player:'Плеер',queue:'Очередь'};
let device='phone',page='home';const grid=document.querySelector('.grid'),dialog=document.querySelector('dialog');
function render(){grid.replaceChildren();grid.classList.toggle('desktop',device==='desktop');for(const [code,title,description] of variants){
const card=document.createElement('article');card.className='card';const heading=document.createElement('h2');heading.textContent=title;
const text=document.createElement('p');text.textContent=description;const button=document.createElement('button');button.className='image';
button.setAttribute('aria-label','Увеличить '+title+', '+pages[page]);const img=document.createElement('img');img.src=images[`${code}-${device}-${page}`];img.alt=title+' — '+pages[page];
button.append(img);button.onclick=()=>{const large=dialog.querySelector('img');large.src=img.src;large.alt=img.alt;dialog.showModal()};card.append(heading,text,button);grid.append(card)}
document.querySelectorAll('[data-device]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.device===device));
document.querySelectorAll('[data-page]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.page===page));}
document.querySelectorAll('[data-device]').forEach(b=>b.onclick=()=>{device=b.dataset.device;render()});
document.querySelectorAll('[data-page]').forEach(b=>b.onclick=()=>{page=b.dataset.page;render()});document.querySelector('#close').onclick=()=>dialog.close();render();
</script></html>"""


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    print(json.dumps(package(args.directory)))
