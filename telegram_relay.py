#!/usr/bin/env python3
"""
Relais Webhook TradingView -> Telegram
======================================

TradingView ne peut pas envoyer un message directement à Telegram : ses alertes
POST vers une URL (webhook). Ce petit serveur reçoit ce POST et transmet le
contenu à ton bot Telegram via l'API Bot (sendMessage).

Flux :
    Alerte TradingView (webhook)  ->  ce serveur (/webhook)  ->  Telegram

------------------------------------------------------------------------------
PRÉREQUIS
------------------------------------------------------------------------------
1. Créer un bot : sur Telegram, parle à @BotFather -> /newbot -> récupère le TOKEN.
2. Récupérer ton chat_id :
   - Écris un message à ton bot (ou ajoute-le à ton canal/groupe).
   - Ouvre : https://api.telegram.org/bot<TOKEN>/getUpdates
   - Lis le champ "chat":{"id": ...}. C'est ton TELEGRAM_CHAT_ID.
     (Pour un canal, l'id ressemble à -1001234567890.)
3. Installer les dépendances :  pip install flask requests
4. Définir les variables d'environnement :
       export TELEGRAM_BOT_TOKEN="123456:ABC..."
       export TELEGRAM_CHAT_ID="123456789"
       export WEBHOOK_SECRET="un-secret-au-hasard"   # optionnel mais recommandé
5. Lancer :  python telegram_relay.py   (écoute sur le port 80, ou $PORT)

------------------------------------------------------------------------------
CÔTÉ TRADINGVIEW
------------------------------------------------------------------------------
- Le webhook nécessite un abonnement TradingView Pro (ou +).
- Sur l'alerte "FVG M15 en Killzone" -> onglet Notifications -> coche "Webhook URL"
  et mets :  http://TON_IP:PORT/webhook?secret=un-secret-au-hasard
- Le champ "Message" de l'alerte est envoyé tel quel à Telegram. Tu peux garder
  le message par défaut de l'indicateur (déjà mis en forme avec emoji).

------------------------------------------------------------------------------
ALTERNATIVE SANS SERVEUR
------------------------------------------------------------------------------
Si tu n'as pas TradingView Pro, l'Expert Advisor MT5 peut envoyer les messages
Telegram directement (WebRequest) — dis-le moi et je l'ajoute à l'EA.
"""

import os
import json
import requests
from flask import Flask, request, abort

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CHAT_ID   = os.environ.get("TELEGRAM_CHAT_ID", "")
SECRET    = os.environ.get("WEBHOOK_SECRET", "")   # "" = pas de vérification
PORT      = int(os.environ.get("PORT", "80"))

TELEGRAM_API = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"

app = Flask(__name__)


def send_to_telegram(text: str) -> tuple[bool, str]:
    """Envoie `text` au chat Telegram configuré."""
    if not BOT_TOKEN or not CHAT_ID:
        return False, "TELEGRAM_BOT_TOKEN ou TELEGRAM_CHAT_ID manquant."
    try:
        resp = requests.post(
            TELEGRAM_API,
            json={"chat_id": CHAT_ID, "text": text, "disable_web_page_preview": True},
            timeout=10,
        )
        ok = resp.ok and resp.json().get("ok", False)
        return ok, resp.text
    except Exception as exc:  # réseau, timeout, etc.
        return False, str(exc)


def extract_message(req) -> str:
    """Récupère le texte de l'alerte, que TradingView envoie en texte brut ou JSON."""
    raw = req.get_data(as_text=True).strip()
    if not raw:
        return ""
    # Si c'est du JSON, on tente d'en tirer un message lisible.
    try:
        data = json.loads(raw)
        if isinstance(data, dict):
            return data.get("message") or data.get("text") or json.dumps(data, ensure_ascii=False)
    except (ValueError, TypeError):
        pass
    return raw  # texte brut


@app.route("/webhook", methods=["POST"])
def webhook():
    # Vérification du secret (query string ?secret=... ou header X-Webhook-Secret)
    if SECRET:
        provided = request.args.get("secret") or request.headers.get("X-Webhook-Secret", "")
        if provided != SECRET:
            abort(403)

    message = extract_message(request)
    if not message:
        return {"status": "empty"}, 400

    ok, detail = send_to_telegram(message)
    if ok:
        return {"status": "sent"}, 200
    print(f"[telegram_relay] Échec envoi Telegram : {detail}")
    return {"status": "error", "detail": detail}, 502


@app.route("/health", methods=["GET"])
def health():
    configured = bool(BOT_TOKEN and CHAT_ID)
    return {"status": "ok", "telegram_configured": configured}, 200


if __name__ == "__main__":
    if not (BOT_TOKEN and CHAT_ID):
        print("ATTENTION : TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID non définis. "
              "Le serveur démarre mais n'enverra rien tant qu'ils ne sont pas configurés.")
    app.run(host="0.0.0.0", port=PORT)
