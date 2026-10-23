// minimal ABIs for the Superfluid contracts the UI talks to directly

export const superTokenAbi = [
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "decimals", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "transfer", stateMutability: "nonpayable", inputs: [{ name: "to", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "getUnderlyingToken", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "upgrade", stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }], outputs: [] },
  { type: "function", name: "upgradeByETH", stateMutability: "payable", inputs: [], outputs: [] },
] as const;

export const erc20Abi = [
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "decimals", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }] },
] as const;

export const cfaForwarderAbi = [
  { type: "function", name: "setFlowrate", stateMutability: "nonpayable", inputs: [{ name: "token", type: "address" }, { name: "receiver", type: "address" }, { name: "flowrate", type: "int96" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "getAccountFlowrate", stateMutability: "view", inputs: [{ name: "token", type: "address" }, { name: "account", type: "address" }], outputs: [{ type: "int96" }] },
] as const;

export const poolAbi = [
  { type: "function", name: "getTotalUnits", stateMutability: "view", inputs: [], outputs: [{ type: "uint128" }] },
  { type: "function", name: "getUnits", stateMutability: "view", inputs: [{ name: "member", type: "address" }], outputs: [{ type: "uint128" }] },
] as const;

export const gdaForwarderAbi = [
  { type: "function", name: "connectPool", stateMutability: "nonpayable", inputs: [{ name: "pool", type: "address" }, { name: "userData", type: "bytes" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "isMemberConnected", stateMutability: "view", inputs: [{ name: "pool", type: "address" }, { name: "member", type: "address" }], outputs: [{ type: "bool" }] },
] as const;
