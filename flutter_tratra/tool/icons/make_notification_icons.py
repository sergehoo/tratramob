"""Icônes de notification Tratra dérivées du logo officiel (aucun dessin approximatif) :
 - petite icône monochrome (barre d'état) : silhouette blanche du logo — visière + bloc, « T » et liseré évidés —
   dans la zone utile de 20 dp sur 24 dp, 5 densités ;
 - grande icône couleur : logo officiel sur disque blanc (lisible en thème clair comme sombre) ;
 - version verte de la petite icône pour l'aperçu du Back-Office."""
import sys
from pathlib import Path
from PIL import Image

src, android_res, web_public = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
logo = Image.open(src).convert("RGBA")
w, h = logo.size
px = logo.load()
mask = Image.new("L", (w, h), 0)
mp = mask.load()
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        whiteness = min(1.0, max(0.0, (min(r, g, b) - 140) / 115))   # blanc (T, liseré) -> transparent ; vert/jaune -> plein
        mp[x, y] = int(round(a * (1 - whiteness)))
bbox = mask.getbbox()
mask = mask.crop(bbox)
side = max(mask.size)
square = Image.new("L", (side, side), 0)
square.paste(mask, ((side - mask.width) // 2, (side - mask.height) // 2))
live = 20 / 24                                       # marge de 2 dp de chaque côté (gabarit Material)
canvas = int(round(side / live))
padded = Image.new("L", (canvas, canvas), 0)
padded.paste(square, ((canvas - side) // 2, (canvas - side) // 2))
for folder, size in {"drawable-mdpi": 24, "drawable-hdpi": 36, "drawable-xhdpi": 48, "drawable-xxhdpi": 72, "drawable-xxxhdpi": 96}.items():
    a = padded.resize((size, size), Image.Resampling.LANCZOS)
    icon = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    icon.putalpha(a)
    white = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    white.putalpha(a)
    out = android_res / folder
    out.mkdir(parents=True, exist_ok=True)
    white.save(out / "ic_stat_tratra.png", optimize=True)
# Grande icône : logo couleur sur disque blanc, 256 px (64 dp en xxxhdpi).
big = 256
large = Image.new("RGBA", (big, big), (0, 0, 0, 0))
disc = Image.new("L", (big * 4, big * 4), 0)
from PIL import ImageDraw
ImageDraw.Draw(disc).ellipse((0, 0, big * 4 - 1, big * 4 - 1), fill=255)
disc = disc.resize((big, big), Image.Resampling.LANCZOS)
white_disc = Image.new("RGBA", (big, big), (255, 255, 255, 255))
white_disc.putalpha(disc)
large.alpha_composite(white_disc)
crop = logo.crop(bbox)
scale = (big * 0.64) / max(crop.size)
crop = crop.resize((int(crop.width * scale), int(crop.height * scale)), Image.Resampling.LANCZOS)
large.alpha_composite(crop, ((big - crop.width) // 2, (big - crop.height) // 2))
(android_res / "drawable-nodpi").mkdir(parents=True, exist_ok=True)
large.save(android_res / "drawable-nodpi" / "tratra_notification_large.png", optimize=True)
# Aperçu du Back-Office : même silhouette, verte (couleur d'accent des notifications Tratra).
a = padded.resize((96, 96), Image.Resampling.LANCZOS)
green = Image.new("RGBA", (96, 96), (46, 139, 87, 255))
green.putalpha(a)
web_public.mkdir(parents=True, exist_ok=True)
green.save(web_public / "ic_stat_tratra.png", optimize=True)
large.save(web_public / "tratra_notification_large.png", optimize=True)
print("bbox", bbox, "ok")
