# Demo video: beat sheet (≤ 5 min, no AI voice)

A tight, judge-friendly script. Record your own voice (Atrium docks AI voices). Total target
**~4:00**, leaving slack under the 5-minute hard cut. Three movements: **30s hook → 60s how →
90s live demo → 60s why it's new + close.**

> **The one line the whole video orbits** (say a version of this early, and again at the close):
> *"Lambda is the first v4 hook that hedges your LP position on a real Hyperliquid perp,
> **automatically and cross-chain, with no off-chain bot.** The loss LPs bleed to LVR and the
> funding a short collects are the same number with the sign flipped, so Lambda captures it."*
>
> Delta-neutral LP vaults exist. A **fully on-chain, cross-chain, automatic** hedge into a real
> perp does not. That's the thing a similar project won't have. Make it impossible to miss.

> Have these open before you hit record: the live frontend (Unichain Sepolia), a wallet with
> testnet ETH + tWETH approved, a terminal at the repo root, and `VERIFICATION.md` on a tab.

---

## 0:00-0:30: The problem (the hook)

**Say:**
> "If you provide liquidity on Uniswap, you lose money by design. It's called LVR. When the
> price moves, the pool sells the asset that's rising and buys the one that's falling, and
> arbitrage bots pocket the difference. For an ETH pool that's about **11% a year**, bleeding
> quietly from LPs. Lambda turns that loss into yield by automatically opening a matching short
> on Hyperliquid, **cross-chain, with no bot in the loop.**"

**Show:** the landing page hero / the "Normal LP vs Lambda LP" comparison.

> ⏱ Drop the "cross-chain, no bot" differentiator *here, in the first 30 seconds*. Don't save it
> for the end. It's what separates Lambda from every other delta-neutral hook in the field.

---

## 0:30-1:30: How it works (the idea + architecture)

**Say:**
> "The trick: a short on a perpetual exchange *collects* funding, and over time that funding is
> the same size as the LVR an LP loses, same number, opposite sign. So Lambda holds both: your
> Uniswap position, and a matching Hyperliquid short that cancels the price risk. The loss comes
> back as funding income."
>
> "It's three legs. **One**: a Uniswap v4 hook on Unichain tracks your position's exact delta
> and charges a directional fee. **Two**: when delta drifts, it emits one event, and a Reactive
> Smart Contract catches it cross-chain. **This is the part nobody else ships: no keeper, no
> off-chain bot, the coordination is all on-chain.** **Three**: that fires a real perp on
> Hyperliquid through the CoreWriter precompile. All automatic."

**Show:** the architecture diagram (README mermaid or the in-app `/docs` diagram), pointing to
each leg as you name it. **Linger on the leg-2 cross-chain arrow.**

---

## 1:30-3:00: Live demo (functionality)

**Say + do, in order:**

1. **Connect** wallet on Unichain Sepolia. *"Everything here is live testnet: real contracts."*
2. **Deposit** tWETH into the hook. *"I'm providing liquidity through Lambda instead of directly."*
3. **Watch the pipeline advance** `Connect → Deposit → Hedge live → Funding`.
   *"The deposit moved delta past the band, so the hook fired `HedgeRequested`."*
4. **Point at the hedge panel** showing `targetSize = 0.65 × delta`.
   *"A Reactive contract on Lasna caught that event and delivered the hedge back across chains.
   That 0.65 is the research-backed hedge ratio that keeps liquidation risk near 1%, not 20%."*
5. **Cut to terminal**, run the `cast call` and read the returned tuple:
   ```bash
   cast call 0x36C7AA315e4Cd8aB7E8CADfbD5B10A3Fb03c2E0C \
     "hedge(bytes32)((uint64,uint64,uint256,uint160))" \
     0x92fcee81621f08f93eb2e42cbb5e42d969459a5e41cda459b329cbbd0ec4373b \
     --rpc-url https://sepolia.unichain.org
   ```
   *"No UI in the loop. The cross-chain hedge is recorded on-chain. Nonce, target size, price."*
6. *(Optional but strong, 15s)* Run the **live-fork tests** and let them go green on camera:
   ```bash
   UNICHAIN_SEPOLIA_RPC=https://sepolia.unichain.org \
   HYPEREVM_RPC=https://rpc.hyperliquid.xyz/evm \
     forge test --match-path 'contracts/test/fork/*' -vvv
   ```
   *"To prove this isn't a simulation: this replays all three legs against their real chains.
   On a Unichain fork: real swap, the real hook emits the hedge, Reactive routes it, the live
   receiver records it. On a HyperEVM mainnet fork: the real hedger fires a correct CoreWriter
   short. Seven green, plus 135 unit and invariant tests."*

---

## 3:00-4:00: Why it's new + mainnet + close

**Say:**
> "What's new: as far as we know this is the first v4 hook to make the LVR-to-funding identity
> explicit and act on it, turning perpetual funding into a native Uniswap yield source. And the
> hedge is real and cross-chain and automatic, not a simulation."
>
> "Two legs run live on testnet today. The Hyperliquid leg is fully built and tested. It's not
> on *testnet* only because Reactive's testnet can't route to HyperEVM testnet. Promotion to
> mainnet follows a documented checklist: point the Reactive leg at HyperEVM mainnet
> (`DESTINATION_CHAIN_ID=999`), use the calibrated price scales (`szScaleWad=1e8`,
> `pxScaleWad=1e20`), and call `fundMargin()` to seed perp margin. No contract rewrite."
>
> "That's Lambda: the loss every LP pays, caught and turned into yield. Thanks for watching."

**Show:** the "What makes this new" section, then the partner logos / repo URL on the final frame.

---

## Don'ts (per Atrium rules)
- **No AI voice**: instant score markdown.
- **Don't exceed 5:00**: judges stop watching at the cut.
- **Don't overclaim**: say the Hyperliquid leg is "built + tested, mainnet-config," never "live."
- Keep the GitHub link pointing at the **`main`** branch in the submission.
