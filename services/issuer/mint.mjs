import "dotenv/config";
import {
  createPublicClient,
  createWalletClient,
  http,
  keccak256,
  toHex,
  defineChain,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

const liskSepolia = defineChain({
  id: 4202,
  name: "Lisk Sepolia",
  nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [process.env.RPC_URL] } },
  blockExplorers: {
    default: { name: "Blockscout", url: "https://sepolia-blockscout.lisk.com" },
  },
});

const CONTRACT = process.env.CONTRACT_ADDRESS;
const issuer = privateKeyToAccount(process.env.ISSUER_PRIVATE_KEY);
const subject = privateKeyToAccount(process.env.PRIVATE_KEY);
const nik = process.env.NIK ?? "3374010101900001";

const abi = [
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
];

const nullifier = keccak256(toHex(nik));
const expiry = BigInt(Math.floor(Date.now() / 1000) + 86400);

const domain = {
  name: "zkKTP",
  version: "1",
  chainId: 4202,
  verifyingContract: CONTRACT,
};
const types = {
  Attestation: [
    { name: "subject", type: "address" },
    { name: "nullifier", type: "bytes32" },
    { name: "expiry", type: "uint256" },
  ],
};
const attestation = { subject: subject.address, nullifier, expiry };

const signature = await issuer.signTypedData({
  domain,
  types,
  primaryType: "Attestation",
  message: attestation,
});

console.log("Issuer:      ", issuer.address);
console.log("Subject:     ", subject.address);
console.log("Nullifier:   ", nullifier);
console.log("Signature:   ", signature);

const publicClient = createPublicClient({
  chain: liskSepolia,
  transport: http(process.env.RPC_URL),
});
const walletClient = createWalletClient({
  account: subject,
  chain: liskSepolia,
  transport: http(process.env.RPC_URL),
});

const hash = await walletClient.writeContract({
  address: CONTRACT,
  abi,
  functionName: "mint",
  args: [attestation, signature],
});
console.log("\nmint tx:     ", hash);

const receipt = await publicClient.waitForTransactionReceipt({ hash });
console.log("status:      ", receipt.status);

const verified = await publicClient.readContract({
  address: CONTRACT,
  abi,
  functionName: "isVerified",
  args: [subject.address],
});
console.log("isVerified:  ", verified);
console.log("explorer:    ", `https://sepolia-blockscout.lisk.com/tx/${hash}`);
