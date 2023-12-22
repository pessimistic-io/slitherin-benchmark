/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

import "./ICollateralModule.sol";
import "./Account.sol";
import "./CollateralConfiguration.sol";
import "./ERC20Helper.sol";
import "./Collateral.sol";

/**
 * @title Module for managing user collateral.
 * @dev See ICollateralModule.
 */
contract CollateralModule is ICollateralModule {
    using ERC20Helper for address;
    using CollateralConfiguration for CollateralConfiguration.Data;
    using Account for Account.Data;
    using AccountRBAC for AccountRBAC.Data;
    using Collateral for Collateral.Data;
    using SafeCastI256 for int256;
    using SafeCastU256 for uint256;

    /**
     * @inheritdoc ICollateralModule
     */
    function deposit(uint128 accountId, address collateralType, uint256 tokenAmount) external override {
        CollateralConfiguration.collateralEnabled(collateralType);
        Account.Data storage account = Account.exists(accountId);
        address depositFrom = msg.sender;
        address self = address(this);

        uint256 actualTokenAmount = tokenAmount;

        uint256 liquidationBooster = CollateralConfiguration.load(collateralType).liquidationBooster;
        if (account.collaterals[collateralType].liquidationBoosterBalance < liquidationBooster) {
            uint256 liquidationBoosterTopUp =
                liquidationBooster - account.collaterals[collateralType].liquidationBoosterBalance;
            actualTokenAmount += liquidationBoosterTopUp;
            account.collaterals[collateralType].increaseLiquidationBoosterBalance(liquidationBoosterTopUp);
            emit Collateral.LiquidatorBoosterUpdate(
                accountId, collateralType, liquidationBoosterTopUp.toInt(), block.timestamp
            );
        }

        uint256 allowance = IERC20(collateralType).allowance(depositFrom, self);
        if (allowance < actualTokenAmount) {
            revert IERC20.InsufficientAllowance(actualTokenAmount, allowance);
        }

        uint256 currentBalance = IERC20(collateralType).balanceOf(self);
        uint256 collateralCap = CollateralConfiguration.load(collateralType).cap;
        if (collateralCap < currentBalance + actualTokenAmount) {
            revert CollateralCapExceeded(
                collateralType, collateralCap, currentBalance, tokenAmount, actualTokenAmount - tokenAmount
            );
        }

        collateralType.safeTransferFrom(depositFrom, self, actualTokenAmount);

        account.collaterals[collateralType].increaseCollateralBalance(tokenAmount);
        emit Collateral.CollateralUpdate(accountId, collateralType, tokenAmount.toInt(), block.timestamp);

        emit Deposited(accountId, collateralType, actualTokenAmount, msg.sender, block.timestamp);
    }

    /**
     * @inheritdoc ICollateralModule
     */
    function withdraw(uint128 accountId, address collateralType, uint256 tokenAmount) external override {
        Account.Data storage account =
            Account.loadAccountAndValidatePermission(accountId, AccountRBAC._ADMIN_PERMISSION, msg.sender);

        uint256 collateralBalance = account.collaterals[collateralType].balance;
        if (tokenAmount > collateralBalance) {
            uint256 liquidatorBoosterWithdrawal = tokenAmount - collateralBalance;
            account.collaterals[collateralType].decreaseLiquidationBoosterBalance(liquidatorBoosterWithdrawal);
            emit Collateral.LiquidatorBoosterUpdate(
                accountId, collateralType, -liquidatorBoosterWithdrawal.toInt(), block.timestamp
            );

            account.collaterals[collateralType].decreaseCollateralBalance(collateralBalance);
            emit Collateral.CollateralUpdate(accountId, collateralType, -collateralBalance.toInt(), block.timestamp);
        } else {
            account.collaterals[collateralType].decreaseCollateralBalance(tokenAmount);
            emit Collateral.CollateralUpdate(accountId, collateralType, -tokenAmount.toInt(), block.timestamp);
        }

        account.imCheck(collateralType);

        collateralType.safeTransfer(msg.sender, tokenAmount);

        emit Withdrawn(accountId, collateralType, tokenAmount, msg.sender, block.timestamp);
    }

    /**
     * @inheritdoc ICollateralModule
     */
    function getAccountCollateralBalance(uint128 accountId, address collateralType)
        external
        view
        override
        returns (uint256 collateralBalance)
    {
        return Account.load(accountId).getCollateralBalance(collateralType);
    }

    /**
     * @inheritdoc ICollateralModule
     */
    function getAccountCollateralBalanceAvailable(uint128 accountId, address collateralType)
        external
        override
        returns (uint256 collateralBalanceAvailable)
    {
        return Account.load(accountId).getCollateralBalanceAvailable(collateralType);
    }

    /**
     * @inheritdoc ICollateralModule
     */
    function getAccountLiquidationBoosterBalance(uint128 accountId, address collateralType)
        external
        view
        override
        returns (uint256 collateralBalance)
    {
        return Account.load(accountId).getLiquidationBoosterBalance(collateralType);
    }

    /**
     * @inheritdoc ICollateralModule
     */
    function getTotalAccountValue(uint128 accountId, address collateralType)
        external
        view
        override
        returns (int256 totalAccountValue)
    {
        return Account.load(accountId).getTotalAccountValue(collateralType);
    }
}

