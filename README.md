# Cascade Vault

ERC-4626 tokenized share vault with a pluggable strategy stub and configurable withdrawal fee. Foundry coverage: **unit + fuzz + invariant**.

Repo: [github.com/DiegoCascavita/defi-vault](https://github.com/DiegoCascavita/defi-vault)

---

## Cascade Suite

| # | Repo | Role |
|---|---|---|
| 1 | [defi-stablecoin](https://github.com/DiegoCascavita/defi-stablecoin) | Overcollateralized DSC engine + `OracleLib` |
| 2 | [defi-lending](https://github.com/DiegoCascavita/defi-lending) | Lending pool + dual oracle + liquidations |
| 3 | [defi-dapp](https://github.com/DiegoCascavita/defi-dapp) | Cascade Lend — Next.js / wagmi UI |
| 4 | **defi-vault** (this repo) | ERC-4626 vault + fees / IdleStrategy |

```
defi-stablecoin ──► defi-lending ──► defi-dapp
   DSC / CR~200%      dual-oracle HF      wallet desk
                           │
                           ▼
                    defi-vault (ERC-4626)
                 tokenized shares over an asset
              (idle DAI / WETH first; pool strategy later)
```

**Independence:** this protocol is its own repo. A future strategy may supply into Cascade Lend; v0 does **not** wrap `LendingPool` internals.

---

## Architecture

```
Depositor                    Vault (ERC-4626)                 Underlying
   │                              │                                │
   │ deposit / mint               │                                │
   │ ────────────────────────────►│ transferFrom asset             │
   │◄──── shares (cvTOKEN) ───────│ ──► IdleStrategy (hold) ───────►│
   │                              │                                │
   │ withdraw / redeem            │ optional withdrawal fee skim   │
   │◄──── assets ─────────────────│ → feeRecipient                 │
```

| Piece | Role |
|---|---|
| `CascadeVault` | OZ `ERC4626` + `Ownable`; withdrawal fee BPS; strategy hook |
| `ICascadeStrategy` | `asset` / `totalAssets` / `deposit` / `withdraw` / `harvest` |
| `IdleStrategy` | v0 default — assets sit in the strategy contract |
| `HelperConfig` + `DeployVault` | Anvil mocks first; Sepolia placeholders only |

### Fees (v0)

| Fee | Default | Behavior |
|---|---|---|
| Deposit fee | `0` bps | Reserved hook |
| Withdrawal fee | `0–50` bps | Skim to `feeRecipient` on withdraw/redeem |
| Management fee | stub event | Real streaming fee = follow-up |

---

## Layout

```
src/
  CascadeVault.sol
  interfaces/ICascadeStrategy.sol
  strategies/IdleStrategy.sol
script/
  DeployVault.s.sol
  HelperConfig.s.sol
test/
  mocks/ERC20Mock.sol
  unit/CascadeVaultTest.t.sol
  fuzz/CascadeVaultFuzz.t.sol
  fuzz/Handler.t.sol
  fuzz/Invariants.t.sol
```

---

## Quickstart

```bash
forge install
forge test
```

Anvil deploy stub:

```bash
forge script script/DeployVault.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

---

## Sepolia WETH note (future)

Sepolia currently has **two** WETH addresses in the Cascade story — they are **not** interchangeable:

| Protocol | WETH | Address |
|---|---|---|
| defi-stablecoin (DSC collateral) | Uniswap WETH9 | `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14` |
| defi-lending / defi-dapp | Canonical Wrapped Ether | `0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9` |

v0 tests use **mocks only**. When Vault goes live, default underlying should follow **lending/dapp** if the strategy supplies into Cascade Lend.

---

## License

MIT
