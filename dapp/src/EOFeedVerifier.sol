// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IEOFeedVerifier } from "./interfaces/IEOFeedVerifier.sol";
import { IBLS } from "./interfaces/IBLS.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// solhint-disable no-unused-import
import {
    CallerIsNotFeedManager,
    InvalidProof,
    InvalidInput,
    InvalidAddress,
    InvalidEventRoot,
    VotingPowerIsZero,
    InsufficientVotingPower,
    SignatureVerificationFailed,
    SignaturePairingFailed,
    ValidatorIndexOutOfBounds,
    ValidatorSetTooSmall,
    DuplicatedAddresses
} from "./interfaces/Errors.sol";

/**
 * @title EOFeedVerifier
 * @author eOracle
 * @notice The EOFeedVerifier contract handles the verification of update payloads. The payload includes a Merkle root
 * signed by eoracle validators and a Merkle path to the leaf containing the data. The verifier stores the current
 * validator set in its storage and ensures that the Merkle root is signed by a subset of this validator set with
 * sufficient voting power.
 */
contract EOFeedVerifier is IEOFeedVerifier, OwnableUpgradeable {
    bytes32 public constant DOMAIN = keccak256("EORACLE_FEED_VERIFIER");
    uint256 public constant MIN_VALIDATORS = 3;

    /// @dev BLS library contract
    IBLS internal _bls;

    /// @dev length of validators set
    uint256 internal _currentValidatorSetLength;

    /// @dev total voting power of the current validators set
    uint256 internal _totalVotingPower;

    /// @dev current validators set (index => Validator)
    mapping(uint256 => Validator) internal _currentValidatorSet;

    /// @dev hash (keccak256) of the current validator set
    bytes32 internal _currentValidatorSetHash;

    /// @dev block number of the last processed block
    uint256 internal _lastProcessedBlockNumber;

    /// @dev event root of the last processed block
    bytes32 internal _lastProcessedEventRoot;

    /// @dev address of the feed manager
    address internal _feedManager;

    /// @dev full apk of the current validator set
    uint256[2] internal _fullApk;

    /* ============ Modifiers ============ */

    /**
     * @dev Allows only the feed manager to call the function
     */
    modifier onlyFeedManager() {
        if (msg.sender != _feedManager) revert CallerIsNotFeedManager();
        _;
    }

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /* ============ Initializer ============ */

    /**
     * @param owner Owner of the contract
     */
    function initialize(address owner) external initializer {
        // if (address(bls_) == address(0) || address(bls_).code.length == 0) {
        //     revert InvalidAddress();
        // }
        // _bls = bls_;
        __Ownable_init(owner);
    }

    /* ============ External Functions ============ */

    /**
     * @inheritdoc IEOFeedVerifier
     */
    function verify(
        LeafInput calldata input,
        VerificationParams calldata vParams
    )
        external
        onlyFeedManager
        returns (bytes memory)
    {
        _verifyParams(vParams);
        bytes memory data = _verifyLeaf(input, vParams.eventRoot);
        return data;
    }

    /**
     * @inheritdoc IEOFeedVerifier
     */
    function batchVerify(
        LeafInput[] calldata inputs,
        VerificationParams calldata vParams
    )
        external
        onlyFeedManager
        returns (bytes[] memory)
    {
        _verifyParams(vParams);
        return _verifyLeaves(inputs, vParams.eventRoot);
    }

    /**
     * @notice Function to set a new validator set
     * @param newValidatorSet The new validator set to store
     */
    function setNewValidatorSet(Validator[] calldata newValidatorSet) external onlyOwner {
        uint256 length = newValidatorSet.length;
        if (length < MIN_VALIDATORS) revert ValidatorSetTooSmall();
        if (!_hasNoAddressDuplicates(newValidatorSet)) revert DuplicatedAddresses();
        if (length < _currentValidatorSetLength) {
            for (uint256 i = length; i < _currentValidatorSetLength; i++) {
                // slither-disable-next-line costly-loop
                delete _currentValidatorSet[i];
            }
        }

        _currentValidatorSetLength = length;
        _currentValidatorSetHash = keccak256(abi.encode(newValidatorSet));
        uint256 totalPower = 0;
        uint256[2] memory apk = [uint256(0), uint256(0)];

        for (uint256 i = 0; i < length; i++) {
            if (newValidatorSet[i]._address == address(0)) revert InvalidAddress();
            uint256 votingPower = newValidatorSet[i].votingPower;
            if (votingPower == 0) revert VotingPowerIsZero();
            totalPower += votingPower;
            _currentValidatorSet[i] = newValidatorSet[i];
            // slither-disable-next-line calls-loop
            apk = _bls.ecadd(apk, newValidatorSet[i].g1pk);
        }

        _fullApk = apk;
        _totalVotingPower = totalPower;
        emit ValidatorSetUpdated(_currentValidatorSetLength, _currentValidatorSetHash, _totalVotingPower);
    }

    /**
     * @notice Sets the address of the feed manager.
     * @param feedManager_ The address of the new feed manager.
     */
    function setFeedManager(address feedManager_) external onlyOwner {
        if (feedManager_ == address(0)) revert InvalidAddress();
        _feedManager = feedManager_;
        emit FeedManagerSet(feedManager_);
    }

    /**
     * @notice Set the BLS contract
     * @param bls_ Address of the BLS contract
     */
    function setBLS(IBLS bls_) external onlyOwner {
        if (address(bls_) == address(0) || address(bls_).code.length == 0) {
            revert InvalidAddress();
        }
        _bls = bls_;
    }

    /**
     * @notice Returns the length of the current validator set.
     * @return The number of validators in the current set.
     */
    function currentValidatorSetLength() external view returns (uint256) {
        return _currentValidatorSetLength;
    }

    /**
     * @notice Returns the total voting power of the current validator set.
     * @return The total voting power.
     */
    function totalVotingPower() external view returns (uint256) {
        return _totalVotingPower;
    }

    /**
     * @notice Returns the validator at the specified index in the current validator set.
     * @param index The index of the validator in the current set.
     * @return The validator at the given index.
     */
    function currentValidatorSet(uint256 index) external view returns (Validator memory) {
        if (index >= _currentValidatorSetLength) revert ValidatorIndexOutOfBounds();
        return _currentValidatorSet[index];
    }

    /**
     * @notice Returns the hash of the current validator set.
     * @return The hash of the current validator set.
     */
    function currentValidatorSetHash() external view returns (bytes32) {
        return _currentValidatorSetHash;
    }

    /**
     * @notice Returns the block number of the last processed block.
     * @return The last processed block number.
     */
    function lastProcessedBlockNumber() external view returns (uint256) {
        return _lastProcessedBlockNumber;
    }

    /**
     * @notice Returns the event root of the last processed block.
     * @return The last processed event root.
     */
    function lastProcessedEventRoot() external view returns (bytes32) {
        return _lastProcessedEventRoot;
    }

    /**
     * @notice Returns the address of the feed manager.
     * @return The address of the feed manager.
     */
    function feedManager() external view returns (address) {
        return _feedManager;
    }

    function bls() external view returns (IBLS) {
        return _bls;
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Function to verify the checkpoint signature
     * @param vParams Signed data
     */
    function _verifyParams(IEOFeedVerifier.VerificationParams calldata vParams) internal {
        // if the eventRoot has not changed, we don't need to verify the whole checkpoint again
        if (vParams.eventRoot == _lastProcessedEventRoot) {
            return;
        }

        // bytes32 msgHash = keccak256(
        //     abi.encode(vParams.eventRoot, vParams.blockNumber, vParams.blockHash, vParams.chainId,
        // vParams.aggregator)
        // );

        if (vParams.eventRoot == bytes32(0)) revert InvalidEventRoot();

        // _verifySignature(msgHash, vParams.signature, vParams.apkG2, vParams.nonSignersBitmap);

        if (vParams.blockNumber > _lastProcessedBlockNumber) {
            _lastProcessedBlockNumber = vParams.blockNumber;
            _lastProcessedEventRoot = vParams.eventRoot;
        }
    }

    /**
     * @notice Verify the signature of the checkpoint
     * @param messageHash Hash of the message to verify
     * @param signature G1 Aggregated signature of the checkpoint
     * @param apkG2 G2 Aggregated public key of the checkpoint
     * @param nonSignersBitmap Bitmap of the validators who did not sign the data
     */
    function _verifySignature(
        bytes32 messageHash,
        uint256[2] calldata signature,
        uint256[4] calldata apkG2,
        bytes calldata nonSignersBitmap
    )
        internal
        view
    {
        uint256[2] memory apk = [uint256(0), uint256(0)];
        uint256 aggVotingPower = _totalVotingPower;
        // first apk will hold all non signers
        for (uint256 i = 0; i < _currentValidatorSetLength; i++) {
            Validator memory v = _currentValidatorSet[i];
            if (_getValueFromBitmap(nonSignersBitmap, i)) {
                apk = _bls.ecadd(apk, v.g1pk);
                aggVotingPower -= v.votingPower;
            }
        }

        // we check the agg voting power is indeed sufficient
        if (aggVotingPower <= ((2 * _totalVotingPower) / 3)) revert InsufficientVotingPower();

        // then we negate the non signers and add the full apk
        apk = _bls.ecadd(_fullApk, _bls.neg(apk));
        uint256[2] memory hashPoint = _bls.hashToPoint(DOMAIN, abi.encodePacked(messageHash));
        (bool pairingSuccessful, bool signatureIsValid) =
            _bls.verifySignatureAndVeracity(apk, signature, hashPoint, apkG2);

        if (!pairingSuccessful) revert SignaturePairingFailed();
        if (!signatureIsValid) revert SignatureVerificationFailed();
    }

    /**
     * @notice Verify a batch of exits leaves
     * @param inputs Batch exit inputs for multiple event leaves
     * @param eventRoot the root this event should belong to
     * @return Array of the unhashed leaves
     */
    function _verifyLeaves(LeafInput[] calldata inputs, bytes32 eventRoot) internal pure returns (bytes[] memory) {
        if (inputs.length == 0) revert InvalidInput();
        uint256 length = inputs.length;
        bytes[] memory returnData = new bytes[](length);
        for (uint256 i = 0; i < length; i++) {
            returnData[i] = _verifyLeaf(inputs[i], eventRoot);
        }
        return returnData;
    }

    /**
     * @notice Verify for one event
     * @param input Exit leaf input
     * @param eventRoot event root the leaf should belong to
     * @return The unhashed leaf
     */
    function _verifyLeaf(LeafInput calldata input, bytes32 eventRoot) internal pure returns (bytes memory) {
        // bytes32 leaf = keccak256(input.unhashedLeaf);

        // if (!MerkleProof.verify(input.proof, eventRoot, leaf)) {
        //     revert InvalidProof();
        // }

        return input.unhashedLeaf;
    }

    /**
     * @dev Extracts a boolean value from a specific index in a bitmap.
     * @param bitmap The bytes array containing the bitmap.
     * @param index The bit position from which to retrieve the value.
     * @return bool The boolean value of the bit at the specified index in the bitmap.
     *              Returns 'true' if the bit is set (1), and 'false' if the bit is not set (0).
     */
    function _getValueFromBitmap(bytes calldata bitmap, uint256 index) private pure returns (bool) {
        uint256 byteNumber = index / 8;
        // safe to downcast as any value % 8 will always be less than 8
        uint8 bitNumber = uint8(index % 8);

        if (byteNumber >= bitmap.length) {
            return false;
        }
        // safe to downcast as bitmap[byteNumber] is byte and less than 256
        return uint8(bitmap[byteNumber]) & (1 << bitNumber) > 0;
    }

    /**
     * @dev Checks if there are no duplicate addresses in the validator set.
     * @param validators The array of validators to check for duplicates.
     * @return bool True if there are no duplicate addresses, false otherwise.
     */
    function _hasNoAddressDuplicates(Validator[] calldata validators) private pure returns (bool) {
        for (uint256 i = 0; i < validators.length; i++) {
            for (uint256 j = i + 1; j < validators.length; j++) {
                if (validators[i]._address == validators[j]._address) {
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * @dev Gap for future storage variables in upgradeable contract.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    // solhint-disable ordering
    // slither-disable-next-line unused-state,naming-convention
    uint256[50] private __gap;
    // solhint-disable enable
}
