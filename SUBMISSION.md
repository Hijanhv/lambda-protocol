# Lambda — UHI9 submission text

Form ready text describing exactly what is built and verifiable in this repo. Numbers that
are research based projections are labelled as such. Nothing here claims a feature that is
not in the code.

## Project name

Lambda. Yield protected liquidity for Uniswap v4. Turns the structural LVR loss every LP
pays into LP yield, via a real cross chain perpetual hedge on Hyperliquid.

## Sponsors / theme

- [x] Reactive Network
- [x] Uniswap Hookathon theme: Impermanent Loss and Yield Systems
- [ ] Uniswap v4 hook with no sponsor integrations

## Solo or team

- [x] Solo

## Cohort

- [x] UHI9

## Preferred name / email / Discord

```
Janhavi Chavada
(email and Discord are entered directly on the UHI9 submission portal; kept out of this public file to avoid scraping)
```

## How partners are integrated

**Reactive Network** (deployed on Reactive Lasna 5318007). `LambdaReactive` is a Reactive
Smart Contract that subscribes to the hook's `HedgeRequested` event on Unichain Sepolia and,
with no off chain bot, routes a cross chain callback to the destination contract that
re sizes the perp hedge. It enforces strictly increasing per pool nonces, so replays and out
of order events are dropped, and the destination re checks the nonce, so the hedge is
authenticated on both legs. It can also subscribe to a Reactive cron topic to drive periodic
funding checkpoints. Verified live end to end: a real `HedgeRequested` on Unichain Sepolia
was caught on Lasna and the callback was delivered and recorded on the destination, with no
bot in the loop. Anyone can read the delivered hedge with a single `cast call`. On mainnet
the same callback targets the real `LambdaHedger` on HyperEVM. HyperEVM is a Reactive
destination on mainnet (999) only, which the Reactive Network team confirmed directly, so
promotion is a one line config change (`DESTINATION_CHAIN_ID=999`) with no code change.

**Uniswap v4.** `LambdaHook` is a first class v4 hook that doubles as the LP vault. It gates
both liquidity paths so the vault is the pool's only LP, which makes the tracked delta exact;
reads the post swap price on `afterSwap` and raises a `HedgeRequested` signal when delta
drifts past a band; and returns a Nezlobin directional fee override on `beforeSwap` for a
dynamic fee pool. The trading curve is never modified. The delta math is settlement grade and
cross checked against Uniswap's own `getAmount0Delta` (fuzzed). The repo also includes an
`InsuranceVault` with an Aave V3 venue, built and tested but not yet deployed, for a
liquidation gap reserve that would earn yield while idle. The hook was self audited with
Uniswap's official `v4-security-foundations` skill, all twelve v4 vulnerability classes
checked, plus fuzzing and invariant suites, with no Medium or above findings.

**Hyperliquid.** `LambdaHedger` turns the hedge callback into a real perpetual order through
the CoreWriter precompile at `0x3333333333333333333333333333333333333333` on HyperEVM. Order
bytes are framed by Lambda's own `CoreWriterLib`, following Hyperliquid's CoreWriter action
spec (one version byte, a three byte action id, then the ABI encoded order), tested byte for
byte. The precompile is verified live on chain. The hedger leg is proven against real HyperEVM
mainnet state on a Foundry fork: the real hedger, deployed on the fork, takes the callback and
fires a correct CoreWriter short, asserted byte for byte against the schema.

## Key links

- GitHub: https://github.com/Hijanhv/lambda-protocol
- Live dashboard: https://lambda-protocol.vercel.app
- Demo video: {to be filled}
- On chain verification (Unichain Sepolia): contracts and the delivered hedge are readable via
  the `cast call` shown in the README "Live on testnet" section
- Reactive RSC (Lasna): https://lasna.reactscan.net/

## Problem and background

Vanilla Uniswap LPs lose a measured, structural amount called loss versus rebalancing (LVR)
every block. Milionis, Moallemi, Roughgarden and Zhang (2022, ACM EC) prove the closed form
rate `lambda / V = sigma^2 / 8`. For an ETH USDC pool at roughly 5 percent daily volatility
that is about 11 percent per year transferred from LPs to arbitrageurs, a cost that trading
fees often do not cover.

