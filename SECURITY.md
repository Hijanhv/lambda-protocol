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

## Reporting a vulnerability

Please report suspected vulnerabilities privately rather than opening a public
issue. Use GitHub's **"Report a vulnerability"** flow under the Security tab, or
contact the maintainer directly. We aim to acknowledge reports promptly and will
credit responsible disclosures.

Do not test against live funds or deployed contracts without prior written
permission.
