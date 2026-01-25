// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../lib/forge-std/src/Script.sol";
import "../contracts/BlueRailroadTrainV2.sol";

/**
 * @title DeployBlueRailroadV2Script
 * @notice Deploys BlueRailroadTrainV2 contract to Optimism
 * @dev Run with:
 *      forge script scripts/DeployBlueRailroadV2.s.sol --rpc-url $OPTIMISM_RPC --broadcast --verify
 *
 * Environment variables:
 *   PRIVATE_KEY - Deployer private key
 *   V1_CONTRACT - Address of the V1 Blue Railroad contract (default: 0xCe09A2d0d0BDE635722D8EF31901b430E651dB52)
 *
 * After deployment:
 * 1. V1 holders approve the V2 contract to transfer their V1 tokens
 * 2. V1 holders call migrateFromV1() with corrected metadata:
 *    - Use blockheight instead of date
 *    - Use correct songId (7 for Squats, not 5)
 *    - Use IPFS URIs (not Discord links)
 * 3. Owner can also mint new tokens via issueTony() for new exercises
 */
contract DeployBlueRailroadV2Script is Script {
    // V1 contract address on Optimism
    address constant DEFAULT_V1_CONTRACT = 0xCe09A2d0d0BDE635722D8EF31901b430E651dB52;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Allow overriding V1 contract address for testing
        address v1Contract = vm.envOr("V1_CONTRACT", DEFAULT_V1_CONTRACT);

        vm.startBroadcast(deployerPrivateKey);

        address initialOwner = vm.addr(deployerPrivateKey);

        BlueRailroadTrainV2 blueRailroad = new BlueRailroadTrainV2(initialOwner, v1Contract);
        console.log("BlueRailroadTrainV2 deployed to:", address(blueRailroad));
        console.log("Owner:", initialOwner);
        console.log("V1 Contract:", v1Contract);

        vm.stopBroadcast();
    }
}
