# Cascade Vault

ERC-4626 tokenized share vault with a pluggable strategy stub, configurable withdrawal fee, and **EIP-2612 Permit / EIP-712** (gasless share approvals + `depositWithPermit` on permit-capable underlying). Foundry coverage: **unit + fuzz + invariant**.

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
| `CascadeVault` | OZ `ERC4626` + `ERC20Permit` + `Ownable`; withdrawal fee BPS; strategy hook |
| `permit` / `DOMAIN_SEPARATOR` | EIP-2612 on vault shares (EIP-712 domain version `"1"`) |
| `depositWithPermit` | Underlying EIP-2612 approval + deposit (try/catch tolerant to frontrun) |
| `ICascadeStrategy` | `asset` / `totalAssets` / `deposit` / `withdraw` / `harvest` |
| `IdleStrategy` | v0 default — assets sit in the strategy contract |
| `HelperConfig` + `DeployVault` | Anvil mocks + Sepolia lending/dapp WETH broadcast |

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
  mocks/ERC20Mock.sol          # mintable ERC-20 + Permit
  unit/CascadeVaultTest.t.sol
  unit/CascadeVaultPermitTest.t.sol
  fuzz/CascadeVaultFuzz.t.sol
  fuzz/CascadeVaultPermitFuzz.t.sol
  fuzz/Handler.t.sol
  fuzz/Invariants.t.sol
```

---

## Quickstart

```bash
forge install
forge test
```

Anvil deploy:

```bash
forge script script/DeployVault.s.sol:DeployVault --rpc-url http://127.0.0.1:8545 --broadcast
```

Sepolia deploy (requires `SEPOLIA_RPC_URL`, `PRIVATE_KEY`, `ETHERSCAN_API_KEY` — never commit secrets):

```bash
forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url "$SEPOLIA_RPC_URL" --broadcast --verify -vvvv
```

Recorded addresses: [`deployments/sepolia.json`](./deployments/sepolia.json).

---

## Sepolia (live)

| Contract | Address |
|---|---|
| CascadeVault (`cvWETH`) | [`0xDb56Bc666F3F76145325bA1433Ba67AD3eEE3d61`](https://sepolia.etherscan.io/address/0xDb56Bc666F3F76145325bA1433Ba67AD3eEE3d61#code) |
| IdleStrategy | [`0x92D069059C9dA4532Ca0d60a466b865F45c59512`](https://sepolia.etherscan.io/address/0x92D069059C9dA4532Ca0d60a466b865F45c59512#code) |
| Underlying WETH | [`0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9`](https://sepolia.etherscan.io/token/0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9) |

Deployer `0x70E2…a1DC` · block `12112393` · script `DeployVault.s.sol`.

### WETH note

Sepolia has **two** WETH addresses in the Cascade story — they are **not** interchangeable:

| Protocol | WETH | Address |
|---|---|---|
| defi-stablecoin (DSC collateral) | Uniswap WETH9 | `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14` |
| defi-lending / defi-dapp / **this vault** | Canonical Wrapped Ether | `0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9` |

Local tests still use **mocks**. Live Sepolia vault underlying follows **lending/dapp** WETH.

---

## License

MIT
