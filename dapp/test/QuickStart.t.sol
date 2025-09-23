// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { FeedVerifierDeployer } from "../script/deployment/base/DeployFeedVerifier.s.sol";
import { FeedManagerDeployer } from "../script/deployment/base/DeployFeedManager.s.sol";
import { EOFeedVerifier } from "src/EOFeedVerifier.sol";
import { EOFeedManager } from "src/EOFeedManager.sol";
import { IEOFeedManager } from "src/interfaces/IEOFeedManager.sol";
import { IEOFeedVerifier } from "src/interfaces/IEOFeedVerifier.sol";

// Deployment command: FOUNDRY_PROFILE="deployment" forge script script/deployment/DeployNewTargetContractSet.s.sol
// --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY -vvv --slow --verify --broadcast
contract QuickStartTest is Test, FeedVerifierDeployer, FeedManagerDeployer {
    EOFeedManager public feedManager;
    EOFeedVerifier public feedVerifier;
    address public publisher;
    address public owner;

    function setUp() public {
        // Set up test accounts - use same address for owner and publisher
        owner = address(this);
        publisher = address(this);

        // Deploy contracts
        address feedVerifierProxy;
        address feedManagerProxy;
        (feedVerifierProxy, feedManagerProxy) = execute(owner);

        feedVerifier = EOFeedVerifier(feedVerifierProxy);
        feedManager = EOFeedManager(feedManagerProxy);

        // Whitelist the publisher (same as owner)
        address[] memory publishers = new address[](1);
        bool[] memory isWhitelisted = new bool[](1);
        publishers[0] = publisher;
        isWhitelisted[0] = true;
        feedManager.whitelistPublishers(publishers, isWhitelisted);
    }

    function test_createAndUpdateFeed() public {
        // Test parameters
        uint256 feedId = 0;
        uint256 rate1 = 1200e18; // First rate: 1000 with 18 decimals
        uint256 timestamp1 = block.timestamp;

        // Create leaf input data for first update (feedId, rate, timestamp)
        bytes memory unhashedLeaf1 = abi.encode(feedId, rate1, timestamp1);

        // Create a simple merkle proof (empty for testing since validation is removed)
        bytes32[] memory proof = new bytes32[](0);

        // Create leaf input for first update
        IEOFeedVerifier.LeafInput memory leafInput1 =
            IEOFeedVerifier.LeafInput({ leafIndex: 0, unhashedLeaf: unhashedLeaf1, proof: proof });

        // Create verification parameters (simplified for testing)
        IEOFeedVerifier.VerificationParams memory vParams = IEOFeedVerifier.VerificationParams({
            eventRoot: keccak256("test"),
            blockNumber: uint64(block.number),
            chainId: uint32(block.chainid),
            aggregator: publisher,
            blockHash: blockhash(block.number - 1),
            signature: [uint256(0), uint256(0)], // Empty signature for testing
            apkG2: [uint256(0), uint256(0), uint256(0), uint256(0)], // Empty apk for testing
            nonSignersBitmap: new bytes(0)
        });

        // Add the feed as supported
        uint256[] memory feedIds = new uint256[](1);
        bool[] memory isSupported = new bool[](1);
        feedIds[0] = feedId;
        isSupported[0] = true;
        feedManager.setSupportedFeeds(feedIds, isSupported);

        // Verify the feed is supported
        assertTrue(feedManager.isSupportedFeed(feedId), "Feed should be supported");

        // Verify the publisher is whitelisted
        assertTrue(feedManager.isWhitelistedPublisher(publisher), "Publisher should be whitelisted");

        // First update: Update the feed (no vm.prank needed since publisher == owner)
        feedManager.updateFeed(leafInput1, vParams);

        // Get the latest price feed after first update
        IEOFeedManager.PriceFeed memory priceFeed1 = feedManager.getLatestPriceFeed(feedId);

        // Verify the first feed data
        console.log("First feed value", priceFeed1.value);
        console.log("First feed timestamp", priceFeed1.timestamp);
        console.log("First eoracle block number", priceFeed1.eoracleBlockNumber);
        assertEq(priceFeed1.value, rate1, "First feed value should match");
        assertEq(priceFeed1.timestamp, timestamp1, "First feed timestamp should match");
        assertEq(priceFeed1.eoracleBlockNumber, vParams.blockNumber, "First eoracle block number should match");

        // Second update: Test updating with a new rate
        uint256 rate2 = 2400e18;
        uint256 timestamp2 = timestamp1 + 1;
        bytes memory unhashedLeaf2 = abi.encode(feedId, rate2, timestamp2);

        IEOFeedVerifier.LeafInput memory leafInput2 =
            IEOFeedVerifier.LeafInput({ leafIndex: 0, unhashedLeaf: unhashedLeaf2, proof: proof });

        // Update the feed again (no vm.prank needed since publisher == owner)
        feedManager.updateFeed(leafInput2, vParams);

        // Get the updated price feed after second update
        IEOFeedManager.PriceFeed memory priceFeed2 = feedManager.getLatestPriceFeed(feedId);

        // Verify the second feed data
        assertEq(priceFeed2.value, rate2, "Second feed value should match");
        assertEq(priceFeed2.timestamp, timestamp2, "Second feed timestamp should match");
        assertEq(priceFeed2.eoracleBlockNumber, vParams.blockNumber, "Second eoracle block number should match");

        // Verify that the second update overwrote the first
        assertTrue(priceFeed2.timestamp > priceFeed1.timestamp, "Second timestamp should be greater than first");
        assertTrue(priceFeed2.value != priceFeed1.value, "Second value should be different from first");
    }

    function run() external {
        vm.startBroadcast();
        execute(msg.sender);
        vm.stopBroadcast();
    }

    // for testing purposes
    function run(address broadcastFrom) public returns (address feedVerifierProxy, address feedManagerProxy) {
        vm.startBroadcast(broadcastFrom);
        (feedVerifierProxy, feedManagerProxy) = execute(broadcastFrom);
        vm.stopBroadcast();
    }

    function execute(address broadcastFrom) public returns (address feedVerifierProxy, address feedManagerProxy) {
        feedVerifierProxy = deployFeedVerifier(broadcastFrom, broadcastFrom);
        feedManagerProxy =
            deployFeedManager(broadcastFrom, feedVerifierProxy, broadcastFrom, broadcastFrom, broadcastFrom);
        EOFeedVerifier(feedVerifierProxy).setFeedManager(feedManagerProxy);
    }
}
