// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./Address.sol";

import "./IStakefishTransactionFeePoolV2.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

contract StakefishTransactionFeePoolVNatSpec is
//    Initializable,
//    UUPSUpgradeable,
    IStakefishTransactionFeePoolV2
{
    using Address for address payable;

    constructor() {}

//    constructor() initializer {}
//
//    function initialize(address operatorAddress_, address adminAddress_) initializer external {
//        // ...;
//    }
//
//    function _authorizeUpgrade(address) internal override adminOnly {}

    /**
     * @notice Helper method to decode `validatorInfo` into its components. uint256 packs two information:
     * The lower 4 bytes are a timestamp representing the join pool time of the validator.
     * The next 20 bytes are the ETH1 address of the owner.
     * @dev Returns (address `ownerAddress`, uint256 `joinPoolTimestamp`)
     * @param data uint256 encoded `validatorInfo` containing (address ownerAddress, uint256 joinPoolTimestamp)
     * @return (address ownerAddress, uint256 joinPoolTimestamp)
     */
    function decodeValidatorInfo(
        uint256 data
    ) virtual public pure returns (address, uint256) {
        return (address(0), 0);
    }

    /**
     * @notice Helper method to encode validatorInfo from its components. The lower 4 bytes of the encoded `data`
     * are a timestamp representing the join pool time of the validator. The next 20 bytes are the ETH1 address of the owner.
     * @dev Returns (uint256 `data`)
     * @param ownerAddress The depositor that owns the validator
     * @param joinPoolTimestamp The timestamp recorded when the validator joined the pool
     * @return uint256 encoded `data`
     */
    function encodeValidatorInfo(
        address ownerAddress,
        uint256 joinPoolTimestamp
    ) virtual public pure returns (uint256) {
        return 0;
    }

    /**
     * Operator Functions
     */

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function joinPool(
        bytes calldata validatorPubKey,
        address depositorAddress,
        uint256 joinTime
    ) external override operatorOnly {
        // ...;
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function partPool(
        bytes calldata validatorPubKey,
        uint256 leaveTime
    ) external override operatorOnly {
        // ...;
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function bulkJoinPool(
        bytes calldata validatorPubKeyArray,
        address[] calldata depositorAddresses,
        uint256 joinTime
    ) external override operatorOnly {
        // ...;
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function bulkPartPool(
        bytes calldata validatorPubKeyArray,
        uint256 leaveTime
    ) external override operatorOnly {
        // ...;
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function pendingReward(
        address depositorAddress
    ) virtual external override view returns (uint256, uint256) {
        return (0, 0);
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function collectReward(
        address payable beneficiary,
        uint256 amountRequested
    ) external override {
        // ...;
    }

    /**
     * Admin Functions
     */

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function setCommissionRate(
        uint256 commissionRate
    ) external override adminOnly {
        // ...;
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function collectPoolCommission(
        address payable beneficiary,
        uint256 amountRequested
    ) external override adminOnly {
        // ...;
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function transferValidatorByAdmin(
        bytes calldata validatorPubKeys,
        address[] calldata toAddresses,
        uint256 transferTimestamp
    ) external override adminOnly {
        // ...;
    }

    /**
     * Warning: The `balance` and `lifetimeCollectedCommission` must also be transferred during contract migration
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function transferClaimHistory(
        address[] calldata addresses,
        uint256[] calldata claimAmounts
    ) external override adminOnly {
        // ...;
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function closePoolForWithdrawal() external override adminOnly {
        // ...;
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function openPoolForWithdrawal() external override adminOnly {
        // ...;
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function changeOperator(
        address newOperator
    ) external override adminOnly {
        // ...;
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function emergencyWithdraw (
        address[] calldata depositorAddresses,
        address[] calldata beneficiaries,
        uint256 amountRequested
    ) external override adminOnly {
        // ...;
    }

    /**
     * Public
     */

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function totalValidators() virtual external override view returns (uint256 validatorCount) {
        return 0;
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function getPoolState() virtual external override view returns (uint256, uint256, uint256, uint256, uint256) {
        return (0, 0, 0, 0, 0);
    }

    /**
     * @inheritdoc IStakefishTransactionFeePoolV2
     */
    function getUserState(address user) virtual external override view returns (uint256, uint256, uint256, uint256) {
        return (0, 0, 0, 0);
    }

    /**
     * Modifiers
     */

    modifier operatorOnly() {
        _;
    }

    modifier adminOnly() {
        _;
    }

    receive() external override payable {
        // ...;
    }

}

