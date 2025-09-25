// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IPauserRegistry } from "eigenlayer-contracts/interfaces/IPauserRegistry.sol";
import { IEOFeedVerifier } from "./interfaces/IEOFeedVerifier.sol";
import { IEOFeedManager } from "./interfaces/IEOFeedManager.sol";
import {
    InvalidAddress,
    CallerIsNotWhitelisted,
    MissingLeafInputs,
    FeedNotSupported,
    InvalidInput,
    CallerIsNotPauser,
    CallerIsNotUnpauser,
    CallerIsNotFeedDeployer
} from "./interfaces/Errors.sol";

/**
 * @title EOFeedManager
 * @author eOracle
 * @notice The EOFeedManager contract is responsible for receiving feed updates from whitelisted publishers. These
 * updates are verified using the logic in the EOFeedVerifier. Upon successful verification, the feed data is stored in
 * the EOFeedManager and made available for other smart contracts to read. Only supported feed IDs can be published to
 * the feed manager.
 */
contract EOFeedManager is IEOFeedManager, OwnableUpgradeable, PausableUpgradeable {
    /// @dev Map of feed id to price feed (feed id => PriceFeed)
    mapping(uint256 => PriceFeed) internal _priceFeeds;

    /// @dev Map of whitelisted publishers (publisher => is whitelisted)
    mapping(address => bool) internal _whitelistedPublishers;

    /// @dev Map of supported feeds, (feed id => is supported)
    mapping(uint256 => bool) internal _supportedFeedIds;

    /// @dev feed verifier contract
    IEOFeedVerifier internal _feedVerifier;

    /// @notice Address of the `PauserRegistry` contract that this contract defers to for determining access control
    /// (for pausing).
    IPauserRegistry internal _pauserRegistry;

    /// @dev Address of the feed deployer
    address internal _feedDeployer;

    /* ============ Modifiers ============ */

    /// @dev Allows only whitelisted publishers to call the function
    modifier onlyWhitelisted() {
        if (!_whitelistedPublishers[msg.sender]) revert CallerIsNotWhitelisted(msg.sender);
        _;
    }

    /// @dev Allows only non-zero addresses
    modifier onlyNonZeroAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    modifier onlyPauser() {
        if (!_pauserRegistry.isPauser(msg.sender)) revert CallerIsNotPauser();
        _;
    }

    modifier onlyUnpauser() {
        if (msg.sender != _pauserRegistry.unpauser()) revert CallerIsNotUnpauser();
        _;
    }

    modifier onlyFeedDeployer() {
        if (msg.sender != _feedDeployer) revert CallerIsNotFeedDeployer();
        _;
    }

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /* ============ Initializer ============ */

    /**
     * @notice Initialize the contract with the feed verifier address
     * @dev The feed verifier contract must be deployed first
     * @param feedVerifier Address of the feed verifier contract
     * @param owner Owner of the contract
     * @param pauserRegistry Address of the pauser registry contract
     * @param feedDeployer Address of the feed deployer
     */
    function initialize(
        address feedVerifier,
        address owner,
        address pauserRegistry,
        address feedDeployer
    )
        external
        onlyNonZeroAddress(feedVerifier)
        onlyNonZeroAddress(feedDeployer)
        onlyNonZeroAddress(pauserRegistry)
        initializer
    {
        __Ownable_init(owner);
        __Pausable_init();
        _feedVerifier = IEOFeedVerifier(feedVerifier);
        _pauserRegistry = IPauserRegistry(pauserRegistry);
        _feedDeployer = feedDeployer;
    }

    /* ============ External Functions ============ */

    /**
     * @notice Set the feed verifier contract address
     * @param feedVerifier Address of the feed verifier contract
     */
    function setFeedVerifier(address feedVerifier) external onlyOwner onlyNonZeroAddress(feedVerifier) {
        _feedVerifier = IEOFeedVerifier(feedVerifier);
        emit FeedVerifierSet(feedVerifier);
    }

    /**
     * @notice Set the feed deployer
     * @param feedDeployer The feed deployer address
     */
    function setFeedDeployer(address feedDeployer) external onlyOwner onlyNonZeroAddress(feedDeployer) {
        _feedDeployer = feedDeployer;
        emit FeedDeployerSet(feedDeployer);
    }

    /**
     * @notice Reset timestamps for specified price feeds to zero
     * @dev This function can only be called by the contract owner
     * @dev Useful for emergency situations where you need to clear stale timestamp data
     * @param feedIds Array of feed IDs whose timestamps should be reset
     */
    function resetFeedTimestamps(uint256[] calldata feedIds) external onlyOwner {
        for (uint256 i = 0; i < feedIds.length; i++) {
            uint256 feedId = feedIds[i];
            if (!_supportedFeedIds[feedId]) {
                revert FeedNotSupported(feedId);
            }
            _priceFeeds[feedId].timestamp = 0;
        }
    }
    /**
     * @notice Set the supported feeds
     * @param feedIds Array of feed ids
     * @param isSupported Array of booleans indicating whether the feed is supported
     */

    function setSupportedFeeds(uint256[] calldata feedIds, bool[] calldata isSupported) external onlyOwner {
        if (feedIds.length != isSupported.length) revert InvalidInput();
        for (uint256 i = 0; i < feedIds.length; i++) {
            _supportedFeedIds[feedIds[i]] = isSupported[i];
            emit SupportedFeedsUpdated(feedIds[i], isSupported[i]);
        }
    }

    /**
     * @notice Add supported feeds
     * @param feedIds Array of feed ids
     */
    function addSupportedFeeds(uint256[] calldata feedIds) external onlyFeedDeployer {
        for (uint256 i = 0; i < feedIds.length; i++) {
            _supportedFeedIds[feedIds[i]] = true;
            emit SupportedFeedsUpdated(feedIds[i], true);
        }
    }

    /**
     * @inheritdoc IEOFeedManager
     */
    function whitelistPublishers(address[] calldata publishers, bool[] calldata isWhitelisted) external onlyOwner {
        if (publishers.length != isWhitelisted.length) revert InvalidInput();
        for (uint256 i = 0; i < publishers.length; i++) {
            if (publishers[i] == address(0)) revert InvalidAddress();
            _whitelistedPublishers[publishers[i]] = isWhitelisted[i];
            emit PublisherWhitelisted(publishers[i], isWhitelisted[i]);
        }
    }

    /**
     * @inheritdoc IEOFeedManager
     */
    // Reentrancy is not an issue because _feedVerifier is set by the owner
    // slither-disable-next-line reentrancy-benign,reentrancy-events
    function updateFeed(
        IEOFeedVerifier.LeafInput calldata input,
        IEOFeedVerifier.VerificationParams calldata vParams
    )
        external
        onlyWhitelisted
        whenNotPaused
    {
        bytes memory data = _feedVerifier.verify(input, vParams);
        _processVerifiedRate(data, vParams.blockNumber);
    }

    /**
     * @inheritdoc IEOFeedManager
     */
    // Reentrancy is not an issue because _feedVerifier is set by the owner
    // slither-disable-next-line reentrancy-benign,reentrancy-events
    function updateFeeds(
        IEOFeedVerifier.LeafInput[] calldata inputs,
        IEOFeedVerifier.VerificationParams calldata vParams
    )
        external
        onlyWhitelisted
        whenNotPaused
    {
        if (inputs.length == 0) revert MissingLeafInputs();

        bytes[] memory data = _feedVerifier.batchVerify(inputs, vParams);
        for (uint256 i = 0; i < data.length; i++) {
            _processVerifiedRate(data[i], vParams.blockNumber);
        }
    }

    /**
     * @notice Set the pauser registry contract address
     * @param pauserRegistry Address of the pauser registry contract
     */
    function setPauserRegistry(address pauserRegistry) external onlyOwner onlyNonZeroAddress(pauserRegistry) {
        _pauserRegistry = IPauserRegistry(pauserRegistry);
        emit PauserRegistrySet(pauserRegistry);
    }

    /**
     * @notice Pause the feed manager
     */
    function pause() external onlyPauser {
        _pause();
    }

    /**
     * @notice Unpause the feed manager
     */
    function unpause() external onlyUnpauser {
        _unpause();
    }

    /**
     * @inheritdoc IEOFeedManager
     */
    function getLatestPriceFeed(uint256 feedId) external view returns (PriceFeed memory) {
        return _getLatestPriceFeed(feedId);
    }

    /**
     * @inheritdoc IEOFeedManager
     */
    function getLatestPriceFeeds(uint256[] calldata feedIds) external view returns (PriceFeed[] memory) {
        PriceFeed[] memory retVal = new PriceFeed[](feedIds.length);
        for (uint256 i = 0; i < feedIds.length; i++) {
            retVal[i] = _getLatestPriceFeed(feedIds[i]);
        }
        return retVal;
    }

    /**
     * @inheritdoc IEOFeedManager
     */
    function isWhitelistedPublisher(address publisher) external view returns (bool) {
        return _whitelistedPublishers[publisher];
    }

    /**
     * @inheritdoc IEOFeedManager
     */
    function isSupportedFeed(uint256 feedId) external view returns (bool) {
        return _supportedFeedIds[feedId];
    }

    /**
     * @inheritdoc IEOFeedManager
     */
    function getFeedDeployer() external view returns (address) {
        return _feedDeployer;
    }

    /**
     * @inheritdoc IEOFeedManager
     */
    function getFeedVerifier() external view returns (IEOFeedVerifier) {
        return _feedVerifier;
    }

    /**
     * @inheritdoc IEOFeedManager
     */
    function getPauserRegistry() external view returns (IPauserRegistry) {
        return _pauserRegistry;
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Process the verified feed data, validate it and store it. If the timestamp is newer than the
     *  existing timestamp, updates the price feed and emits RateUpdated. Otherwise emits SymbolReplay without updating.
     * @param data verified feed data, abi encoded (uint256 feedId, uint256 rate, uint256 timestamp)
     * @param blockNumber eoracle chain block number
     */
    function _processVerifiedRate(bytes memory data, uint256 blockNumber) internal {
        (uint256 feedId, uint256 rate, uint256 timestamp) = abi.decode(data, (uint256, uint256, uint256));
        if (!_supportedFeedIds[feedId]) revert FeedNotSupported(feedId);
        if (_priceFeeds[feedId].timestamp < timestamp) {
            _priceFeeds[feedId] = PriceFeed(rate, timestamp, blockNumber);
            emit RateUpdated(feedId, rate, timestamp);
        } else {
            emit SymbolReplay(feedId, rate, timestamp, _priceFeeds[feedId].timestamp);
        }
    }

    /**
     * @notice Get the latest price feed
     * @param feedId Feed id
     * @return PriceFeed struct
     */
    function _getLatestPriceFeed(uint256 feedId) internal view returns (PriceFeed memory) {
        if (!_supportedFeedIds[feedId]) revert FeedNotSupported(feedId);
        return _priceFeeds[feedId];
    }

    /**
     * @dev Gap for future storage variables in upgradeable contract.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    // solhint-disable ordering
    // slither-disable-next-line unused-state,naming-convention
    uint256[48] private __gap;
    // solhint-disable enable
}
