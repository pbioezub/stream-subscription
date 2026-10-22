import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { usePublicClient, useWriteContract } from "wagmi";
import type { Abi, Address, ContractFunctionArgs, ContractFunctionName, TransactionReceipt } from "viem";
import { errMsg } from "./format";

type Mutability = "nonpayable" | "payable";

type TxParams<abi extends Abi, fn extends ContractFunctionName<abi, Mutability>> = {
  address: Address;
  abi: abi;
  functionName: fn;
  args?: ContractFunctionArgs<abi, Mutability, fn>;
  value?: bigint;
};

/// Sends a transaction, waits for it and refetches all contract reads.
export function useTx() {
  const qc = useQueryClient();
  const client = usePublicClient();
  const { writeContractAsync } = useWriteContract();
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function send<const abi extends Abi, fn extends ContractFunctionName<abi, Mutability>>(
    label: string,
    params: TxParams<abi, fn>,
  ): Promise<TransactionReceipt | undefined> {
    setError(null);
    setPending(label);
    try {
      // params are checked against the abi above; wagmi's own overloads are too deep to forward generically
      const hash = await writeContractAsync(params as never);
      const receipt = await client!.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("transaction reverted");
      await qc.invalidateQueries();
      return receipt;
    } catch (e) {
      setError(errMsg(e));
    } finally {
      setPending(null);
    }
  }

  return { send, pending, error };
}
