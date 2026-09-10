"""Crea en PayPal el producto y el plan de la cuota mensual del chofer.

Son 15 USD al mes. Existe porque hacerlo por los menus de PayPal es facil de
equivocar —y sobre todo, porque el plan hay que crearlo una vez por entorno: uno
de produccion NO existe en sandbox ni al reves, y ese es el tropiezo tipico—.

Se corre sin argumentos:

    python tool/crear_plan_paypal.py

y te pregunta las credenciales. El secreto se escribe a ciegas y no queda en el
historial del shell, que es justo lo que pasa si se pone en la linea de
comandos: PowerShell lo guarda en ConsoleHost_history.txt aunque el comando
falle. Tambien se pueden dar por variables de entorno (PAYPAL_CLIENT_ID,
PAYPAL_SECRET, PAYPAL_ENTORNO) si ya estan puestas.

Imprime el `P-...` que hay que poner en el secreto `PAYPAL_PLAN_ID` de Supabase.
Si el producto ya existe, se reutiliza y solo se crea el plan.

Ver docs/CUOTA.md.
"""

import base64
import getpass
import json
import os
import sys
import urllib.error
import urllib.request

ENTORNOS = {
    "sandbox": "https://api-m.sandbox.paypal.com",
    "produccion": "https://api-m.paypal.com",
}

MONTO = "15"
MONEDA = "USD"


def pedir(url: str, datos: dict | None, cabeceras: dict) -> dict:
    cuerpo = json.dumps(datos).encode() if datos is not None else None
    req = urllib.request.Request(url, data=cuerpo, headers=cabeceras, method="POST")
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        detalle = e.read().decode(errors="replace")
        raise SystemExit(f"PayPal respondio {e.code} en {url}:\n{detalle}")


def main() -> None:
    client = (os.environ.get("PAYPAL_CLIENT_ID") or "").strip()
    secreto = (os.environ.get("PAYPAL_SECRET") or "").strip()
    entorno = (os.environ.get("PAYPAL_ENTORNO") or "").strip()

    # Si no vienen del entorno, se preguntan. Es la via recomendada: escribir
    # el secreto en la linea de comandos lo deja en el historial del shell
    # —PowerShell lo guarda en ConsoleHost_history.txt aunque el comando falle—
    # y `getpass` no lo muestra ni lo guarda en ningun sitio.
    if not client:
        client = input("Client ID de PayPal (empieza por 'A'): ").strip()
    if not secreto:
        secreto = getpass.getpass("Secret de la MISMA app (no se vera al escribir): ").strip()
    if not entorno:
        entorno = input("Entorno [sandbox]: ").strip() or "sandbox"

    if not client or not secreto:
        raise SystemExit("Sin client id y secreto no se puede crear nada.")
    if entorno not in ENTORNOS:
        raise SystemExit(f"El entorno tiene que ser sandbox o produccion, no {entorno!r}")

    base = ENTORNOS[entorno]
    print(f"Entorno: {entorno} ({base})")

    # 1. Token. Si falla aqui, el par client id + secreto no vale para este
    #    entorno y no tiene sentido seguir.
    basico = base64.b64encode(f"{client}:{secreto}".encode()).decode()
    req = urllib.request.Request(
        f"{base}/v1/oauth2/token",
        data=b"grant_type=client_credentials",
        headers={
            "Authorization": f"Basic {basico}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as r:
            acceso = json.loads(r.read())["access_token"]
    except urllib.error.HTTPError as e:
        raise SystemExit(
            f"PayPal rechazo las credenciales ({e.code}).\n"
            f"Comprueba que son de la pestana {entorno} y de la misma app.\n"
            f"{e.read().decode(errors='replace')}"
        )
    print("Credenciales aceptadas.")

    cabeceras = {
        "Authorization": f"Bearer {acceso}",
        "Content-Type": "application/json",
    }

    # 2. El producto: lo que se vende. `SERVICE` porque es acceso a la app, no
    #    una cosa que se envie.
    producto = pedir(
        f"{base}/v1/catalogs/products",
        {
            "name": "Ride - acceso de chofer",
            "description": "Cuota mensual para recibir viajes en Ride",
            "type": "SERVICE",
            "category": "SOFTWARE",
        },
        {**cabeceras, "PayPal-Request-Id": "ride-producto-cuota"},
    )
    print(f"Producto: {producto['id']}")

    # 3. El plan: cuanto y cada cuanto.
    #    `total_cycles: 0` es "hasta que la den de baja"; con cualquier otro
    #    numero la suscripcion se acabaria sola a los N meses.
    plan = pedir(
        f"{base}/v1/billing/plans",
        {
            "product_id": producto["id"],
            "name": "Cuota mensual de chofer",
            "description": f"{MONTO} {MONEDA} al mes para recibir viajes",
            "status": "ACTIVE",
            "billing_cycles": [
                {
                    "frequency": {"interval_unit": "MONTH", "interval_count": 1},
                    "tenure_type": "REGULAR",
                    "sequence": 1,
                    "total_cycles": 0,
                    "pricing_scheme": {
                        "fixed_price": {"value": MONTO, "currency_code": MONEDA}
                    },
                }
            ],
            "payment_preferences": {
                "auto_bill_outstanding": True,
                "setup_fee_failure_action": "CONTINUE",
                # Tres intentos antes de suspender. PayPal avisa por webhook y
                # el chofer se queda sin recibir viajes cuando venza el mes que
                # ya pago, no antes.
                "payment_failure_threshold": 3,
            },
        },
        {**cabeceras, "PayPal-Request-Id": "ride-plan-cuota-mensual"},
    )

    print()
    print("Listo. Pon esto en el secreto PAYPAL_PLAN_ID de Supabase:")
    print()
    print(f"    {plan['id']}")
    print()
    print(f"({MONTO} {MONEDA}/mes, estado {plan['status']}, entorno {entorno})")


if __name__ == "__main__":
    sys.exit(main())
