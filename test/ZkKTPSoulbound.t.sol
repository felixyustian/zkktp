// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ZkKTPSoulbound} from "../contracts/ZkKTPSoulbound.sol";

contract ZkKTPSoulboundTest is Test {
    ZkKTPSoulbound internal zkktp;

    address internal issuer;
    uint256 internal issuerPk;
    address internal user1;
    address internal user2;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant ATTESTATION_TYPEHASH =
        keccak256("Attestation(address subject,bytes32 nullifier,uint256 expiry)");

    function setUp() public {
        vm.warp(1_700_000_000); // sane timestamp so expiry math never underflows
        (issuer, issuerPk) = makeAddrAndKey("issuer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        zkktp = new ZkKTPSoulbound(issuer);
    }

    // --- helpers ---

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("zkKTP")),
                keccak256(bytes("1")),
                block.chainid,
                address(zkktp)
            )
        );
    }

    function _sign(uint256 pk, ZkKTPSoulbound.Attestation memory att)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash =
            keccak256(abi.encode(ATTESTATION_TYPEHASH, att.subject, att.nullifier, att.expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _att(address subject, bytes32 nullifier)
        internal
        view
        returns (ZkKTPSoulbound.Attestation memory)
    {
        return ZkKTPSoulbound.Attestation({
            subject: subject,
            nullifier: nullifier,
            expiry: block.timestamp + 1 hours
        });
    }

    // --- happy path ---

    function test_MintSucceeds() public {
        bytes32 nul = keccak256("NIK:3374...0001");
        ZkKTPSoulbound.Attestation memory att = _att(user1, nul);
        bytes memory sig = _sign(issuerPk, att);

        vm.prank(user1);
        uint256 tokenId = zkktp.mint(att, sig);

        assertEq(tokenId, 1);
        assertEq(zkktp.ownerOf(1), user1);
        assertEq(zkktp.balanceOf(user1), 1);
        assertTrue(zkktp.isVerified(user1));
        assertTrue(zkktp.usedNullifiers(nul));
        assertTrue(zkktp.locked(1));
    }

    // --- uniqueness: one human, one credential ---

    function test_DoubleMintSameNullifierReverts() public {
        bytes32 nul = keccak256("NIK:same-person");

        ZkKTPSoulbound.Attestation memory a1 = _att(user1, nul);
        vm.prank(user1);
        zkktp.mint(a1, _sign(issuerPk, a1));

        // same person (same nullifier), different wallet -> rejected
        ZkKTPSoulbound.Attestation memory a2 = _att(user2, nul);
        bytes memory sig2 = _sign(issuerPk, a2);
        vm.prank(user2);
        vm.expectRevert(ZkKTPSoulbound.NullifierAlreadyUsed.selector);
        zkktp.mint(a2, sig2);
    }

    function test_SameWalletCannotMintTwice() public {
        ZkKTPSoulbound.Attestation memory a1 = _att(user1, keccak256("nul-a"));
        vm.prank(user1);
        zkktp.mint(a1, _sign(issuerPk, a1));

        // same wallet, different nullifier -> rejected as already verified
        ZkKTPSoulbound.Attestation memory a2 = _att(user1, keccak256("nul-b"));
        bytes memory sig2 = _sign(issuerPk, a2);
        vm.prank(user1);
        vm.expectRevert(ZkKTPSoulbound.AlreadyVerified.selector);
        zkktp.mint(a2, sig2);
    }

    // --- soulbound enforcement ---

    function test_TransferReverts() public {
        ZkKTPSoulbound.Attestation memory att = _att(user1, keccak256("nul-t"));
        vm.prank(user1);
        zkktp.mint(att, _sign(issuerPk, att));

        vm.prank(user1);
        vm.expectRevert(ZkKTPSoulbound.Soulbound.selector);
        zkktp.transferFrom(user1, user2, 1);
    }

    function test_ApproveReverts() public {
        ZkKTPSoulbound.Attestation memory att = _att(user1, keccak256("nul-ap"));
        vm.prank(user1);
        zkktp.mint(att, _sign(issuerPk, att));

        vm.prank(user1);
        vm.expectRevert(ZkKTPSoulbound.Soulbound.selector);
        zkktp.approve(user2, 1);
    }

    function test_SetApprovalForAllReverts() public {
        vm.prank(user1);
        vm.expectRevert(ZkKTPSoulbound.Soulbound.selector);
        zkktp.setApprovalForAll(user2, true);
    }

    // --- attestation validation ---

    function test_ExpiredAttestationReverts() public {
        ZkKTPSoulbound.Attestation memory att = ZkKTPSoulbound.Attestation({
            subject: user1,
            nullifier: keccak256("nul-exp"),
            expiry: block.timestamp - 1
        });
        bytes memory sig = _sign(issuerPk, att);
        vm.prank(user1);
        vm.expectRevert(ZkKTPSoulbound.AttestationExpired.selector);
        zkktp.mint(att, sig);
    }

    function test_WrongSubjectReverts() public {
        // attestation is for user1, but user2 tries to redeem it
        ZkKTPSoulbound.Attestation memory att = _att(user1, keccak256("nul-ws"));
        bytes memory sig = _sign(issuerPk, att);
        vm.prank(user2);
        vm.expectRevert(ZkKTPSoulbound.WrongSubject.selector);
        zkktp.mint(att, sig);
    }

    function test_InvalidIssuerSignatureReverts() public {
        (, uint256 attackerPk) = makeAddrAndKey("attacker");
        ZkKTPSoulbound.Attestation memory att = _att(user1, keccak256("nul-bad"));
        bytes memory badSig = _sign(attackerPk, att); // not the trusted issuer
        vm.prank(user1);
        vm.expectRevert(ZkKTPSoulbound.InvalidIssuerSignature.selector);
        zkktp.mint(att, badSig);
    }

    // --- admin ---

    function test_SetTrustedIssuerOnlyOwner() public {
        address newIssuer = makeAddr("newIssuer");
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        zkktp.setTrustedIssuer(newIssuer);
    }

    function test_OwnerCanRotateIssuer() public {
        (address newIssuer, uint256 newPk) = makeAddrAndKey("newIssuer");
        zkktp.setTrustedIssuer(newIssuer); // test contract is owner

        ZkKTPSoulbound.Attestation memory att = _att(user1, keccak256("nul-rot"));
        vm.prank(user1);
        zkktp.mint(att, _sign(newPk, att)); // signed by the new issuer, accepted
        assertTrue(zkktp.isVerified(user1));
    }

    function test_LockedRevertsForNonexistentToken() public {
        vm.expectRevert();
        zkktp.locked(999);
    }
}
