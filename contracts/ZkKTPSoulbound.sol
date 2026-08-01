// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title IERC5192 — Minimal Soulbound Token interface
interface IERC5192 {
    /// @notice Emitted when a token is locked (non-transferable).
    event Locked(uint256 tokenId);
    /// @notice Emitted when a token is unlocked. Never emitted here — all tokens stay locked.
    event Unlocked(uint256 tokenId);
    /// @notice Returns the locking status of a token. Always true for existing tokens.
    function locked(uint256 tokenId) external view returns (bool);
}

/// @title ZkKTPSoulbound
/// @notice Non-transferable "verified unique Indonesian human" credential.
///         Minted only against an EIP-712 attestation signed by a trusted off-chain
///         issuer. No PII is stored on-chain — only a one-way nullifier derived from
///         the NIK, which guarantees one credential per person.
contract ZkKTPSoulbound is ERC721, EIP712, Ownable, IERC5192 {
    using ECDSA for bytes32;

    // --- Types ---

    struct Attestation {
        address subject; // wallet permitted to mint
        bytes32 nullifier; // H(NIK) — uniqueness anchor, non-reversible
        uint256 expiry; // unix seconds; mint reverts after this
    }

    bytes32 private constant ATTESTATION_TYPEHASH =
        keccak256("Attestation(address subject,bytes32 nullifier,uint256 expiry)");

    // --- Storage ---

    address public trustedIssuer;
    uint256 private _nextTokenId;

    /// @dev nullifier => consumed. Enforces one credential per verified person.
    mapping(bytes32 => bool) public usedNullifiers;

    /// @dev holder => true once they hold a credential. Enforces one credential per wallet.
    mapping(address => bool) public isVerified;

    // --- Events ---

    event CredentialMinted(address indexed subject, uint256 indexed tokenId, bytes32 nullifier);
    event TrustedIssuerUpdated(address indexed previousIssuer, address indexed newIssuer);

    // --- Errors ---

    error Soulbound();
    error InvalidIssuerSignature();
    error AttestationExpired();
    error NullifierAlreadyUsed();
    error AlreadyVerified();
    error WrongSubject();
    error ZeroAddressIssuer();

    constructor(address issuer_)
        ERC721("zkKTP Proof-of-Personhood", "zkKTP")
        EIP712("zkKTP", "1")
        Ownable(msg.sender)
    {
        if (issuer_ == address(0)) revert ZeroAddressIssuer();
        trustedIssuer = issuer_;
        emit TrustedIssuerUpdated(address(0), issuer_);
    }

    // --- Minting ---

    /// @notice Mint a soulbound credential against a signed issuer attestation.
    /// @param att The attestation binding a wallet to a verified nullifier.
    /// @param signature The issuer's EIP-712 signature over `att`.
    function mint(Attestation calldata att, bytes calldata signature) external returns (uint256 tokenId) {
        if (att.subject != msg.sender) revert WrongSubject();
        if (block.timestamp > att.expiry) revert AttestationExpired();
        if (usedNullifiers[att.nullifier]) revert NullifierAlreadyUsed();
        if (isVerified[msg.sender]) revert AlreadyVerified();

        bytes32 structHash =
            keccak256(abi.encode(ATTESTATION_TYPEHASH, att.subject, att.nullifier, att.expiry));
        address signer = _hashTypedDataV4(structHash).recover(signature);
        if (signer != trustedIssuer) revert InvalidIssuerSignature();

        usedNullifiers[att.nullifier] = true;
        isVerified[msg.sender] = true;

        tokenId = ++_nextTokenId;
        _safeMint(msg.sender, tokenId);

        emit Locked(tokenId);
        emit CredentialMinted(msg.sender, tokenId, att.nullifier);
    }

    // --- ERC-5192 ---

    /// @inheritdoc IERC5192
    function locked(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return true; // every credential is permanently soulbound
    }

    // --- Admin ---

    function setTrustedIssuer(address newIssuer) external onlyOwner {
        if (newIssuer == address(0)) revert ZeroAddressIssuer();
        emit TrustedIssuerUpdated(trustedIssuer, newIssuer);
        trustedIssuer = newIssuer;
    }

    // --- Soulbound enforcement ---

    /// @dev OZ v5 transfer hook. Allow mint (from == 0) and burn (to == 0); block transfers.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    // --- Interface support ---

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC5192).interfaceId || super.supportsInterface(interfaceId);
    }
}
