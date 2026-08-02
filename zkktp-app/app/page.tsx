"use client";

import { useState } from "react";
import {
  useAccount,
  useConnect,
  useDisconnect,
  useSwitchChain,
  useReadContract,
  useWriteContract,
  usePublicClient,
} from "wagmi";
import { CONTRACT_ADDRESS, EXPLORER, zkKTPAbi } from "../lib/contract";
import { liskSepolia } from "../lib/wagmi";

type Status = "idle" | "signing" | "minting" | "done" | "error";

function shorten(addr?: string) {
  return addr ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : "—";
}

export default function Home() {
  const { address, isConnected, chainId } = useAccount();
  const { connect, connectors, isPending: connecting } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain, isPending: switching } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();
  const publicClient = usePublicClient();

  const wrongNetwork = isConnected && chainId !== liskSepolia.id;

  const { data: verifiedOnChain, refetch } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: zkKTPAbi,
    functionName: "isVerified",
    args: address ? [address] : undefined,
    query: { enabled: !!address && !wrongNetwork },
  });

  const [status, setStatus] = useState<Status>("idle");
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
  const [error, setError] = useState<string | null>(null);

  const verified = verifiedOnChain === true || status === "done";
  const busy = status === "signing" || status === "minting";

  async function mint() {
    if (!address) return;
    setError(null);
    try {
      setStatus("signing");
      const res = await fetch("/api/attest", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ subject: address }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error ?? "Could not issue attestation");
      }
      const { attestation, signature } = await res.json();

      setStatus("minting");
      const hash = await writeContractAsync({
        address: CONTRACT_ADDRESS,
        abi: zkKTPAbi,
        functionName: "mint",
        args: [
          {
            subject: attestation.subject as `0x${string}`,
            nullifier: attestation.nullifier as `0x${string}`,
            expiry: BigInt(attestation.expiry),
          },
          signature as `0x${string}`,
        ],
        chain: liskSepolia,
        account: address,
      });
      setTxHash(hash);
      await publicClient?.waitForTransactionReceipt({ hash });
      await refetch();
      setStatus("done");
    } catch (e: unknown) {
      const msg =
        (e as { shortMessage?: string })?.shortMessage ??
        (e as Error)?.message ??
        "Something went wrong";
      // Trim noisy revert dumps to the reason
      setError(msg.split("\n")[0]);
      setStatus("error");
    }
  }

  const injected = connectors[0];

  return (
    <main className="shell">
      <header className="masthead">
        <div className="wordmark">
          <span className="zk">zk</span>KTP
        </div>
        <div className="net">
          <span className="dot" />
          Lisk Sepolia · testnet
        </div>
      </header>

      <section className="hero">
        <div>
          <p className="eyebrow">Proof-of-Personhood · Indonesia</p>
          <h1>
            One human.
            <br />
            One <span className="em">credential.</span>
          </h1>
          <p className="lede">
            Prove you're a unique, verified human on-chain and receive a{" "}
            <strong>soulbound credential</strong> any dApp can check. Your KTP and
            biometrics never touch the chain — only a one-way nullifier does.
          </p>
          <ul className="tenets">
            <li>No identity data on-chain, ever</li>
            <li>Non-transferable — can't be sold or farmed</li>
            <li>One verified person, one credential</li>
          </ul>
        </div>

        <div className="stage">
          <Credential address={address} verified={verified} />

          <div className="panel">
            {!isConnected && (
              <>
                <div className="panel__row">
                  <span className="k">Status</span>
                  <span className="v">Not connected</span>
                </div>
                <button
                  className="btn"
                  onClick={() => injected && connect({ connector: injected })}
                  disabled={connecting || !injected}
                  style={{ marginTop: 16 }}
                >
                  {connecting ? <span className="spinner" /> : null}
                  Connect wallet
                </button>
                <p className="hint">
                  Needs a browser wallet (MetaMask). You'll be asked to approve the
                  connection — no transaction yet.
                </p>
              </>
            )}

            {isConnected && wrongNetwork && (
              <>
                <div className="panel__row">
                  <span className="k">Network</span>
                  <span className="v warn">Wrong network</span>
                </div>
                <button
                  className="btn btn--primary"
                  onClick={() => switchChain({ chainId: liskSepolia.id })}
                  disabled={switching}
                  style={{ marginTop: 16 }}
                >
                  {switching ? <span className="spinner" /> : null}
                  Switch to Lisk Sepolia
                </button>
                <p className="hint">
                  The credential lives on Lisk Sepolia. Switch networks to continue.
                </p>
              </>
            )}

            {isConnected && !wrongNetwork && (
              <>
                <div className="panel__row">
                  <span className="k">Wallet</span>
                  <span className="v">{shorten(address)}</span>
                </div>
                <div className="panel__row">
                  <span className="k">Credential</span>
                  <span className={`v ${verified ? "ok" : ""}`}>
                    {verified ? "Held ✓" : "None yet"}
                  </span>
                </div>

                {!verified && (
                  <>
                    <button
                      className="btn btn--primary"
                      onClick={mint}
                      disabled={busy}
                      style={{ marginTop: 16 }}
                    >
                      {busy ? <span className="spinner" /> : null}
                      {status === "signing"
                        ? "Issuing attestation…"
                        : status === "minting"
                          ? "Minting credential…"
                          : "Verify & mint credential"}
                    </button>
                    <p className="hint">
                      Demo mode: verification is simulated — the issuer signs on
                      request. In production the KTP OCR + liveness pipeline runs
                      first, then the issuer signs.
                    </p>
                  </>
                )}

                {verified && (
                  <p className="hint" style={{ marginTop: 16 }}>
                    This wallet holds a zkKTP credential. It's soulbound — try to
                    transfer it and the contract reverts.
                  </p>
                )}

                {txHash && (
                  <a
                    className="txlink"
                    href={`${EXPLORER}/tx/${txHash}`}
                    target="_blank"
                    rel="noreferrer"
                  >
                    View transaction ↗
                  </a>
                )}
                {error && <p className="error">{error}</p>}

                <button
                  className="btn btn--ghost"
                  onClick={() => disconnect()}
                  style={{ marginTop: 16 }}
                >
                  Disconnect
                </button>
              </>
            )}
          </div>
        </div>
      </section>

      <footer className="foot">
        <span>
          Contract{" "}
          <a href={`${EXPLORER}/address/${CONTRACT_ADDRESS}`} target="_blank" rel="noreferrer">
            {shorten(CONTRACT_ADDRESS)}
          </a>{" "}
          · verified
        </span>
        <span>ERC-5192 soulbound · EIP-712 attestation</span>
      </footer>
    </main>
  );
}

