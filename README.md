# stream-subscription

Superfluid Super App for subscriptions paid by streaming. You're subscribed while your stream to the app is at
least `minFlowRate`. Part of the incoming money (`poolShareBps`) is streamed on to a GDA pool, so collaborators
get their share in real time; the rest stays in the app for the owner.

```solidity
sub.isSubscribed(user);
```

Contracts:
- `src/StreamSubscription.sol` — the Super App, also admin of the revenue pool
- `src/StreamSubscriptionFactory.sol` — deploys and registers new subscriptions

`subscribedSince(user)` and `totalStreamed(user)` give how long someone has been subscribed and how much they
have paid in total, e.g. for perks after a few months or above some amount.

The owner can pause new subscriptions (`setPaused`); existing streams keep working.

GDA buffers aren't covered by app credit, so the app needs a small reserve in the token before the first
subscriber joins (`initialReserve` in `create`, or just transfer it; `bufferShortfall(rate)` tells how much).

## Usage

```sh
git clone --recurse-submodules https://github.com/pbioezub/stream-subscription
forge test
```

`test/StreamSubscription.invariant.t.sol` runs random subscribe / unsubscribe / units / withdraw sequences and
checks that the app never gets jailed or goes insolvent.

Fork tests run against OP Sepolia / OP Mainnet if `OP_SEPOLIA_RPC_URL` / `OP_MAINNET_RPC_URL` are set.

Deploy:

```sh
forge script script/Deploy.s.sol --rpc-url optimism_sepolia --account deployer --broadcast --verify
```

Deployed on OP Sepolia:

| | |
|---|---|
| StreamSubscriptionFactory | [`0x87FEA38543844378a5EddD5134def801d37F41e3`](https://optimism-sepolia.blockscout.com/address/0x87FEA38543844378a5EddD5134def801d37F41e3) |
| demo subscription (0.001 ETHx / month) | [`0xB45A8ad0A67172FeC0d0421671F2d91944F4C51F`](https://optimism-sepolia.blockscout.com/address/0xB45A8ad0A67172FeC0d0421671F2d91944F4C51F) |

OP Mainnet: factory [`0xe684dA181b49156d602b814FFfd4C5De6fD52132`](https://optimistic.etherscan.io/address/0xe684dA181b49156d602b814FFfd4C5De6fD52132)
(verified on Sourcify, code as of tag `v0.1.0`). Apps register themselves in the constructor, and on OP Mainnet registration is
permissioned, so `create` only works when sent by an allowlisted deployer account.

## Frontend

`frontend/` has a small web app: a subscribe page to share with subscribers, a creator page (stats,
collaborators, withdraw, pause) and a form to create new subscriptions. See `frontend/README.md`.

## License

MIT
