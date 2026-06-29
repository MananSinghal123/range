#!/usr/bin/env bash
#
# warmup-oracle.sh — make the MUSD/BTC pool able to serve a 300s TWAP.
#
# The pool's oracle starts with observationCardinality = 1, so the swap inside a
# rebalance overwrites the single observation and the post-swap observe([300,0])
# reverts "OLD". This script:
#   1) increaseObservationCardinalityNext  → reserve oracle slots
#   2) approve the router for tiny warm-up swaps
#   3) trade #1                            → write the first real observation
#      ...wait > 300s so it ages past the TWAP window...
#   4) trade #2                            → leaves a >300s-old observation retained
# then verifies observe([300,0]) succeeds.
#
# Signing: exports PRIVATE_KEY (e.g. `source .env`) uses --private-key; otherwise it
# falls back to a cast keystore named by ACCOUNT (default: mezo-keeper).
#
# Usage:
#   bash keeper-bot/warmup-oracle.sh
#   ACCOUNT=mykeystore bash keeper-bot/warmup-oracle.sh
#   WAIT_SECONDS=330 bash keeper-bot/warmup-oracle.sh

set -euo pipefail

# ─── Config (override via env) ───────────────────────────────────────────────
RPC="${RPC:-https://rpc.test.mezo.org}"
ACCOUNT="${ACCOUNT:-mezo-keeper}"
POOL="${POOL:-0x026dB82AC7ABf60Bf1a81317c9DbD63702B85850}"
ROUTER="${ROUTER:-0x3112908bB72ce9c26a321Eeb22EC8e051F3b6E6a}"
MUSD="${MUSD:-0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503}"   # token0
BTC="${BTC:-0x7b7C000000000000000000000000000000000000}"     # token1
ME="${ME:-0xe4F4c768d628074C8a975126D517a60A03848f69}"        # swap recipient

TICK_SPACING="${TICK_SPACING:-50}"
TARGET_CARD="${TARGET_CARD:-50}"                  # oracle slots to reserve
SWAP_IN="${SWAP_IN:-100000000000000000}"          # 0.1 MUSD per warm-up swap (negligible)
TWAP="${TWAP:-300}"                               # vault's twapSeconds
WAIT_SECONDS="${WAIT_SECONDS:-320}"               # must be > TWAP

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

# Pick a signer: PRIVATE_KEY (one prompt-free run) or a keystore account.
if [[ -n "${PRIVATE_KEY:-}" ]]; then
  SIGNER=(--private-key "$PRIVATE_KEY")
  log "signer: --private-key (from env)"
else
  SIGNER=(--account "$ACCOUNT")
  log "signer: --account $ACCOUNT (you'll be prompted for the password on each tx)"
fi
SEND=(cast send "${SIGNER[@]}" --rpc-url "$RPC")
CALL=(cast call --rpc-url "$RPC")

cardinality(){ "${CALL[@]}" "$POOL" 'slot0()(uint160,int24,uint16,uint16,uint16,bool)' | sed -n '4p'; }

if (( WAIT_SECONDS <= TWAP )); then
  log "ERROR: WAIT_SECONDS ($WAIT_SECONDS) must be greater than TWAP ($TWAP)"; exit 1
fi

log "pool=$POOL  cardinality(before)=$(cardinality)  cardinalityNext target=$TARGET_CARD"

# ─── Step 1: enlarge the oracle buffer ───────────────────────────────────────
log "Step 1/4: increaseObservationCardinalityNext($TARGET_CARD)"
"${SEND[@]}" "$POOL" "increaseObservationCardinalityNext(uint16)" "$TARGET_CARD" >/dev/null
log "  done."

# ─── Step 2: approve the router to pull MUSD for the warm-up swaps ────────────
log "Step 2/4: approve router for warm-up MUSD ($(( SWAP_IN * 4 )) wei)"
"${SEND[@]}" "$MUSD" "approve(address,uint256)" "$ROUTER" "$(( SWAP_IN * 4 ))" >/dev/null
log "  done."

# One tiny MUSD->BTC swap; writes a fresh oracle observation. minOut=0, no price limit.
warmup_swap(){
  local deadline=$(( $(date +%s) + 600 ))
  "${SEND[@]}" "$ROUTER" \
    "exactInputSingle((address,address,int24,address,uint256,uint256,uint256,uint160))" \
    "($MUSD,$BTC,$TICK_SPACING,$ME,$deadline,$SWAP_IN,0,0)" >/dev/null
}

# ─── Step 3: trade #1 ────────────────────────────────────────────────────────
log "Step 3/4: warm-up trade #1"
warmup_swap
log "  cardinality now=$(cardinality)"

# ─── Wait so trade #1's observation ages past the TWAP window ─────────────────
log "Waiting ${WAIT_SECONDS}s so trade #1's observation becomes >${TWAP}s old..."
sleep "$WAIT_SECONDS"

# ─── Step 4: trade #2 ────────────────────────────────────────────────────────
log "Step 4/4: warm-up trade #2"
warmup_swap
log "  cardinality now=$(cardinality)"

# ─── Verify ──────────────────────────────────────────────────────────────────
log "Verifying observe([$TWAP,0])..."
if "${CALL[@]}" "$POOL" 'observe(uint32[])(int56[],uint160[])' "[$TWAP,0]" >/dev/null 2>&1; then
  log "✅ observe($TWAP) succeeds — restart the keeper; the rebalance should now go through."
else
  log "❌ observe($TWAP) still reverts OLD. Re-run after another >${TWAP}s wait, or raise TARGET_CARD."
  exit 1
fi
