// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ZkKTPSoulbound} from "../contracts/ZkKTPSoulbound.sol";

/// @notice Deploys ZkKTPSoulbound with the trusted issuer address.
/// Env required:
///   PRIVATE_KEY     deployer key (testnet only — never a mainnet key)
///   ISSUER_ADDRESS  address whose signatures the contract will accept
///
/// Run:
///   forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
contract Deploy is Script {
    function run() external returns (ZkKTPSoulbound zkktp) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address issuer = vm.envAddress("ISSUER_ADDRESS");

        vm.startBroadcast(deployerPk);
        zkktp = new ZkKTPSoulbound(issuer);
        vm.stopBroadcast();

        console2.log("ZkKTPSoulbound deployed at:", address(zkktp));
        console2.log("Trusted issuer:", issuer);
    }
}