function Credential({
  address,
  verified,
}: {
  address?: string;
  verified: boolean;
}) {
  return (
    <div
      className={`card ${verified ? "card--verified" : "card--ghost"}`}
      aria-label={verified ? "Issued credential" : "Unissued credential"}
    >
      <div className="card__band">
        <span className="id">zkKTP · Proof-of-Personhood</span>
        <span className="card__flag">
          <span className="r" />
          <span className="w" />
        </span>
      </div>

      <div className="card__body">
        <div className="card__photo">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
            <circle cx="12" cy="8" r="4" />
            <path d="M4 21c0-4 4-6 8-6s8 2 8 6" />
          </svg>
        </div>
        <div className="card__fields">
          <div className="field">
            <div className="k">Holder</div>
            <div className="v">{address ?? "Not connected"}</div>
          </div>
          <div className="field">
            <div className="k">Status</div>
            <div className="v">{verified ? "Verified unique human" : "Awaiting issuance"}</div>
          </div>
          <div className="field">
            <div className="k">Type</div>
            <div className="v">Soulbound · non-transferable</div>
          </div>
        </div>
      </div>

      {verified && (
        <div className="card__seal">
          Verified
          <br />
          On-chain
        </div>
      )}

      <div className="card__foot">
        <span className="card__chip" />
        <span>{verified ? "Lisk Sepolia · 4202" : "Not yet issued"}</span>
      </div>
    </div>
  );
}
