// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IEOFeedManager } from "../interfaces/IEOFeedManager.sol";
import { IEOFeedAdapter } from "./interfaces/IEOFeedAdapter.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { InvalidAddress } from "../interfaces/Errors.sol";

/**
 * @title EOFeedAdapter
 * @author eOracle
 * @notice EOFeedAdapter is a contract that provides a standardized interface for accessing feed data
 * from the eOracle system. It acts as a compatibility layer between eOracle's native feed format and
 * the widely-used AggregatorV3Interface format.
 * @dev compatible with AggregatorV3Interface.
 */
contract EOFeedAdapter is IEOFeedAdapter, Initializable {
    /// @dev Feed manager contract
    IEOFeedManager private _feedManager;

    /// @dev Feed version
    uint256 private _version;

    /// @dev Feed description
    string private _description;

    /// @dev Feed id
    uint256 private _feedId;

    /// @dev the next 2 variables will be packed in 1 slot

    /// @dev The input decimals of the rate
    uint8 private _inputDecimals;

    /// @dev The output decimals of the rate
    uint8 private _outputDecimals;

    /// @dev The decimals difference between input and output decimals
    int256 private _decimalsDiff;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /* ============ Initializer ============ */

    /**
     * @notice Initialize the contract
     * @param feedManager The feed manager address
     * @param feedId Feed id
     * @param inputDecimals The input decimal precision of the rate
     * @param outputDecimals The output decimal precision of the rate
     * @param feedDescription The description of feed
     * @param feedVersion The version of feed
     */
    function initialize(
        address feedManager,
        uint256 feedId,
        uint8 inputDecimals,
        uint8 outputDecimals,
        string memory feedDescription,
        uint256 feedVersion
    )
        external
        initializer
    {
        if (feedManager == address(0)) revert InvalidAddress();
        _feedManager = IEOFeedManager(feedManager);
        _feedId = feedId;
        _outputDecimals = outputDecimals;
        _inputDecimals = inputDecimals;
        uint256 diff = inputDecimals > outputDecimals ? inputDecimals - outputDecimals : outputDecimals - inputDecimals;
        _decimalsDiff = int256(10 ** diff); // casted to int256 to conform with the adapter interface return type
        _description = feedDescription;
        _version = feedVersion;
    }

    /* ============ External Functions ============ */

    /**
     * @notice Get the price for the round
     * @param roundId The roundId - is ignored, only latest round is supported
     * @return roundId The latest round id
     * @return answer The price
     * @return startedAt The timestamp of the start of the round
     * @return updatedAt The timestamp of the end of the round
     * @return answeredInRound The round id in which the answer was computed
     */
    // solhint-disable-next-line no-unused-vars
    function getRoundData(uint80 roundId) external view returns (uint80, int256, uint256, uint256, uint80) {
        IEOFeedManager.PriceFeed memory priceData = _feedManager.getLatestPriceFeed(_feedId);
        return (
            uint80(priceData.eoracleBlockNumber),
            _normalizePrice(priceData.value),
            priceData.timestamp,
            priceData.timestamp,
            uint80(priceData.eoracleBlockNumber)
        );
    }

    /**
     * @notice Get the latest price
     * @return roundId The round id
     * @return answer The price
     * @return startedAt The timestamp of the start of the round
     * @return updatedAt The timestamp of the end of the round
     * @return answeredInRound The round id in which the answer was computed
     */
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        IEOFeedManager.PriceFeed memory priceData = _feedManager.getLatestPriceFeed(_feedId);
        return (
            uint80(priceData.eoracleBlockNumber),
            _normalizePrice(priceData.value),
            priceData.timestamp,
            priceData.timestamp,
            uint80(priceData.eoracleBlockNumber)
        );
    }

    /**
     * @notice Get the latest price
     * @return int256 The price
     */
    function latestAnswer() external view returns (int256) {
        IEOFeedManager.PriceFeed memory priceData = _feedManager.getLatestPriceFeed(_feedId);
        return _normalizePrice(priceData.value);
    }

    /**
     * @notice Get the latest timestamp
     * @return uint256 The timestamp
     */
    function latestTimestamp() external view returns (uint256) {
        IEOFeedManager.PriceFeed memory priceData = _feedManager.getLatestPriceFeed(_feedId);
        return priceData.timestamp;
    }

    /**
     * @notice Get the price for the round
     * @param roundId The roundId - is ignored, only latest round is supported
     * @return int256 The price
     */
    // solhint-disable-next-line no-unused-vars
    function getAnswer(uint256 roundId) external view returns (int256) {
        IEOFeedManager.PriceFeed memory priceData = _feedManager.getLatestPriceFeed(_feedId);
        return _normalizePrice(priceData.value);
    }

    /**
     * @notice Get the timestamp for the round
     * @param roundId The roundId - is ignored, only latest round is supported
     * @return uint256 The timestamp
     */
    // solhint-disable-next-line no-unused-vars
    function getTimestamp(uint256 roundId) external view returns (uint256) {
        IEOFeedManager.PriceFeed memory priceData = _feedManager.getLatestPriceFeed(_feedId);
        return priceData.timestamp;
    }

    /**
     * @notice Get the id of the feed
     * @return uint256 The feed id
     */
    function getFeedId() external view returns (uint256) {
        return _feedId;
    }

    /**
     * @notice Get the decimals of the rate
     * @return uint8 The decimals
     */
    function decimals() external view returns (uint8) {
        return _outputDecimals;
    }

    /**
     * @notice Get the description of the feed
     * @return string The description
     */
    function description() external view returns (string memory) {
        return _description;
    }

    /**
     * @notice Get the version of the feed
     * @return uint256 The version
     */
    function version() external view returns (uint256) {
        return _version;
    }

    /**
     * @notice Get the latest round
     * @return uint256 The round id, eoracle block number
     */
    function latestRound() external view returns (uint256) {
        IEOFeedManager.PriceFeed memory priceData = _feedManager.getLatestPriceFeed(_feedId);
        return priceData.eoracleBlockNumber;
    }

    /**
     * @notice Get the paused status of the feed
     * @return bool The paused status
     */
    function isPaused() external view returns (bool) {
        return PausableUpgradeable(address(_feedManager)).paused();
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Normalize the price to the output decimals
     * @param price The price to normalize
     * @return int256 The normalized price
     */
    function _normalizePrice(uint256 price) internal view returns (int256) {
        if (_inputDecimals > _outputDecimals) {
            return int256(price) / _decimalsDiff;
        } else {
            return int256(price) * _decimalsDiff;
        }
    }

    /**
     * @dev Gap for future storage variables in upgradeable contract.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    // solhint-disable ordering
    // slither-disable-next-line unused-state,naming-convention
    uint256[48] private __gap;
    // solhint-disable ordering
}
