// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { FeedVerifierDeployer } from "./base/DeployFeedVerifier.s.sol";
import { FeedManagerDeployer } from "./base/DeployFeedManager.s.sol";
import { EOFeedVerifier } from "src/EOFeedVerifier.sol";
import { EOFeedManager } from "src/EOFeedManager.sol";

/**
 * @title DeployQuickStart
 * @notice Deployment script that follows the QuickStart.t.sol pattern
 * @dev Deploys both FeedManager and FeedVerifier contracts and sets up the basic configuration
 */
contract DeployQuickStart is Script, FeedVerifierDeployer, FeedManagerDeployer {
    EOFeedManager public feedManager;
    EOFeedVerifier public feedVerifier;
    address public feedVerifierProxy;
    address public feedManagerProxy;

    function run() external {
        // Get private key from environment variable
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        
        vm.startBroadcast(privateKey);

        // Deploy contracts using the same pattern as QuickStart.t.sol
        (feedVerifierProxy, feedManagerProxy) = execute(deployer);

        // Set up the contracts
        feedVerifier = EOFeedVerifier(feedVerifierProxy);
        feedManager = EOFeedManager(feedManagerProxy);

        // Set the feed manager in the verifier
        feedVerifier.setFeedManager(feedManagerProxy);

        uint256[] memory feedIds = new uint256[](1);
        bool[] memory isSupported = new bool[](1);
        feedIds[0] = 0;
        isSupported[0] = true;
        feedManager.setSupportedFeeds(feedIds, isSupported);

        address[] memory publishers = new address[](1);
        publishers[0] = deployer;
        bool[] memory isWhitelisted = new bool[](1);
        isWhitelisted[0] = true;
        feedManager.whitelistPublishers(publishers, isWhitelisted);

        vm.stopBroadcast();

        // Log deployment information
        console2.log("=== Deployment Complete ===");
        console2.log("Feed Verifier Proxy:", feedVerifierProxy);
        console2.log("Feed Manager Proxy:", feedManagerProxy);
        console2.log("Deployer:", deployer);
    }

    /**
     * @notice Execute the deployment process
     * @param broadcastFrom The address to broadcast from (typically the deployer)
     * @return feedVerifierProxy The deployed feed verifier proxy address
     * @return feedManagerProxy The deployed feed manager proxy address
     */
    function execute(address broadcastFrom) public returns (address feedVerifierProxy, address feedManagerProxy) {
        // Deploy Feed Verifier
        feedVerifierProxy = deployFeedVerifier(broadcastFrom, broadcastFrom);

        // Deploy Feed Manager
        feedManagerProxy = deployFeedManager(
            broadcastFrom, // proxyAdmin
            feedVerifierProxy, // feedVerifier
            broadcastFrom, // owner
            broadcastFrom, // pauserRegistry
            broadcastFrom // feedDeployer
        );

        // Set the feed manager in the verifier
        EOFeedVerifier(feedVerifierProxy).setFeedManager(feedManagerProxy);
    }
}