LVR has a mirror image: a short position on a perpetual exchange collects funding, and over
time that funding is statistically the same size as the LVR an LP loses, same number with the
sign flipped, because both are paid by demand for exposure to a moving price. Lambda makes
this identity explicit on chain: hold the LP position and a matching Hyperliquid short
together, and the loss that used to leak out returns to the LP as funding income.

Lambda does not blindly fully hedge. Following Hane (2026), it ships a hedge ratio `h = 0.65`,
which keeps liquidation risk near 1.4 percent instead of near 19 percent at a full hedge while
still removing the large majority of price risk. Protection comes from two independent
mechanisms aimed at the same leak: a directional dynamic fee that makes informed flow pay the
LP on chain, and the perp hedge that neutralises residual price risk off pool.

## Impact

Lambda addresses the Yield Systems half of the UHI9 theme by turning Hyperliquid funding into
a native v4 LP yield source. Research based targets for an ETH USDC position at `h = 0.65`
(modelled, not measured returns):

- LVR captured back as funding income, scaled by `h`
- Swap fee yield unchanged, since the curve is untouched
- Hyperliquid funding yield on the short in non bear regimes
- The large majority of first order impermanent loss neutralised
- A delta neutral, yield positive LP position that aims to earn whether price moves up, down,
  or sideways

The intended outcome is to pull risk averse capital into v4 pools and to bring perpetual
funding on chain as a reusable v4 yield primitive.

## What we built and the challenges we solved

1. **The LVR to funding identity, acted on.** Lambda is, as far as we know, the first v4 hook
   to make the LVR to funding identity explicit on chain and route the captured value back to
   LPs as funding income.
2. **Exact delta tracking.** Because the hook is the pool's only LP, its tracked liquidity is
   exactly the pool's liquidity over the managed range, so the delta in each hedge signal is
   exact, not the `liquidity / 2` approximation many tools use. The math is cross checked
   against Uniswap's own `getAmount0Delta` with fuzz tests.
3. **Automatic cross chain hedge with no off chain bot.** The coordination that would normally
   need a centralized keeper runs entirely on a Reactive Smart Contract. Verified live end to
   end on testnet: a swap on Unichain Sepolia raised the signal, Reactive on Lasna caught it,
   and the destination recorded the exact hedge.
4. **Proving the perp leg without a live testnet route.** Reactive's testnet does not route
   callbacks to HyperEVM testnet, only to mainnet, which the Reactive team confirmed. So we
   proved the hedger against real HyperEVM mainnet state on a Foundry fork: the real
   `LambdaHedger` fires a correct CoreWriter short, checked byte for byte. Promotion to a live
   mainnet loop is a one line config change.
5. **Authentication on both legs.** The cross chain payload carries a placeholder that is not
   trusted. Authorization is the Reactive callback proxy allowlist plus a strictly increasing
   per pool nonce that is re checked on the destination, so replays and out of order callbacks
   are dropped on both legs.
6. **Test rigor.** 135 Foundry tests, warning free build, run in CI on every push: 128 unit
   and invariant tests including 12 fuzz tests and 2 invariant suites, plus 7 live fork tests
   that replay all three legs against their real chains' state (legs one and three on a
   Unichain Sepolia fork against the live contracts, leg two on a HyperEVM mainnet fork). A
   Next.js dashboard reads live on chain state and lets a judge deposit, watch the hedge fire,
   and verify the delivered result.

## Status

Legs one and three are live on Unichain Sepolia and Reactive Lasna and verified on chain end
to end. Leg two, the Hyperliquid perp, is fully written, unit tested, and fork proven against
real HyperEVM mainnet state. It is not on testnet for one external reason only: Reactive's
testnet does not route to HyperEVM testnet. Mainnet is a config flip, not a rewrite.

## Team

Solo submission. Math, contracts, Reactive and Hyperliquid integration, the frontend, tests,
and deployment.
