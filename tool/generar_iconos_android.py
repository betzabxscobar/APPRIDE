"""Genera el icono de la app para Android a partir de assets/images/LopoTipo.png.

Se escribe a mano en vez de usar flutter_launcher_icons para no sumar una
dependencia mas al proyecto: el logo cambia una vez al ano y esto es un rato de
Pillow. Si el logo cambia, se vuelve a correr:

    python tool/generar_iconos_android.py

Saca dos cosas por densidad:

  - ic_launcher.png: el icono de toda la vida, para Android 7 y anteriores. Ya
    viene con el fondo blanco y las esquinas redondeadas porque esos launchers
    dibujan el PNG tal cual.
  - ic_launcher_foreground.png: la capa de arriba del icono adaptativo (Android
    8+). Va sobre lienzo transparente y con aire de sobra en los bordes, que de
    eso se come el recorte que aplica cada launcher (circulo, rombo, squircle).
    El fondo lo pone mipmap-anydpi-v26/ic_launcher.xml.
"""

from pathlib import Path

from PIL import Image, ImageDraw

RAIZ = Path(__file__).resolve().parent.parent
LOGO = RAIZ / "assets" / "images" / "LopoTipo.png"
RES = RAIZ / "android" / "app" / "src" / "main" / "res"

# Los tamanos en px de cada densidad: el icono clasico es de 48dp y el lienzo
# del adaptativo de 108dp, multiplicados por el factor de la densidad.
DENSIDADES = {
    "mdpi": 1,
    "hdpi": 1.5,
    "xhdpi": 2,
    "xxhdpi": 3,
    "xxxhdpi": 4,
}

FONDO = (255, 255, 255, 255)  # El logo es azul, asi que la base va en blanco.

# Cuanto del lado ocupa el logo. En el clasico se ve el lienzo entero; en el
# adaptativo solo se ve un circulo de 66dp de los 108, y el logo es casi
# cuadrado: para que quepa entero ahi dentro tiene que ser bastante mas chico
# que el del icono clasico.
PROPORCION_CLASICO = 0.66
PROPORCION_ADAPTATIVO = 0.45
RADIO_ESQUINA = 0.22  # Del lado, solo para el icono clasico.


def logo_recortado() -> Image.Image:
    """El logo sin el margen transparente que trae el PNG original."""
    logo = Image.open(LOGO).convert("RGBA")
    return logo.crop(logo.split()[3].getbbox())


def centrado(lienzo: Image.Image, logo: Image.Image, proporcion: float) -> None:
    """Pega el logo en medio del lienzo, escalado a `proporcion` del lado."""
    lado = lienzo.width
    objetivo = round(lado * proporcion)
    escala = objetivo / max(logo.width, logo.height)
    medida = (max(1, round(logo.width * escala)), max(1, round(logo.height * escala)))
    encogido = logo.resize(medida, Image.LANCZOS)
    lienzo.alpha_composite(
        encogido,
        ((lado - encogido.width) // 2, (lado - encogido.height) // 2),
    )


def clasico(logo: Image.Image, lado: int) -> Image.Image:
    lienzo = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    mascara = Image.new("L", (lado, lado), 0)
    ImageDraw.Draw(mascara).rounded_rectangle(
        (0, 0, lado - 1, lado - 1), radius=round(lado * RADIO_ESQUINA), fill=255
    )
    lienzo.paste(Image.new("RGBA", (lado, lado), FONDO), mask=mascara)
    centrado(lienzo, logo, PROPORCION_CLASICO)
    return lienzo


def adaptativo(logo: Image.Image, lado: int) -> Image.Image:
    lienzo = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    centrado(lienzo, logo, PROPORCION_ADAPTATIVO)
    return lienzo


def main() -> None:
    logo = logo_recortado()
    for nombre, factor in DENSIDADES.items():
        carpeta = RES / f"mipmap-{nombre}"
        carpeta.mkdir(parents=True, exist_ok=True)

        clasico(logo, round(48 * factor)).save(carpeta / "ic_launcher.png")
        adaptativo(logo, round(108 * factor)).save(
            carpeta / "ic_launcher_foreground.png"
        )
        print(f"mipmap-{nombre}: {round(48 * factor)}px / {round(108 * factor)}px")


if __name__ == "__main__":
    main()
