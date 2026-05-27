# Security Policy

Lambda moves real value across chains, so security is treated as a core design
constraint rather than an afterthought. This document covers how the protocol
approaches safety and how to report a vulnerability.

## Design principles

- **The Uniswap swap curve is never modified.** Protection comes from dynamic
  fees and an off-pool hedge, so the core trading behavior LPs depend on stays
  standard and predictable.
- **Liquidation risk is bounded by design.** The default `h = 0.65` hedge ratio
  keeps the perpetual short well away from liquidation in normal market
  conditions.
- **Cross-chain messages are authenticated on both legs.** A hedge can only be
  triggered by a genuine, replay-protected event originating from the hook.
- **An insurance reserve** is planned to backstop rare tail scenarios.

## Pre-deployment commitments

Before any mainnet deployment, the build plan includes:

- A full third-party security review.
- Invariant fuzzing of the core accounting and hedge-sizing logic.
- On-chain monitoring of the cross-chain hedge loop.

## Known limitations (testnet stage)

We'd rather name these than paper over them:

- **Hedge fills are fire-and-forget.** `LambdaHedger` submits one IOC CoreWriter
  order per signal and records the target as filled. A partial or missed L1 fill
  isn't reconciled back, so the recorded short can drift from the true Hyperliquid
  position. Production fix: reconcile `shortSize` against the live L1 position on the
  cron checkpoint and re-issue the residual (or use managed GTC orders).
- **Sub-lot rounding biases the hedge slightly under-target.** Per-trade sizes floor
  to integer L1 lots and the dust remainder is forgiven into `shortSize`, so the
  realized short tracks marginally below the exact target. Bounded per step; would be
  tracked as an explicit carried remainder in production.
- **InsuranceVault** mints no zero-share deposits (guards the ERC-4626
  first-depositor/donation inflation grief); full virtual-shares accounting and a
  seeded first deposit are planned before it backs real value. It is not deployed in
  the testnet submission.

These are bounded, documented, and out of the critical path for the testnet demo
(the hedger is implemented and unit-tested but not deployed — see the README).

## Reporting a vulnerability

Please report suspected vulnerabilities privately rather than opening a public
issue. Use GitHub's **"Report a vulnerability"** flow under the Security tab, or
contact the maintainer directly. We aim to acknowledge reports promptly and will
credit responsible disclosures.

Do not test against live funds or deployed contracts without prior written
permission.
