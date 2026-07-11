# IA Trading

Landing page premium **IA Trading** — le trading augmenté par l'intelligence artificielle.

Signaux en temps réel, analyse prédictive, gestion du risque automatisée et backtesting.

## Fichiers
- `index.html` — le site complet, autonome (prêt à ouvrir dans un navigateur ou à publier via GitHub Pages)

## Voir le site
Ouvre `index.html` dans ton navigateur, ou active GitHub Pages (branche `main`, dossier racine).

## À personnaliser
- Email de contact : `contact@iatrading.app`
- Lien Telegram : `https://t.me/`
- Chiffres de performance et témoignage

## Indicateur TradingView — `ict_irl_erl_fvg.pine`

Indicateur **Pine Script v6** qui automatise une stratégie ICT complète.

### Concepts imbriqués
- **IRL → ERL** : le FVG (liquidité interne) sert de point d'entrée, les swings High/Low (liquidité externe) servent de cibles / TP2.
- **FVG** : Fair Value Gaps détectés en **H4** (biais) et en **M15** (déclencheur).
- **50% Premium / Discount** : equilibrium du dealing range → long en Discount, short en Premium.
- **Killzone** : l'entrée M15 n'est validée qu'à l'intérieur d'une killzone (London / NY AM / NY PM / Asian, configurables).

### Logique de trade automatisée
1. Détection d'un **FVG H4** dans le sens du biais (structure BOS ou EMA HTF).
2. Attente du **tap** de la zone H4 (le prix revient dans le FVG).
3. Recherche d'un **FVG M15** dans le même sens, **en Killzone**, du bon côté du 50%.
4. Niveau d'**entrée limit au bord du FVG M15** (haut du gap pour un long, bas pour un short), **SL juste sous/au-dessus du FVG**, **RR 1:2** (paramétrable).
5. **TP1 à 1R** → matérialisé pour passer en **Break Even + 25%** de partiel.
6. **TP2 à 2R** (liquidité externe / ERL).

L'indicateur trace les zones FVG, le dealing range + 50%, les killzones ombrées, les niveaux Entrée/SL/TP1/TP2, un tableau de bord (biais, zone H4, premium/discount, killzone) et déclenche des **alertes** (`ICT LONG` / `ICT SHORT`).

### Utilisation
1. Sur TradingView, ouvre l'éditeur Pine, colle le contenu de `ict_irl_erl_fvg.pine`, clique **Add to chart**.
2. Applique l'indicateur sur un graphique **M15** (le H4 est récupéré automatiquement).
3. Configure ta killzone (fuseau horaire + plages), le biais, le RR et les buffers de stop.
4. Crée une alerte sur les conditions `ICT LONG` / `ICT SHORT` pour être notifié des setups.

> Note anti-repaint : les FVG H4 ne sont validés que sur bougie H4 clôturée, et les signaux sur bougie M15 clôturée.

### Alertes Telegram (FVG M15 en Killzone)
L'indicateur émet une alerte **`FVG M15 en Killzone`** au moment exact où un FVG M15 se trace pendant une killzone (message prêt avec direction, actif, prix, biais H4, état de la zone).

TradingView n'envoie pas vers Telegram directement : un petit relais webhook est fourni (`telegram_relay.py`).

1. Crée un bot avec **@BotFather** (`/newbot`) → récupère le **TOKEN**.
2. Récupère ton **chat_id** via `https://api.telegram.org/bot<TOKEN>/getUpdates`.
3. `pip install -r requirements.txt`, définis `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `WEBHOOK_SECRET`, puis `python telegram_relay.py`.
4. Sur TradingView (plan **Pro** requis pour les webhooks), alerte `FVG M15 en Killzone` → **Webhook URL** = `http://TON_IP:PORT/webhook?secret=...`.

> Sans TradingView Pro : l'EA MT5 peut envoyer les messages Telegram directement (WebRequest), sans serveur — à activer sur demande.

## Stratégie backtestable — `ict_irl_erl_fvg_strategy.pine`

Version **`strategy()`** de la même logique, avec exécution réaliste :

- **Entrée par ordre LIMIT au bord du FVG M15** (bord proximal) :
  - Long : limit au **haut** du FVG, SL juste **sous** le FVG.
  - Short : limit au **bas** du FVG, SL juste **au-dessus** du FVG.
