import type { Address } from "viem";

async function query<T>(url: string, q: string, variables: Record<string, unknown>): Promise<T> {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query: q, variables }),
  });
  const json = await res.json();
  if (json.errors) throw new Error(json.errors[0].message);
  return json.data;
}

export type PoolMember = { account: { id: Address }; units: string; isConnected: boolean };

export async function poolMembers(url: string, pool: Address) {
  const data = await query<{ pool: { poolMembers: PoolMember[] } | null }>(
    url,
    `query($id: ID!) { pool(id: $id) { poolMembers(first: 100, where: { units_gt: "0" }) { account { id } units isConnected } } }`,
    { id: pool.toLowerCase() },
  );
  return data.pool?.poolMembers ?? [];
}

export type Subscriber = { sender: { id: Address }; currentFlowRate: string; createdAtTimestamp: string };

export async function subscribers(url: string, app: Address) {
  const data = await query<{ streams: Subscriber[] }>(
    url,
    `query($app: String!) { streams(first: 100, orderBy: createdAtTimestamp, orderDirection: desc,
       where: { receiver: $app, currentFlowRate_gt: "0" }) { sender { id } currentFlowRate createdAtTimestamp } }`,
    { app: app.toLowerCase() },
  );
  return data.streams;
}
