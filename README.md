# Keel

A small perpetuals protocol, built to learn how these systems work before breaking them. LPs fund a vault, traders open leveraged long and short positions against that liquidity, and Chainlink supplies the prices.

There are no fees, no funding and no profit or loss. A position records its size, collateral and entry price, nothing more. It compiles but has no tests yet and has not been audited, so don't put real money in it.

## How it works

Three contracts:

- **`KeelVault`** is an ERC-4626 vault that holds LP money. It enforces both LP rules: reserved liquidity can't exceed a set share of the vault, and LPs can't withdraw what is reserved.
- **`KeelEngine`** holds trader collateral and positions. Traders open, increase and close here.
- **`PriceOracle`** wraps Chainlink feeds and rejects zero, negative and stale prices.

```
LP ── deposit / withdraw ──▶ KeelVault ◀── reserve / release ── KeelEngine ◀── Trader
                                                                    │
                                          Chainlink ──▶ PriceOracle ◀┘ getPrice
```

To open a position, the engine checks leverage, reads the price, pulls the collateral, and asks the vault to reserve the position's size. The vault refuses if that would pass the utilization cap. Closing releases the reservation and returns the collateral. A reservation is only a number in the vault, so no tokens move between the contracts.

LP money stays in the vault and collateral stays in the engine, which keeps the vault's `totalAssets()` equal to its plain token balance.

## Example

The vault holds 1,000,000 USDC. The cap is 80% and max leverage is 10x.

| Step | What happens |
|---|---|
| Bob opens a BTC long, size 50,000, collateral 5,000, with BTC at 65,000 | Allowed (exactly 10x). 50,000 is reserved |
| An LP tries to withdraw 960,000 | Reverts. Only 950,000 is free |
| BTC is at 70,000. Bob adds size 30,000 with 3,000 collateral | Allowed (80,000 ≤ 8,000 × 10). Entry price becomes 66,875 |
| Carol tries to open size 750,000 | Reverts. 80,000 + 750,000 passes the 800,000 cap |
| Carol opens size 720,000 | Allowed, exactly at the cap |
| Bob closes | His 80,000 reservation is released and he gets 8,000 back |

## Who does what

- **LPs** deposit, hold kLP shares, and withdraw whatever isn't reserved.
- **Traders** open, increase and close positions.
- **Admin** configures each contract and can't touch anyone's funds.
- **Chainlink** is the only outside dependency.
- **Keepers:** none. Every action is started by a user, and the oracle is read on demand. A version with liquidations and funding would need them.

| Contract | Admin functions |
|---|---|
| `PriceOracle` | `setMarket(market, feed, enabled)`, `setMaxPriceAge(seconds)` (1 second to 1 day) |
| `KeelVault` | `setEngine(engine)` (once only), `setMaxUtilization(bps)` (1 to 10,000) |
| `KeelEngine` | `setMaxLeverage(x)` (above 0) |

Deploy in this order: oracle, vault, engine, then `vault.setEngine(engine)`, then `oracle.setMarket(...)` for each market. Hand ownership to a multisig last. Until `setEngine` runs, every `openPosition` reverts.

## Formulas

```
price          = answer × 1e18 / 10^feedDecimals
shares         = assets × (totalSupply + 10^6) / (totalAssets + 1)
free liquidity = totalAssets − reserved
cap check      = reserved + size ≤ totalAssets × maxUtilizationBps / 10,000
leverage check = size ≤ collateral × maxLeverage
new entry      = (size × entry + sizeDelta × price) / (size + sizeDelta)
```

Sizes and collateral are in token units, and 1 unit is treated as 1 USD. The `10^6` is the decimals offset, which defends against the first-depositor inflation attack and gives kLP 12 decimals.

## Known limits

- **No PnL.** Traders can't lose and LPs earn nothing. If PnL is added, longs break the reserve, because a long's profit has no ceiling ([solvency notes](docs/SECURITY.md#solvency)).
- **LP lock-up.** Positions are free and never expire, so someone can reserve up to the cap and sit on it. Locking 800,000 of LP money at 10x takes about 80,000 of refundable collateral.
- **`setEngine` is permanent.** A wrong address bricks the vault.
- **Admin keys are powerful.** The cap can go up to 100%, and `setMaxLeverage` has no upper bound. Use a multisig.
- **Oracle.** One staleness window for every market, and no L2 sequencer check.
- **Token.** It must be a plain stablecoin worth 1 USD. Fee-on-transfer, rebasing and hook tokens aren't supported.

The full risk register is in [docs/SECURITY.md](docs/SECURITY.md).

## Build

```bash
git clone --recurse-submodules https://github.com/0xpenn/keel
cd keel
forge build
```

Dependencies: OpenZeppelin Contracts v5.4.0 and forge-std, both as git submodules.

## More

- [docs/SECURITY.md](docs/SECURITY.md): solvency, invariants, risk register, test plan
- [docs/DESIGN.md](docs/DESIGN.md): why it's built this way
