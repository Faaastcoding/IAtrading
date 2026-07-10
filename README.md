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

> Rappel : les résultats de backtest ne garantissent pas les performances futures. Le trading comporte un risque de perte en capital.

> Avertissement : le trading comporte un risque de perte en capital. IA Trading fournit des outils d'aide à la décision et ne constitue pas un conseil en investissement.
