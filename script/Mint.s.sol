// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ZkKTPSoulbound} from "../contracts/ZkKTPSoulbound.sol";

contract Mint is Script {
    bytes32 constant ATTESTATION_TYPEHASH =
        keccak256("Attestation(address subject,bytes32 nullifier,uint256 expiry)");
    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function run() external {
        address contractAddr = vm.envAddress("CONTRACT_ADDRESS");
        uint256 issuerPk = vm.envUint("ISSUER_PRIVATE_KEY");
        uint256 subjectPk = vm.envUint("PRIVATE_KEY");
        string memory nik = vm.envOr("NIK", string("3374010101900001"));

        address subject = vm.addr(subjectPk);
        bytes32 nullifier = keccak256(abi.encodePacked(nik));
        uint256 expiry = block.timestamp + 1 days;

        ZkKTPSoulbound zkktp = ZkKTPSoulbound(contractAddr);

        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("zkKTP")),
                keccak256(bytes("1")),
                block.chainid,
                contractAddr
            )
        );
        bytes32 structHash = keccak256(abi.encode(ATTESTATION_TYPEHASH, subject, nullifier, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        ZkKTPSoulbound.Attestation memory att = ZkKTPSoulbound.Attestation({
            subject: subject,
            nullifier: nullifier,
            expiry: expiry
        });

        vm.startBroadcast(subjectPk);
        uint256 tokenId = zkktp.mint(att, signature);
        vm.stopBroadcast();

        console2.log("Minted tokenId:", tokenId);
        console2.log("Holder (subject):", subject);
        console2.log("isVerified:", zkktp.isVerified(subject));
    }
}