- **TP1 à 1R** → prise partielle 25% + passage automatique en **Break Even**.
- **TP2 à 2R** sur le reste.
- **Sizing par risque** : `Risque par trade (%)` → la taille est calculée pour risquer X% du capital jusqu'au SL.
- **Expiration** de l'ordre limit non rempli après N bougies (annulation).
- Testable dans le **Strategy Tester** (winrate, drawdown, profit factor, prise partielle réelle).

### Automatisation broker (Vantage / Eightcap)
TradingView **n'envoie pas** automatiquement les ordres d'une stratégie Pine à un broker. Deux voies :

1. **Manuel assisté** : connecter Vantage / Eightcap à TradingView (panneau *Trading*) et exécuter à la main sur signal/alerte. Simple, aucun intermédiaire.
2. **Auto par webhook** : créer une alerte *« alert() function calls only »* ; la stratégie émet déjà un **payload JSON** (`action`, `symbol`, `order`, `price`, `sl`, `tp`) prêt à être envoyé à un pont webhook (bridge) qui relaie vers l'API du broker. Nécessite un service intermédiaire (bridge) car ni Vantage ni Eightcap n'exécutent nativement un webhook TradingView.

## Exécution automatique MetaTrader 5 — `ICT_IRL_ERL_FVG_EA.mq5`

**Expert Advisor (EA) MQL5** qui exécute la stratégie **automatiquement sur MT5** : il analyse tout seul (FVG H4, tap, FVG M15, Killzone, Premium/Discount), et **place l'ordre limit + SL + TP** dès que toutes les conditions sont confirmées, puis gère **BE + prise partielle 25% à 1R** et vise **2R**.

### Ce que fait l'EA
- Biais H4 (structure BOS ou EMA), zone FVG H4 + détection du tap.
- FVG M15 dans le sens du biais, filtre Killzone (heures serveur) + Premium/Discount.
- **Ordre LIMIT au bord du FVG**, SL juste sous/au-dessus du FVG, **sizing par risque (% du solde)**.
- À **1R** : prise partielle 25% + passage **Break Even** automatique. Sortie du reste à **2R**.
- Un seul trade à la fois (par `Magic number`), garde-fou spread, expiration de l'ordre limit.

### Installation
1. Ouvre **MetaEditor** (bouton dans MT5, ou touche F4).
2. `Fichier → Nouveau → Expert Advisor`, ou copie `ICT_IRL_ERL_FVG_EA.mq5` dans `MQL5/Experts/`.
3. Colle le code → **Compiler** (F7). Zéro erreur attendue.
4. Dans MT5, glisse l'EA sur un graphique **M15** de ta paire.
5. Coche **« Autoriser l'Algo Trading »** (bouton *Algo Trading* en haut) et dans les propriétés de l'EA.

### Backtest (règle aussi la demande de backtest 6 mois)
- Dans MT5 : `Affichage → Testeur de stratégie` (Ctrl+R) → choisis l'EA, le symbole, **M15**, la période (6 mois), modèle *« Chaque tick basé sur les ticks réels »*.
- Résultats natifs : profit net, drawdown, profit factor, courbe d'equity, détail des trades.

### Pour tourner 24/7
- L'EA doit rester actif : utilise un **VPS** (Eightcap et Vantage en proposent souvent un gratuit) pour garder MT5 ouvert en permanence.

### Réglages à vérifier en priorité
- **Killzones** : les heures sont en **heure SERVEUR du broker** (souvent GMT+2/+3). Vérifie l'heure de ton serveur MT5 et ajuste `London/NY` en conséquence.
- **Risque** : `Risque par trade (%)` du solde (défaut 1%).
- Commence avec `Trading activé = false` pour observer, puis passe en **compte DÉMO** avant tout compte réel.

> ⚠️ Cet EA place de vrais ordres. **Teste impérativement sur compte démo** d'abord. Les résultats de backtest ne garantissent pas les performances futures. Le trading comporte un risque de perte en capital.

> Avertissement : le trading comporte un risque de perte en capital. IA Trading fournit des outils d'aide à la décision et ne constitue pas un conseil en investissement.
