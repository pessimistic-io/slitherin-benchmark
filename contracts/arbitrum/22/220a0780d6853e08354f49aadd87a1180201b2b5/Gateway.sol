// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {SafeTransferLib, ERC20} from "./SafeTransferLib.sol";
import "./IFeePolicy.sol";
import "./Multicall.sol";
import "./EIP712.sol";
import "./QuotaLib.sol";

contract Gateway is EIP712("Gateway"), Multicall {
    using SafeTransferLib for ERC20;
    using QuotaLib for Quota;

    /// @dev Quota state
    mapping(bytes32 quotaHash => QuotaState state) internal _quotaStates;

    /// @notice Payer nonce, for bulk-canceling quotas (not for EIP712)
    mapping(address payer => uint96 payerNonce) public payerNonces;

    /// @notice Emit when a quota is validated
    /// @param controllerHash Hash of abi.encode(controller, controllerRefId)
    event QuotaValidated(
        bytes32 indexed quotaHash,
        address indexed payer,
        bytes32 indexed controllerHash,
        Quota quota,
        bytes quotaSignature
    );

    /// @notice Emit when a payer cancels a quota. Note that we do not check the quota's validity when it's cancelled.
    event QuotaCancelled(bytes32 indexed quotaHash);

    /// @notice Emit when a payer increments their nonce, i.e. bulk-canceling existing quotas
    event PayerNonceIncremented(address indexed payer, uint96 newNonce);

    /// @notice Emit when a charge is made
    event Charge(
        bytes32 indexed quotaHash,
        address recipient,
        uint160 amount,
        uint40 indexed cycleStartTime,
        uint160 cycleAmountUsed,
        uint24 chargeCount,
        bytes32 indexed receipt,
        Fee[] fees,
        bytes extraEventData
    );

    /// @notice Quota typehash, used for EIP712 signature
    bytes32 public constant _QUOTA_TYPEHASH = QuotaLib._QUOTA_TYPEHASH;

    /// @notice Get the state of a quota by its hash
    function getQuotaState(bytes32 quotaHash) external view returns (QuotaState memory state) {
        return _quotaStates[quotaHash];
    }

    /// @notice Validate the quota parameters with its signature.
    /// @param quota Quota
    /// @param quotaSignature Quota signature signed by the payer
    function validate(Quota memory quota, bytes memory quotaSignature) public {
        bytes32 quotaHash = quota.hash();
        QuotaState storage state = _quotaStates[quotaHash];

        if (!state.validated) {
            require(quota.payerNonce == payerNonces[quota.payer], "INVALID_PAYER_NONCE");
            if (msg.sender != quota.payer || quotaSignature.length != 0) {
                EIP712._verifySignature(quotaSignature, quotaHash, quota.payer);
            }
            state.validated = true;

            bytes32 controllerHash = keccak256(abi.encode(quota.controller, quota.controllerRefId));
            emit QuotaValidated(quotaHash, quota.payer, controllerHash, quota, quotaSignature);
        }
    }

    /// @notice Cancel quota. Only the payer or taker can cancel it.
    /// @param quota Quota. It can be not validated yet.
    function cancel(Quota memory quota) external {
        require(msg.sender == quota.payer, "NOT_ALLOWED");

        bytes32 quotaHash = quota.hash();
        _quotaStates[quotaHash].cancelled = true;
        emit QuotaCancelled(quotaHash);
    }

    /// @notice Increment a payer's nonce to bulk-cancel quotas which he/she approved to pay
    function incrementPayerNonce() external {
        payerNonces[msg.sender] += uint96(uint256(blockhash(block.number - 1)) >> 232); // add a quasi-random 24-bit number
        emit PayerNonceIncremented(msg.sender, payerNonces[msg.sender]);
    }

    /// @notice Pull token from payer to taker. Can only be called by the controller.
    /// @param quota Quota
    /// @param quotaSignature Quota signature signed by the payer. Can be empty if the quota is already validated.
    /// @param recipient Recipient of the charge
    /// @param amount Amount to charge
    /// @param fees Fees
    /// @param extraEventData Extra event data to emit
    /// @return receipt Receipt of the charge
    function charge(
        Quota memory quota,
        bytes memory quotaSignature,
        address recipient,
        uint160 amount,
        Fee[] calldata fees,
        bytes calldata extraEventData
    ) external returns (bytes32 receipt) {
        validate(quota, quotaSignature);

        require(msg.sender == quota.controller, "NOT_CONTROLLER");
        require(block.timestamp >= quota.startTime, "BEFORE_START_TIME");
        require(block.timestamp < quota.endTime, "REACHED_END_TIME");
        require(payerNonces[quota.payer] == quota.payerNonce, "PAYER_NONCE_INVALIDATED"); // ensure payer didn't bulk-cancel quota

        bytes32 quotaHash = quota.hash();
        QuotaState storage state = _quotaStates[quotaHash];

        require(!state.cancelled, "QUOTA_CANCELLED"); // ensure payer didn't cancel quota
        require(!quota.didMissCycle(state), "CYCLE_MISSED"); // ensure controller hasn't missed billing cycle

        // reset usage if new cycle starts
        if (state.chargeCount == 0 || block.timestamp - state.cycleStartTime >= quota.interval) {
            state.cycleStartTime = quota.latestCycleStartTime();
            state.cycleAmountUsed = 0;
        }
        require(uint256(state.cycleAmountUsed) + amount <= quota.amount, "EXCEEDED_QUOTA");

        // record usage
        state.cycleAmountUsed += amount;
        state.chargeCount++;

        // return a receipt (used for searching logs off-chain)
        receipt = keccak256(abi.encode(block.chainid, address(this), quotaHash, state.chargeCount));

        // emit event first, since there could be reentrancy later, and we want to keep the event order correct.
        emit Charge({
            quotaHash: quotaHash,
            recipient: recipient,
            amount: amount,
            cycleStartTime: state.cycleStartTime,
            cycleAmountUsed: state.cycleAmountUsed,
            chargeCount: state.chargeCount,
            receipt: receipt,
            fees: fees,
            extraEventData: extraEventData
        });

        // note that there could be reentrancy below, but it's safe since we already did all state changes.
        if (fees.length == 0) {
            // transfer token directly from payer to recipient if no fees
            ERC20(quota.token).safeTransferFrom(quota.payer, recipient, amount);
        } else {
            // transfer token from payer to this contract first.
            ERC20(quota.token).safeTransferFrom(quota.payer, address(this), amount);

            // send fees
            uint256 totalFees = 0;
            for (uint256 i = 0; i < fees.length; i++) {
                if (fees[i].amount == 0) continue;
                totalFees += fees[i].amount;
                require(totalFees <= amount, "INVALID_FEES");
                ERC20(quota.token).safeTransfer(fees[i].to, fees[i].amount);
            }

            // send remaining to recipient
            ERC20(quota.token).safeTransfer(recipient, amount - totalFees);
        }
    }

    /// @notice Get the status of a quota
    /// @dev Note that a quota can be cancelled but, if it's used for subscription, the subscription could still be
    // not ended yet if the current cycle has not ended yet. It depends on how the subscription implements.
    function getQuotaStatus(Quota calldata quota) public view returns (QuotaStatus status) {
        QuotaState memory state = _quotaStates[quota.hash()];

        // forgefmt:disable-next-item
        bool isCancelled = block.timestamp >= quota.endTime
            || quota.didMissCycle(state)
            || state.cancelled
            || payerNonces[quota.payer] > quota.payerNonce;

        if (isCancelled) return QuotaStatus.Cancelled;
        if (block.timestamp < quota.startTime) return QuotaStatus.NotStarted;
        if (quota.didChargeLatestCycle(state)) return QuotaStatus.Active;
        return state.chargeCount == 0 ? QuotaStatus.PendingFirstCharge : QuotaStatus.PendingNextCharge;
    }
}

