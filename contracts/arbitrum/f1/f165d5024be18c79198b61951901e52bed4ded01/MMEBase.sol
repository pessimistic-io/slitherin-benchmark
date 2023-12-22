// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IMMEBase} from "./IMMEBase.sol";
import {Errors} from "./Errors.sol";
import {DataTypes} from "./DataTypes.sol";
import {Math} from "./Math.sol";
import {IAddressesRegistry} from "./IAddressesRegistry.sol";
import {IAccessManager} from "./IAccessManager.sol";

/**
 * @title MMEBase
 * @author Souq.Finance
 * @notice The Base contract to be inherited by MMEs
 * @notice License: https://souq-exchange.s3.amazonaws.com/LICENSE.md
 */
contract MMEBase is IMMEBase {
    using Math for uint256;
    uint256 public yieldReserve;
    address public immutable addressesRegistry;
    DataTypes.PoolSVSData public poolData;
    uint256[50] __gap;

    constructor(address _registry) {
        require(_registry != address(0), Errors.ADDRESS_IS_ZERO);
        addressesRegistry = _registry;
    }

    /**
     * @dev modifier for when the the msg sender is pool admin in the access manager
     */
    modifier onlyPoolAdmin() {
        require(
            IAccessManager(IAddressesRegistry(addressesRegistry).getAccessManager()).isPoolAdmin(msg.sender),
            Errors.CALLER_NOT_POOL_ADMIN
        );
        _;
    }

    /**
     * @dev modifier for when the the msg sender is either pool admin or pool operations in the access manager
     */
    modifier onlyPoolAdminOrOperations() {
        require(
            IAccessManager(IAddressesRegistry(addressesRegistry).getAccessManager()).isPoolAdmin(msg.sender) ||
                IAccessManager(IAddressesRegistry(addressesRegistry).getAccessManager()).isPoolOperations(msg.sender),
            Errors.CALLER_NOT_POOL_ADMIN_OR_OPERATIONS
        );
        _;
    }

    /// @inheritdoc IMMEBase
    function setFee(DataTypes.PoolFee calldata newFee) external onlyPoolAdmin {
        poolData.fee.lpBuyFee = newFee.lpBuyFee;
        poolData.fee.lpSellFee = newFee.lpSellFee;
        poolData.fee.royaltiesBuyFee = newFee.royaltiesBuyFee;
        poolData.fee.royaltiesSellFee = newFee.royaltiesSellFee;
        poolData.fee.protocolBuyRatio = newFee.protocolBuyRatio;
        poolData.fee.protocolSellRatio = newFee.protocolSellRatio;
        poolData.fee.royaltiesAddress = newFee.royaltiesAddress;
        poolData.fee.protocolFeeAddress = newFee.protocolFeeAddress;
        emit FeeChanged(poolData.fee);
    }

    /// @inheritdoc IMMEBase
    function setPoolIterativeLimits(DataTypes.IterativeLimit calldata newLimits) external onlyPoolAdmin {
        poolData.iterativeLimit.minimumF = newLimits.minimumF;
        poolData.iterativeLimit.maxBulkStepSize = newLimits.maxBulkStepSize;
        poolData.iterativeLimit.iterations = newLimits.iterations;
        emit PoolIterativeLimitsSet(poolData.iterativeLimit);
    }

    /// @inheritdoc IMMEBase
    function setPoolLiquidityLimits(DataTypes.LiquidityLimit calldata newLimits) external onlyPoolAdmin {
        poolData.liquidityLimit.poolTvlLimit = newLimits.poolTvlLimit;
        poolData.liquidityLimit.cooldown = newLimits.cooldown;
        poolData.liquidityLimit.maxDepositPercentage = newLimits.maxDepositPercentage;
        poolData.liquidityLimit.maxWithdrawPercentage = newLimits.maxWithdrawPercentage;
        poolData.liquidityLimit.feeMultiplier = newLimits.feeMultiplier;
        poolData.liquidityLimit.lastLpPrice = newLimits.lastLpPrice;
        poolData.liquidityLimit.addLiqMode = newLimits.addLiqMode;
        poolData.liquidityLimit.removeLiqMode = newLimits.removeLiqMode;
        poolData.liquidityLimit.onlyAdminProvisioning = newLimits.onlyAdminProvisioning;
        emit PoolLiquidityLimitsSet(poolData.liquidityLimit);
    }

}

