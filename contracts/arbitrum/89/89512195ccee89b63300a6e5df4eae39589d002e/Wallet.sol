// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./StringsUpgradeable.sol";

import "./WalletFactory.sol";
import "./ProxyUtils.sol";

/// @title Wallet
/// @notice Basic multisig smart contract wallet with a relay guardian.
contract Wallet is ProxyUtils {
    using AddressUpgradeable for address;

    /// @notice The creating `WalletFactory`.
    WalletFactory public walletFactory;

    /// @dev Struct for a signer.
    struct SignerConfig {
        uint8 votes;
        uint256 signingTimelock;
    }

    /// @notice Configs per signer.
    mapping(address => SignerConfig) public signerConfigs;

    /// @dev Event emitted when a signer config is changed.
    event SignerConfigChanged(address indexed signer, SignerConfig config);

    /// @notice Threshold of signer votes required to sign transactions.
    uint8 public threshold;

    /// @notice Timelock after which the contract can be upgraded and/or the relayer whitelist can be disabled.
    uint256 public relayerWhitelistTimelock;

    /// @dev Struct for a signature.
    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    /// @notice Last timestamp disabling the relayer whitelist was queued/requested.
    uint256 public disableRelayerWhitelistQueueTimestamp;

    /// @notice Maps pending (queued) signature hashes to queue timestamps.
    mapping(bytes32 => uint256) public pendingSignatures;

    /// @notice Current transaction nonce (prevents replays).
    uint256 public nonce;

    /// @dev Initializes the contract.
    /// See `WalletFactory` for details.
    function initialize(
        address[] calldata signers,
        SignerConfig[] calldata _signerConfigs,
        uint8 _threshold,
        uint256 _relayerWhitelistTimelock,
        bool _subscriptionPaymentsEnabled
    ) external {
        // Make sure not initialized already
        require(threshold == 0, "Already initialized.");

        // Input validation
        require(signers.length > 0, "Must have at least one signer.");
        require(signers.length == _signerConfigs.length, "Lengths of signer and signer config arrays must match.");
        require(_threshold > 0, "Vote threshold must be greater than 0.");

        // Set variables
        for (uint256 i = 0; i < _signerConfigs.length; i++) {
            signerConfigs[signers[i]] = _signerConfigs[i];
            emit SignerConfigChanged(signers[i], _signerConfigs[i]);
        }

        threshold = _threshold;
        relayerWhitelistTimelock = _relayerWhitelistTimelock;
        subscriptionPaymentsEnabled = _subscriptionPaymentsEnabled;

        // Set WalletFactory
        walletFactory = WalletFactory(msg.sender);

        // Set lastSubscriptionPaymentTimestamp
        if (_subscriptionPaymentsEnabled) lastSubscriptionPaymentTimestamp = block.timestamp - SUBSCRIPTION_PAYMENT_INTERVAL_SECONDS;
    }

    /// @dev Access control for the contract itself.
    /// Make sure to call functions marked with this modifier via `Wallet.functionCall`.
    modifier onlySelf() {
        require(msg.sender == address(this), "Sender is not self.");
        _;
    }

    /// @dev Internal function to verify `signatures` on `signedData`.
    function _validateSignatures(Signature[] calldata signatures, bytes32 signedDataHash, bool requireRelayGuardian) internal view {
        // Input validation
        require(signatures.length > 0, "No signatures supplied.");
        
        // Loop through signers to tally votes (keeping track of signers checked to look for duplicates)
        uint256 _votes = 0;
        address[] memory signers = new address[](signatures.length);

        for (uint256 i = 0; i < signatures.length; i++) {
            // Get signer
            Signature calldata sig = signatures[i];
            address signer = ecrecover(signedDataHash, sig.v, sig.r, sig.s);

            // Check for duplicate & keep track of signer to check for duplicates in the future
            for (uint256 j = 0; j < i; j++) require(signer != signers[j], "Duplicate signer in signatures array.");
            signers[i] = signer;

            // Get signer config
            SignerConfig memory config = signerConfigs[signer];
            require(config.votes > 0, "Unrecognized signer.");

            // Check signing timelock
            if (config.signingTimelock > 0) {
                uint256 timestamp = pendingSignatures[keccak256(abi.encode(sig))];
                require(timestamp > 0, "Signature not queued.");
                require(timestamp + config.signingTimelock <= block.timestamp, "Timelock not satisfied.");
            }

            // Tally votes
            _votes += config.votes;
        }

        // Check tally of votes against threshold
        require(_votes >= threshold, "Votes not greater than or equal to threshold.");

        // Relayer validation (if enabled)
        if (relayerWhitelistTimelock > 0 && requireRelayGuardian) walletFactory.checkRelayGuardian(msg.sender);
    }

    /// @notice Event emitted when a function call reverts.
    event FunctionCallReversion(uint256 indexed _nonce, uint256 indexA, uint256 indexB, string error);

    /// @notice Call any function on any contract given sufficient authentication.
    /// If the call reverts, the transaction will not revert but will emit a `FunctionCallReversion` event.
    /// @dev NOTICE: Does not validate that ETH balance is great enough for value + gas refund to paymaster + paymaster incentive. Handle this on the UI + relayer sides.
    /// Before the user signs, the UI should calculate gas usage and ensure the external function call will not revert with `eth_estimateGas`.
    /// Relayer should confirm the function call does not revert due to bad signatures or low gas limit by either `eth_call` or `eth_estimateGas` or by simulating signature validation off-chain.
    /// Predict user-specified gas limit (i.e., `feeData[0]`) using the following pseudocode:
    ///     const A = 22000; // Maximum base gas recognized by `gasleft()` in `functionCall` (assume `value` > 0). TODO: Should this include some leeway for unexpected increased in return data?
    ///     const B = 9000; // Maximum gas used by `_validateSignatures` per signature, without `signingTimelock`s (but assume `checkRelayGuardian` for now).
    ///     const C = 3000; // Additional gas used by `_validateSignatures` per signature due to presence of `signingTimelock > 0`.
    ///     const E = 0.195; // Additional gas used per byte of calldata in the external function call.
    ///     let sigGas = 0;
    ///     for (const sig of signatures) sigGas += B + (signerConfig.signingTimelock > 0 ? C : 0);
    ///     return A + sigGas + E * data.length + simulateFunctionCall(target, data, value);
    /// Predict paymaster incentive (i.e., `feeData[3]`) with the following pseudocode:
    ///     const X = 38000; // Maximum base gas unrecognized by `gasleft()` in `functionCall`.
    ///     const Y = 1200; // Maximum gas used per signature (in terms of built-in ABI decoding of `functionCall`'s data into its `signatures` parameter).
    ///     const W = 16.5; // Maximum gas used per byte of calldata in the external function call.
    ///     return X + Y * signatures.length + W * data.length;
    /// It's a good idea to add leeway by multiplying the user-specified gas limit by 1.1x to 1.5x since the risk of losing the leeway is low and the risk of not giving enough leeway is much greater (primarily because the external function call itself can vary greatly in gas usage).
    /// However, the paymaster incentive should be kept as is because, since the values are already higher than the average, the relayer will, on average, gain a small amount of ETH, and there is no penalty to the user if the relayer loses slightly.
    /// @param feeData Array of `[gasLimit, maxFeePerGas, maxPriorityFeePerGas, paymasterIncentive]`.
    function functionCall(
        Signature[] calldata signatures,
        address target,
        bytes calldata data,
        uint256 value,
        uint256[4] calldata feeData
    ) external {
        // Get initial gas
        uint256 initialGas = gasleft();

        // Get message hash (include chain ID, wallet contract address, and nonce) and validate signatures
        bytes32 dataHash = keccak256(abi.encode(block.chainid, address(this), ++nonce, this.functionCall.selector, target, data, value, feeData));
        _validateSignatures(signatures, dataHash, true);

        // Gas validation
        require(tx.gasprice <= feeData[1], "maxFeePerGas not satisfied.");
        require(tx.gasprice - block.basefee <= feeData[2], "maxPriorityFeePerGas not satisfied.");

        // Call contract
        (bool success, bytes memory ret) = target.call{ value: value, gas: gasleft() - 30000 }(data);
        if (!success) emit FunctionCallReversion(nonce, 0, 0, string(abi.encode(bytes32(ret))));

        // Send relayer the gas back
        uint256 gasUsed = initialGas - gasleft();
        require(gasUsed <= feeData[0], "Gas limit not satisfied.");
        msg.sender.call{value: (gasUsed * tx.gasprice) + feeData[3] }("");
    }

    /// @notice Checks gas usage (and revert string if a function reverts) for calling a function on a contract. Always reverts with the gas usage encoded, unless a revert happens earlier.
    /// @dev Requires that the sender is the zero address so that the function is read-only. (This prevents accidental use and might provide additional security, though it probably doesn't since this function always reverts at the end, but costs us nothing so why not?)
    function simulateFunctionCall(
        address target,
        bytes calldata data,
        uint256 value
    ) external {
        // Require sender == zero address
        require(msg.sender == address(0), "Sender must be the zero address for simulations.");

        // Bogus feeData (for abi.encode simulation below)
        uint256[4] memory feeData = [
            0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f,
            0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f,
            0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f,
            0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f
        ];

        // Get initial gas
        uint256 initialGas = gasleft();

        // Simulate getting message hash (since gas is hard to predict)
        keccak256(abi.encode(block.chainid, address(this), ++nonce, this.functionCall.selector, target, data, value, feeData));

        // Actually simulate the external function call
        (bool success, bytes memory ret) = target.call{ value: value, gas: gasleft() - 30000 }(data);

        // Bubble up revert
        if (!success) revert(string(abi.encodePacked("Call reverted: ", ret)));

        // Revert with gas used encoded as a decimal string
        revert(string(abi.encodePacked("WALLET_SIMULATE_FUNCTION_CALL_MULTI_GAS_USAGE=", StringsUpgradeable.toString(initialGas - gasleft()))));
    }

    /// @notice Call multiple functions on any contract(s) given sufficient authentication.
    /// If the call reverts, the transaction will not revert but will emit a `FunctionCallReversion` event.
    /// @dev NOTICE: Does not validate that ETH balance is great enough for value + gas refund to paymaster + paymaster incentive. Handle this on the UI + relayer sides.
    /// Before the user signs, the UI should calculate gas usage and ensure function calls will not revert with `simulateFunctionCallMulti`.
    /// Relayer should confirm the function call does not revert due to bad signatures or low gas limit by either `eth_call` or `eth_estimateGas` or by simulating signature validation off-chain.
    /// Predict user-specified gas limit (i.e., `feeData[0]`) using the following pseudocode:
    ///     const A; // Maximum base gas recognized by `gasleft()` in `functionCallMulti` (excluding paymaster incentive).
    ///     const B; // Maximum gas used by `_validateSignatures` per signature, without `signingTimelock`s (but assume `checkRelayGuardian` for now).
    ///     const C; // Additional gas used by `_validateSignatures` per signature due to presence of `signingTimelock > 0`.
    ///     const D; // Base gas used per external function call: only necessary if there is a need to include some leeway for unexpected increased in return data. TODO: Do we need this?
    ///     let sigGas = 0;
    ///     for (const sig of signatures) sigGas += B + (signerConfig.signingTimelock > 0 ? C : 0);
    ///     return A + sigGas + D * targets.length + simulateFunctionCallMulti(targets, data, values);
    /// Predict paymaster incentive (i.e., `feeData[3]`) with the following pseudocode:
    ///     const X; // Maximum base gas unrecognized by `gasleft()` in `functionCallMulti`.
    ///     const Y; // Maximum gas used per signature (in terms of built-in ABI decoding of `functionCallMulti`'s data into its `signatures` parameter).
    ///     const Z; // Maximum base gas used per external function call (in terms of built-in ABI decoding of `functionCallMulti`'s data into its `targets`, `data`, and `values` parameters).
    ///     const W; // Maximum gas used per byte of calldata in each external function call.
    ///     return X + Y * signatures.length + sum(Z + W * data[i].length);
    /// It's a good idea to add leeway to the user-specified gas limit since the risk of losing the leeway is low and the risk of not giving enough leeway is much greater.
    /// However, the paymaster incentive should be kept as is because, since the values are already higher than the average, the relayer will, on average, gain a small amount of ETH, and there is no penalty to the user if the relayer loses slightly.
    /// @param feeData Array of `[gasLimit, maxFeePerGas, maxPriorityFeePerGas, paymasterIncentive]`.
    function functionCallMulti(
        Signature[] calldata signatures,
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        uint256[4] calldata feeData
    ) external {
        // Get initial gas
        uint256 initialGas = gasleft();

        // Get message hash (include chain ID, wallet contract address, and nonce) and validate signatures
        bytes32 dataHash = keccak256(abi.encode(block.chainid, address(this), ++nonce, this.functionCallMulti.selector, targets, data, values, feeData));
        _validateSignatures(signatures, dataHash, true);

        // Gas validation
        require(tx.gasprice <= feeData[1], "maxFeePerGas not satisfied.");
        require(tx.gasprice - block.basefee <= feeData[2], "maxPriorityFeePerGas not satisfied.");

        // Input validation
        require(targets.length == data.length && targets.length == values.length, "Input array lengths must be equal.");

        // Call contracts
        for (uint256 i = 0; i < targets.length; i++) {
            uint256 gasl = gasleft();
            // If there isn't enough gas left to run the function, break now to avoid checked math reversion when subtracting 30000 from gas left
            if (gasl <= 30000) {
                emit FunctionCallReversion(nonce, 0, i, "Wallet: Function call ran out of gas.");
                break;
            }
            (bool success, bytes memory ret) = targets[i].call{ value: values[i], gas: gasl - 30000 }(data[i]);
            if (!success) emit FunctionCallReversion(nonce, 0, i, string(abi.encode(bytes32(ret))));
        }

        // Send relayer the gas back
        uint256 gasUsed = initialGas - gasleft();
        require(gasUsed <= feeData[0], "Gas limit not satisfied.");
        msg.sender.call{value: (gasUsed * tx.gasprice) + feeData[3] }("");
    }

    /// @notice Checks gas usage (and revert string if a function reverts) for calling multiple functions on contract(s). Always reverts with the gas usage encoded, unless a revert happens earlier.
    /// @dev Requires that the sender is the zero address so that the function is read-only. (This prevents accidental use and might provide additional security, though it probably doesn't since this function always reverts at the end, but costs us nothing so why not?)
    function simulateFunctionCallMulti(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external {
        // Require sender == zero address
        require(msg.sender == address(0), "Sender must be the zero address for simulations.");

        // Bogus feeData (for abi.encode simulation below)
        uint256[4] memory feeData = [
            0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f,
            0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f,
            0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f,
            0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f
        ];

        // Get initial gas
        uint256 initialGas = gasleft();

        // Simulate getting message hash (since gas is hard to predict)
        keccak256(abi.encode(block.chainid, address(this), ++nonce, this.functionCallMulti.selector, targets, data, values, feeData));

        // Call contracts
        for (uint256 i = 0; i < targets.length; i++) {
            // Simulate these 2 operations to avoid having to factor it into the off-chain gas calculation
            uint256 gasl = gasleft();
            if (gasl <= 30000) revert(string(abi.encodePacked("Function call #", StringsUpgradeable.toString(i), " ran out of gas.")));

            // Actually simulate the external function call
            (bool success, bytes memory ret) = targets[i].call{ value: values[i], gas: gasl - 30000 }(data[i]);

            // Bubble up revert
            if (!success) revert(string(abi.encodePacked("Reverted on call #", StringsUpgradeable.toString(i), ": ", ret)));
        }

        // Revert with gas used encoded as a decimal string
        revert(string(abi.encodePacked("WALLET_SIMULATE_FUNCTION_CALL_MULTI_GAS_USAGE=", StringsUpgradeable.toString(initialGas - gasleft()))));
    }

    /// @notice Allows sending a combination of `functionCall`s and `functionCallMulti`s.
    /// Only useful for multi-party wallets--if using a single-party wallet, just re-sign all pending transactions and use `functionCallMulti` to save gas.
    /// If the call reverts, the transaction will not revert but will emit a `FunctionCallReversion` event.
    /// @dev NOTICE: Does not validate that ETH balance is great enough for value + gas refund to paymaster + paymaster incentive. Handle this on the UI + relayer sides.
    /// Relayer should confirm the function call does not revert due to bad signatures or low gas limit by either `eth_call` or `eth_estimateGas` or by simulating signature validation off-chain.
    /// @param multi Array of booleans indicating whether or not their associated item in `signedData` (and their associated item in `signatures`) is a `functionCall` or a `functionCallMulti`.
    /// @param signatures Array of arrays of signatures for each `functionCall` or `functionCallMulti`--each array corresponds to each item in the `multi` parameter and each item in the `signedData` parameter.
    /// @param signedData Array of signed data for each `functionCall` or `functionCallMulti`--each item corresponds to each item in the `multi` parameter and each item in the `signatures` parameter.
    function functionCallBatch(
        bool[] calldata multi,
        Signature[][] calldata signatures,
        bytes[] calldata signedData
    ) external {
        // Get initial gas
        uint256 initialGas = gasleft();

        // Input validation
        require(multi.length == signatures.length && multi.length == signedData.length, "Input array lengths must be equal.");

        // Loop through batch
        uint256 totalPaymasterIncentive = 0;

        for (uint256 i = 0; i < multi.length; i++) {
            uint256 minEndingGas = gasleft();
            _validateSignatures(signatures[i], keccak256(signedData[i]), true);

            if (multi[i]) {
                // Decode data and check relayer
                address[] memory targets;
                bytes[] memory data;
                uint256[] memory values;
                {
                    uint256 chainid;
                    address wallet;
                    uint256 _nonce;
                    bytes4 selector;
                    uint256[4] memory feeData;
                    (chainid, wallet, _nonce, selector, targets, data, values, feeData) =
                        abi.decode(signedData[i], (uint256, address, uint256, bytes4, address[], bytes[], uint256[], uint256[4]));
                    require(chainid == block.chainid && wallet == address(this) && _nonce == ++nonce && selector == this.functionCallMulti.selector, "Invalid functionCallMulti signature.");
                    totalPaymasterIncentive += feeData[3];

                    // Gas validation
                    minEndingGas -= feeData[0];
                    require(tx.gasprice <= feeData[1], "maxFeePerGas not satisfied.");
                    require(tx.gasprice - block.basefee <= feeData[2], "maxPriorityFeePerGas not satisfied.");
                }

                // Input validation
                require(targets.length == data.length && targets.length == values.length, "Input array lengths must be equal.");

                // Call contracts
                for (uint256 j = 0; j < targets.length; j++) {
                    bytes memory ret;
                    {
                        uint256 gasl = gasleft();
                        // If there isn't enough gas left to run the function, break now to avoid checked math reversion when subtracting 30000 from gas left
                        if (gasl <= 30000) {
                            emit FunctionCallReversion(nonce, i, j, "Wallet: function call ran out of gas.");
                            break;
                        }
                        bool success;
                        (success, ret) = targets[j].call{ value: values[j], gas: gasl - 30000 }(data[j]);
                        if (success) continue;
                    }

                    // If call reverted:
                    emit FunctionCallReversion(nonce, i, j, string(abi.encode(bytes32(ret))));
                }

                require(minEndingGas <= gasleft(), "Gas limit not satisfied.");
            } else {
                // Decode data and check relayer
                address target;
                bytes memory data;
                uint256 value;
                {
                    uint256 chainid;
                    address wallet;
                    uint256 _nonce;
                    bytes4 selector;
                    uint256[4] memory feeData;
                    (chainid, wallet, _nonce, selector, target, data, value, feeData) =
                        abi.decode(signedData[i], (uint256, address, uint256, bytes4, address, bytes, uint256, uint256[4]));
                    require(chainid == block.chainid && wallet == address(this) && _nonce == ++nonce && selector == this.functionCall.selector, "Invalid functionCall signature.");
                    totalPaymasterIncentive += feeData[3];

                    // Gas validation
                    minEndingGas -= feeData[0];
                    require(tx.gasprice <= feeData[1], "maxFeePerGas not satisfied.");
                    require(tx.gasprice - block.basefee <= feeData[2], "maxPriorityFeePerGas not satisfied.");
                }

                // Call contract
                (bool success, bytes memory ret) = target.call{ value: value, gas: gasleft() - 30000 }(data);
                if (!success) emit FunctionCallReversion(nonce, i, 0, string(abi.encode(bytes32(ret))));
                require(minEndingGas <= gasleft(), "Gas limit not satisfied.");
            }
        }

        // Send relayer the gas back
        msg.sender.call{value: ((initialGas - gasleft()) * tx.gasprice) + totalPaymasterIncentive }("");
    }

    /// @notice Modifies the signers on the wallet.
    /// WARNING: Does not validate that all signers have >= threshold votes.
    function modifySigners(address[] calldata signers, SignerConfig[] calldata _signerConfigs, uint8 _threshold) external onlySelf {
        // Input validation
        require(signers.length == _signerConfigs.length, "Lengths of signer and config arrays must match.");
        require(_threshold > 0, "Vote threshold must be greater than 0.");

        // Set variables
        for (uint256 i = 0; i < signers.length; i++) {
            signerConfigs[signers[i]] = _signerConfigs[i];
            emit SignerConfigChanged(signers[i], _signerConfigs[i]);
        }

        threshold = _threshold;
    }
    
    /// @notice Updates a signer on the wallet.
    /// WARNING: Does not validate that all signers have >= threshold votes.
    function modifySigner(address signer, uint8 votes, uint256 signingTimelock) external onlySelf {
        SignerConfig memory signerConfig = SignerConfig(votes, signingTimelock);
        signerConfigs[signer] = signerConfig;
        emit SignerConfigChanged(signer, signerConfig);
    }

    /// @notice Change the relayer whitelist timelock.
    /// Timelock can be enabled at any time.
    /// Off chain relay guardian logic: if changing the timelock from a non-zero value, requires that the user waits for the old timelock to pass (after calling `queueAction`).
    function setRelayerWhitelistTimelock(uint256 _relayerWhitelistTimelock) external onlySelf {
        relayerWhitelistTimelock = _relayerWhitelistTimelock;
        disableRelayerWhitelistQueueTimestamp = 0;
    }

    /// @notice Disable the relayer whitelist by setting the timelock to 0.
    /// Requires that the user waits for the old timelock to pass (after calling `queueAction`).
    function disableRelayerWhitelist(Signature[] calldata signatures) external {
        // Validate signatures
        bytes32 dataHash = keccak256(abi.encode(block.chainid, address(this), ++nonce, this.disableRelayerWhitelist.selector));
        if (msg.sender != address(this)) _validateSignatures(signatures, dataHash, false);

        // Check timelock
        if (relayerWhitelistTimelock > 0) {
            uint256 timestamp = disableRelayerWhitelistQueueTimestamp;
            require(timestamp > 0, "Action not queued.");
            require(timestamp + relayerWhitelistTimelock <= block.timestamp, "Timelock not satisfied.");
        }

        // Disable it
        require(relayerWhitelistTimelock > 0, "Relay whitelist already disabled.");
        relayerWhitelistTimelock = 0;
    }

    /// @notice Queues a timelocked action.
    /// @param signatures Only necessary if calling this function directly (i.e., not through `functionCall`).
    function queueDisableRelayerWhitelist(Signature[] calldata signatures) external {
        // Validate signatures
        bytes32 dataHash = keccak256(abi.encode(block.chainid, address(this), ++nonce, this.queueDisableRelayerWhitelist.selector));
        if (msg.sender != address(this)) _validateSignatures(signatures, dataHash, false);

        // Mark down queue timestamp
        disableRelayerWhitelistQueueTimestamp = block.timestamp;
    }

    /// @notice Unqueues a timelocked action.
    /// @param signatures Only necessary if calling this function directly (i.e., not through `functionCall`).
    function unqueueDisableRelayerWhitelist(Signature[] calldata signatures) external {
        // Validate signatures
        bytes32 dataHash = keccak256(abi.encode(block.chainid, address(this), ++nonce, this.unqueueDisableRelayerWhitelist.selector));
        if (msg.sender != address(this)) _validateSignatures(signatures, dataHash, false);

        // Reset queue timestamp
        disableRelayerWhitelistQueueTimestamp = 0;
    }

    /// @notice Queues a timelocked signature.
    /// No unqueue function because transaction nonces can be overwritten and signers can be removed.
    /// No access control because it's unnecessary and wastes gas.
    function queueSignature(bytes32 signatureHash) external {
        pendingSignatures[signatureHash] = block.timestamp;
    }

    /// @dev Receive ETH.
    receive() external payable { }

    /// @notice Returns the current `Wallet` implementation/logic contract.
    function implementation() external view returns (address) {
        return _implementation();
    }

    /// @notice Perform implementation upgrade.
    /// Emits an {Upgraded} event.
    function upgradeTo(address newImplementation) external onlySelf {
        _upgradeTo(newImplementation);
    }

    /// @notice Perform implementation upgrade with additional setup call.
    /// Emits an {Upgraded} event.
    function upgradeToAndCall(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) external onlySelf {
        _upgradeToAndCall(newImplementation, data, forceCall);
    }

    /// @dev Payment amount enabled/diabled.
    bool public subscriptionPaymentsEnabled;

    /// @dev Payment amount per cycle.
    uint256 public constant SUBSCRIPTION_PAYMENT_AMOUNT = 0.164e18; // Approximately 2 ETH per year

    /// @dev Payment amount cycle interval (in seconds).
    uint256 public constant SUBSCRIPTION_PAYMENT_INTERVAL_SECONDS = 86400 * 30; // 30 days

    /// @dev Last recurring payment timestamp.
    uint256 public lastSubscriptionPaymentTimestamp;

    /// @dev Recurring payments transfer function.
    function subscriptionPayments() external {
        require(subscriptionPaymentsEnabled, "Subscription payments not enabled.");
        uint256 cycles = (block.timestamp - lastSubscriptionPaymentTimestamp) / SUBSCRIPTION_PAYMENT_INTERVAL_SECONDS;
        require(cycles > 0, "No cycles have passed.");
        uint256 amount = SUBSCRIPTION_PAYMENT_AMOUNT * cycles;
        require(address(this).balance > 0, "No ETH to transfer.");
        if (amount > address(this).balance) amount = address(this).balance;
        (bool success, ) = walletFactory.relayGuardianManager().call{value: amount}("");
        require(success, "Failed to transfer ETH.");
        lastSubscriptionPaymentTimestamp = block.timestamp;
    }

    /// @dev Enable/disable recurring payments.
    /// Relay guardian has permission to enable or disable at any time depending on if credit card payments are going through.
    function setSubscriptionPaymentsEnabled(bool enabled, uint256 secondsPaidForAlready) external {
        require(subscriptionPaymentsEnabled != enabled, "Status already set to desired status.");
        address relayGuardian = walletFactory.relayGuardian();
        // Allow relay guardian to enable/disable subscription payments, allow user to enable, or allow user to disable if relayed by guardian
        require(msg.sender == relayGuardian || msg.sender == walletFactory.secondaryRelayGuardian() ||
            (msg.sender == address(this) && (enabled || (relayerWhitelistTimelock > 0 && relayGuardian != address(0)))), "Sender is not relay guardian or user enabling payments.");
        subscriptionPaymentsEnabled = enabled;
        if (enabled) lastSubscriptionPaymentTimestamp = block.timestamp - SUBSCRIPTION_PAYMENT_INTERVAL_SECONDS + secondsPaidForAlready;
    }
}

