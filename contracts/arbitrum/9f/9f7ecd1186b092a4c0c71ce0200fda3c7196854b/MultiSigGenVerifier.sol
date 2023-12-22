// SPDX-License-Identifier: Business Source License 1.1
pragma solidity 0.8.18;

import "./EnumerableSet.sol";

/**
 * @title MultiSigGenVerifier
 * @author Franklin Templeton
 * @notice The multi-signature contract used to secure transactions
 *         for the tokenized fund
 */
contract MultiSigGenVerifier {
    using EnumerableSet for EnumerableSet.AddressSet;

    enum Threshold {
        HIGH,
        NORMAL
    }

    /// @dev This is emitted when a multi-sig transaction is executed
    event TransactionExecuted(
        address indexed destination,
        bytes indexed result
    );

    /// @dev This is emitted when a new submitter is added to the multi-sig
    event SubmitterAdded(address indexed submitter);
    /// @dev This is emitted when a submitter is removed from the multi-sig
    event SubmitterRemoved(address indexed submitter);
    /// @dev This is emitted when a new signer is added to the multi-sig
    event SignerAdded(address indexed signer);
    /// @dev This is emitted when a signer is removed from the multi-sig
    event SignerRemoved(address indexed signer);
    /// @dev This is emitted when the multi-sig Threshold.NORMAL is updated
    event NormalThresholdUpdated(uint256 indexed normal);
    /// @dev This is emitted when the multi-sig Threshold.HIGH is updated
    event HighThresholdUpdated(uint256 indexed high);
    /// @dev This is emitted when both multi-sig thresholds are updated
    event ThresholdsUpdated(uint256 indexed normal, uint256 indexed high);

    /// @dev the maximum number of signers that can be added for multi-sig validation
    uint256 public constant MAX_SIGNERS = 50;
    /// @dev the maximum number of valid submitters allowed to send transaction from the multi-sig
    uint256 public constant MAX_SUBMITTERS = 50;
    /// @dev the maximum value for a threshold
    uint256 public constant MAX_THRESHOLD = 255;
    /// @dev nonces to protect against replay attacks
    uint256 private globalNonce;
    mapping(address => uint256) private accountNonces;

    mapping(Threshold => uint256) private thresholdMap;
    mapping(address => uint256) private signersMap;
    EnumerableSet.AddressSet private signersSet;
    EnumerableSet.AddressSet private submittersSet;

    modifier onlySubmitter() {
        require(submittersSet.contains(msg.sender), "INVALID_CALLER");
        _;
    }

    modifier onlyVerifier() {
        require(msg.sender == address(this), "INVALID_CALLER");
        _;
    }

    modifier onlyWithinArrayBounds(
        uint256 signersArrayLength,
        uint256 weightsArrayLength
    ) {
        require(
            signersArrayLength > 0 && signersArrayLength <= MAX_SIGNERS,
            "INVALID_ARRAY_LENGTH"
        );
        require(
            signersArrayLength == weightsArrayLength,
            "ARRAY_SIZE_MISMATCH"
        );
        _;
    }

    /// @notice constructor
    constructor(
        address[2] memory submitters,
        address[] memory signers,
        uint256[] memory weights,
        uint256 _highThreshold,
        uint256 _normalThreshold
    ) onlyWithinArrayBounds(signers.length, weights.length) {
        require(_highThreshold > _normalThreshold, "INVALID_THRESHOLD");
        thresholdMap[Threshold.HIGH] = _highThreshold;
        thresholdMap[Threshold.NORMAL] = _normalThreshold;
        submittersSet.add(submitters[0]);
        submittersSet.add(submitters[1]);

        for (uint256 i = 0; i < signers.length; i++) {
            require(weights[i] > 0, "INVALID_WEIGHT");
            _setupSigner(signers[i], weights[i]);
        }
        require(
            _isAvailableThresholdEnough(_highThreshold),
            "INSUFICIENT_THRESHOLD_AVAILABLE"
        );
    }

    /**
     * @notice The entry function for the multi-sig contract
     *
     * @param account The account associated with the signed request
     * @param target The target smart contract from which to execute the encoded function in the payload
     * @param payload The encoded target function and parameters to be executed after signature valiation
     * @param signatures The byte-array of signatures to validate
     *
     * @dev This contract defines 2 types of thresholds: Threshold.HIGH and Threshold.NORMAL
     *      Function calls that modify the state of this multi-sig contract require HIGH threshold
     *      and calls to any other target contract controled by this multi-sig require NORMAL threshold
     *
     * @dev Every valid signer has an associated weight that will contribute to the final threshold acquired
     *
     */
    function signedDataExecution(
        address account,
        address target,
        bytes memory payload,
        bytes memory signatures
    ) external onlySubmitter {
        require(target.code.length > 0, "INVALID_TARGET_TYPE");
        uint256 signaturesCount = signatures.length / 65;
        uint256 acquiredThreshold;
        bytes32 hash;
        bytes32 r;
        bytes32 s;
        uint8 v;

        if (account == address(0)) {
            hash = _getHash(account, target, payload, globalNonce);
            globalNonce = globalNonce + 1;
        } else {
            hash = _getHash(account, target, payload, accountNonces[account]);
            accountNonces[account] = accountNonces[account] + 1;
        }

        address lastRecoveredSigner;

        for (uint256 i = 0; i < signaturesCount; i++) {
            (v, r, s) = _splitSignature(signatures, i);
            address signerRecovered = ecrecover(hash, v, r, s);

            if (signersSet.contains(signerRecovered)) {
                if (lastRecoveredSigner != address(0)) {
                    require(
                        signerRecovered > lastRecoveredSigner,
                        "INVALID_SIGNATURE_ORDER"
                    );
                }
                lastRecoveredSigner = signerRecovered;
                acquiredThreshold += signersMap[signerRecovered];

                if (acquiredThreshold >= _getRequiredThreshold(target)) {
                    break;
                }
            }
        }

        // Wallet logic
        if (acquiredThreshold < _getRequiredThreshold(target)) {
            revert("INSUFICIENT_THRESHOLD_ACQUIRED");
        }

        (bool success, bytes memory result) = target.call{value: 0}(payload);

        emit TransactionExecuted(target, result);

        if (!success) {
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }
    }

    // -------------------------------------------------- //

    function addSubmitters(address[] memory submitters) public onlyVerifier {
        require(submitters.length <= MAX_SUBMITTERS, "INVALID_ARRAY_LENGTH");
        require(
            submitters.length + submittersSet.length() <= MAX_SUBMITTERS,
            "INVALID_SUBMITTER_COUNT"
        );
        for (uint256 i = 0; i < submitters.length; i++) {
            submittersSet.add(submitters[i]);
            emit SubmitterAdded(submitters[i]);
        }
    }

    function removeSubmitters(address[] memory submitters) public onlyVerifier {
        require(submitters.length <= MAX_SUBMITTERS, "INVALID_ARRAY_LENGTH");
        for (uint256 i = 0; i < submitters.length; i++) {
            submittersSet.remove(submitters[i]);
            require(submittersSet.length() > 0, "INVALID_SUBMITTER_COUNT");
            emit SubmitterRemoved(submitters[i]);
        }
    }

    function updateSigners(
        address[] memory signers,
        uint256[] memory weights
    )
        public
        onlyVerifier
        onlyWithinArrayBounds(signers.length, weights.length)
    {
        for (uint256 i = 0; i < signers.length; i++) {
            _setupSigner(signers[i], weights[i]);
        }

        require(
            _isAvailableThresholdEnough(thresholdMap[Threshold.HIGH]),
            "INSUFICIENT_THRESHOLD_AVAILABLE"
        );
        require(signersSet.length() <= MAX_SIGNERS, "INVALID_SIGNER_COUNT");
    }

    function updateHighThreshold(uint256 high) public onlyVerifier {
        require(high > 0 && high <= MAX_THRESHOLD, "INVALID_THRESHOLD");
        require(
            _isAvailableThresholdEnough(high),
            "INSUFICIENT_THRESHOLD_AVAILABLE"
        );
        thresholdMap[Threshold.HIGH] = high;
        emit HighThresholdUpdated(high);
    }

    function updateNormalThreshold(uint256 normal) public onlyVerifier {
        require(normal > 0 && normal <= MAX_THRESHOLD, "INVALID_THRESHOLD");
        require(normal < thresholdMap[Threshold.HIGH], "INVALID_THRESHOLD");
        thresholdMap[Threshold.NORMAL] = normal;
        emit NormalThresholdUpdated(normal);
    }

    function updateThresholds(
        uint256 high,
        uint256 normal
    ) public onlyVerifier {
        require(high > 0 && high <= MAX_THRESHOLD, "INVALID_THRESHOLD");
        require(normal > 0 && normal <= MAX_THRESHOLD, "INVALID_THRESHOLD");
        require(high > normal, "INVALID_THRESHOLD");
        require(
            _isAvailableThresholdEnough(high),
            "INSUFICIENT_THRESHOLD_AVAILABLE"
        );
        thresholdMap[Threshold.HIGH] = high;
        thresholdMap[Threshold.NORMAL] = normal;
        emit ThresholdsUpdated(normal, high);
    }

    // ******************** Private Functions ********************* //
    // ************************************************************ //

    function _getHash(
        address account,
        address target,
        bytes memory payload,
        uint256 nonce
    ) private view returns (bytes32 hash) {
        hash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encodePacked(
                        bytes1(0x19),
                        bytes1(0),
                        address(this),
                        target,
                        payload,
                        block.chainid,
                        account,
                        nonce
                    )
                )
            )
        );
    }

    function _getRequiredThreshold(
        address target
    ) private view returns (uint256) {
        return
            target == address(this)
                ? thresholdMap[Threshold.HIGH]
                : thresholdMap[Threshold.NORMAL];
    }

    function _splitSignature(
        bytes memory signatures,
        uint256 idx
    ) private pure returns (uint8 v, bytes32 r, bytes32 s) {
        assembly {
            r := mload(add(signatures, add(0x20, mul(0x41, idx))))
            s := mload(add(signatures, add(0x40, mul(0x41, idx))))
            v := and(mload(add(signatures, add(0x41, mul(0x41, idx)))), 0xff)
        }
        require(v == 27 || v == 28, "INVALID_SIGNATURE_FORMAT");
    }

    function _isAvailableThresholdEnough(
        uint256 requiredThreshold
    ) private view returns (bool enoughThreshold) {
        enoughThreshold = false;
        uint256 availableThreshold = 0;
        for (uint i = 0; i < signersSet.length(); i++) {
            availableThreshold += signersMap[signersSet.at(i)];
            if (availableThreshold >= requiredThreshold) {
                enoughThreshold = true;
                break;
            }
        }
    }

    function _setupSigner(address signer, uint256 weight) private {
        require(signer != address(0), "INVALID_ADDRESS");
        if (weight == 0) {
            _removeSigner(signer);
            emit SignerRemoved(signer);
            return;
        }
        signersSet.add(signer);
        emit SignerAdded(signer);
        signersMap[signer] = weight;
    }

    function _removeSigner(address signer) private {
        if (signersMap[signer] == 0) return;
        signersSet.remove(signer);
        delete signersMap[signer];
    }

    // ----------- Utility views functions ----------- //

    function getSubmittersCount() external view returns (uint256) {
        return submittersSet.length();
    }

    function getSubmitters()
        external
        view
        returns (address[] memory currentSubmitters)
    {
        currentSubmitters = new address[](submittersSet.length());
        currentSubmitters = submittersSet.values();
    }

    function getSignersCount() external view returns (uint256) {
        return signersSet.length();
    }

    function getSignerWeight(address signer) external view returns (uint256) {
        return signersMap[signer];
    }

    function getHighThresholdValue() external view returns (uint256) {
        return thresholdMap[Threshold.HIGH];
    }

    function getNormalThresholdValue() external view returns (uint256) {
        return thresholdMap[Threshold.NORMAL];
    }

    function getSignersInfo()
        external
        view
        returns (
            address[] memory currentSigners,
            uint256[] memory currentSignersWeights
        )
    {
        currentSigners = new address[](signersSet.length());
        currentSignersWeights = new uint256[](signersSet.length());

        currentSigners = signersSet.values();
        for (uint i = 0; i < signersSet.length(); i++) {
            currentSignersWeights[i] = signersMap[currentSigners[i]];
        }
    }

    function getNonce(address account) external view returns (uint256 nonce) {
        if (account == address(0)) {
            nonce = globalNonce;
        } else {
            nonce = accountNonces[account];
        }
    }
}

