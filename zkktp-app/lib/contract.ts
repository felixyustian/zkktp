export const CONTRACT_ADDRESS = (process.env.NEXT_PUBLIC_CONTRACT_ADDRESS ??
  "0xAED6894cd859dEd2Df83be9D96B8EcC7945D3b2F") as `0x${string}`;

export const EXPLORER = "https://sepolia-blockscout.lisk.com";

export const zkKTPAbi = [
  {
    type: "function",
    name: "mint",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "att",
        type: "tuple",
        components: [
          { name: "subject", type: "address" },
          { name: "nullifier", type: "bytes32" },
          { name: "expiry", type: "uint256" },
        ],
      },
      { name: "signature", type: "bytes" },
    ],
    outputs: [{ name: "tokenId", type: "uint256" }],
  },
  {
    type: "function",
    name: "isVerified",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;
