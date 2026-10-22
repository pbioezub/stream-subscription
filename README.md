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

On OP Mainnet Super App registration is permissioned, so the factory needs to be allowlisted by Superfluid first.

## Frontend

`frontend/` has a small web app: a subscribe page to share with subscribers, a creator page (stats,
collaborators, withdraw, pause) and a form to create new subscriptions. See `frontend/README.md`.

## License

MIT
