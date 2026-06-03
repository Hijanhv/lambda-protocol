# Fork testing — proving Lambda against live contracts, for free

This is how we test Lambda the way serious protocols do: by **forking a live chain onto
your laptop** and running the real deployed contracts against it. No testnet faucet, no
gas spent, no dependence on anyone else's infra. It is a big step up from the isolated
unit tests — those simulate; this runs against real on-chain state.

## What it is

`anvil --fork-url <rpc>` (or `vm.createSelectFork` inside a Foundry test) copies a chain's
**real state** — deployed bytecode, storage, balances — at a block onto your machine. You
then give yourself fake tokens (`deal`) and impersonate any account (`vm.prank`) and
interact with the *live* contracts locally. Nothing touches the real chain.

## Run it

All three legs against their real chains, in one run:

```bash
export UNICHAIN_SEPOLIA_RPC=https://sepolia.unichain.org   # legs ① + ③
export HYPEREVM_RPC=https://rpc.hyperliquid.xyz/evm        # leg ②  (HyperEVM mainnet, chain 999)
forge test --match-path 'contracts/test/fork/*' -vvv
```

Each file self-skips if its RPC is unset, so you can run just one:

```bash
forge test --match-path 'contracts/test/fork/LambdaForkE2E.t.sol' -vvv          # needs UNICHAIN_SEPOLIA_RPC
forge test --match-path 'contracts/test/fork/LambdaHedgerForkHyperEVM.t.sol' -vvv # needs HYPEREVM_RPC
```

Optional — pin a block for byte-for-byte determinism (recommended for CI):

```bash
export UNICHAIN_SEPOLIA_FORK_BLOCK=<block number>
export HYPEREVM_FORK_BLOCK=<block number>
```

With **no** RPC env set, every fork test self-skips, so the normal `forge test` stays
green and offline.

## What `LambdaForkE2E.t.sol` proves

Against the **live** deployment on Unichain Sepolia (chain 1301):

| Test | Proves |
|---|---|
| `test_fork_poolTopologyMatchesLive` | Our reconstructed `PoolKey` hashes to the live `poolId` — token order, fee, tickSpacing are all correct. |
| `test_fork_liveHookIsConfiguredAndHedging` | The deployed hook is a real configured vault: seeded liquidity, nonzero LP delta, ≥1 hedge already signalled, live directional fee both sides. |
| `test_fork_endToEndHedgeLoop` | The full cross-chain loop: a **real swap** through the live PoolManager + hook → the live hook emits a **real `HedgeRequested`** → fed into `LambdaReactive.react()` → produces the cross-chain callback → delivered to the **live receiver** while impersonating the real Reactive proxy → receiver records it (auth + monotonic nonce enforced). |
| `test_fork_receiverRejectsUnauthorizedCaller` | The live receiver rejects a hedge from any address that isn't the authorized callback proxy. |

## What `LambdaHedgerForkHyperEVM.t.sol` proves

Against a **live HyperEVM mainnet fork** (chain 999) — this is leg ②, the real perp:

| Test | Proves |
|---|---|
| `test_fork_isHyperEVM` | The RPC really points at HyperEVM (chain id 998/999) at a real block. |
| `test_fork_hedgerFiresRealCoreWriterShort` | The **real `LambdaHedger`**, deployed onto forked HyperEVM state and fed the callback, fires **one** CoreWriter order whose bytes match the Hyperliquid schema exactly: version `0x01`, action id `1` (limit order), correct asset, `isBuy=false` (short), `reduceOnly=false` (growing), taker TIF, non-zero size/price, and the deterministic `cloid(poolId, nonce)`. Hedger state advances to the target short. |
| `test_fork_reduceIsReduceOnlyBuy` | Shrinking the short fires a `reduceOnly` **buy**, so a hedge close can never flip the position long. |

**Honest boundary for this file:** a vanilla fork can't *execute* the CoreWriter precompile
(HyperCore is implemented by Hyper's node, not EVM bytecode), so we `vm.etch` a recorder at
`0x3333…3333` to **capture** the action and assert it. The hedger, the size/price math, and
the order framing all run against real forked HyperEVM state; the live HyperCore *fill* is
proven only by an actual mainnet deployment.

## What a fork does NOT prove (be honest about this)

A fork copies **one chain at one block**. It does not run the off-chain machinery that
bridges chains. Specifically:

- **The Reactive Network relayer.** In the test we drive `react()` and the proxy call
  ourselves. We do **not** prove the live ReactVM observed the log and delivered the
  callback in production. That can only be proven by a real deployment with the live
  relayer — which we've already done once on testnet (see `VERIFICATION.md`).
- **HyperLiquid's HyperCore execution.** The real `LambdaHedger` calls the CoreWriter
  precompile `0x3333…3333`, whose effect is implemented by Hyper's node, not by EVM
  bytecode a fork can copy. `LambdaHedgerForkHyperEVM.t.sol` runs the real hedger against
  forked HyperEVM state and asserts the exact order it *submits*, but the precompile is
  etched-to-capture — the actual HyperCore *fill* is proven only by a mainnet deployment.

**So:** fork testing proves our **contract logic is correct against real state**. The
**live relayer + HyperCore plumbing** is proven separately by the actual on-chain
deployment. Both matter; they are different claims, and we don't conflate them.

## Updating addresses after a redeploy

The live addresses are constants at the top of `LambdaForkE2E.t.sol` (mirrored from
`DEPLOY_TESTNET.md` / `frontend/.env.local`). If a redeploy moves them,
`test_fork_poolTopologyMatchesLive` is the canary — it fails immediately if the
hook/token/pool wiring no longer matches.
