import { NextResponse } from "next/server";
import { privateKeyToAccount } from "viem/accounts";
import { keccak256, encodePacked, isAddress, getAddress } from "viem";
import { CONTRACT_ADDRESS } from "../../../lib/contract";

// Runs on the Node runtime so the issuer key stays server-side.
export const runtime = "nodejs";

export async function POST(req: Request) {
  let subject: string | undefined;
  try {
    ({ subject } = await req.json());
  } catch {
    return NextResponse.json({ error: "Malformed request" }, { status: 400 });
  }

  if (!subject || !isAddress(subject)) {
    return NextResponse.json({ error: "Invalid wallet address" }, { status: 400 });
  }

  const pk = process.env.ISSUER_PRIVATE_KEY as `0x${string}` | undefined;
  if (!pk) {
    return NextResponse.json(
      { error: "Issuer key not configured on the server" },
      { status: 500 },
    );
  }

  const issuer = privateKeyToAccount(pk);
  const addr = getAddress(subject);

  // DEMO VERIFICATION.
  // In production the CV pipeline (KTP OCR + liveness + confidence gate) runs
  // first, and nullifier = keccak256(NIK). Here the issuer signs on request and
  // derives the nullifier from the wallet, so every demo wallet gets a unique,
  // one-time credential. Swap this block for the real pipeline call to ship.
  const nullifier = keccak256(encodePacked(["string", "address"], ["zkktp:", addr]));
  const expiry = BigInt(Math.floor(Date.now() / 1000) + 3600); // valid 1 hour

  const signature = await issuer.signTypedData({
    domain: {
      name: "zkKTP",
      version: "1",
      chainId: 4202,
      verifyingContract: CONTRACT_ADDRESS,
    },
    types: {
      Attestation: [
        { name: "subject", type: "address" },
        { name: "nullifier", type: "bytes32" },
        { name: "expiry", type: "uint256" },
      ],
    },
    primaryType: "Attestation",
    message: { subject: addr, nullifier, expiry },
  });

  return NextResponse.json({
    attestation: { subject: addr, nullifier, expiry: expiry.toString() },
    signature,
  });
}
