# Lambda LP Dashboard

The LP-facing app for Lambda: **deposit → watch the hedge → collect funding → withdraw**, the
full journey against the deployed contracts. Next.js (App Router) + wagmi/viem, talking to
`LambdaHook` and `Funding` on the chain where the hook lives (Unichain).

## Run

```bash
cd frontend
npm install
cp .env.example .env.local        # fill in addresses from the deploy scripts (see ../DEPLOY.md)
npm run dev                        # http://localhost:3000
```

Until `.env.local` is filled in, the app loads and shows a configuration banner — it never
hard-codes addresses. The ABIs in `abis/` are exported straight from the Foundry build
(`out/<Contract>.sol/<Contract>.json`); re-export after a contract change with:

```bash
node -e "const a=require('../out/LambdaHook.sol/LambdaHook.json').abi; require('fs').writeFileSync('abis/LambdaHook.json', JSON.stringify(a,null,2));"
```

## What each panel shows

- **Your position** — vault shares; deposit a liquidity amount (approve both tokens once) and
  withdraw all. The hook converts liquidity to the token amounts it pulls.
- **The hedge** — the live LP delta the protocol tracks, the last hedge signal (nonce + hedged
  delta) routed to the HyperEVM hedger, the hedge ratio, and the live **directional fee** in
  each swap direction.
- **Funding income** — funding accrued to you, claimable in one click; plus the pool's
  outstanding funding liability.

The step bar at the top advances Connect → Deposit → Hedge live → Funding accrues as your
position progresses.

## Demo video

A 2–3 minute walkthrough (deposit, show the hedge nonce increment after a swap, watch funding
accrue, claim, withdraw) is the recommended companion for submission — record it against a
testnet deployment once the contracts are live. This app is the script for that walkthrough.

> Note: the deposit form takes a raw liquidity amount with generous slippage bounds — the
> honest minimal mapping. Wiring a v4 quoter to enter by token amount is a small follow-up.
