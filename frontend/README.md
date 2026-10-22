# frontend

Subscribe / create / manage pages for `StreamSubscription`. Vite + React + wagmi, wallet via the browser extension.

```sh
npm install
cp .env.example .env   # set the factory address after deploying
npm run dev
```

`npm run abi` regenerates `src/abi/` from `../out` (run `forge build` first).

Routes: `#/s/<subscription>` is the link you give to subscribers, `#/manage/<subscription>` is the creator view,
`#/create` deploys a new one through the factory. Collaborators and subscriber lists come from the Superfluid
subgraph.
