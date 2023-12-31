// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./D3VaultFunding.sol";

contract D3VaultLiquidation is D3VaultFunding {
    using SafeERC20 for IERC20;
    using DecimalMath for uint256;

    function isPositiveNetWorthAsset(address pool, address token) internal view returns (bool) {
        (uint256 balance, uint256 borrows) = _getBalanceAndBorrows(pool, token);
        return balance >= borrows;
    }

    function getPositiveNetWorthAsset(address pool, address token) internal view returns (uint256) {
        (uint256 balance, uint256 borrows) = _getBalanceAndBorrows(pool, token);
        if (balance > borrows) {
            return balance - borrows;
        } else {
            return 0;
        }
    }

    /// @notice public liquidate function, repay pool negative worth token and get collateral tokens with discount
    /// @param pool pool address, must be in belowMM
    /// @param collateral pool collateral, any positive worth token pool has
    /// @param collateralAmount collateral amount liquidator claim
    /// @param debt pool debt, any negative worth token pool has
    /// @param debtToCover debt amount liquidator repay
    function liquidate(
        address pool,
        address collateral,
        uint256 collateralAmount,
        address debt,
        uint256 debtToCover
    ) external nonReentrant {
        accrueInterests();

        require(!ID3MM(pool).isInLiquidation(), Errors.ALREADY_IN_LIQUIDATION);
        require(!checkBadDebtAfterAccrue(pool), Errors.HAS_BAD_DEBT);
        require(checkCanBeLiquidatedAfterAccrue(pool), Errors.CANNOT_BE_LIQUIDATED);
        require(isPositiveNetWorthAsset(pool, collateral), Errors.INVALID_COLLATERAL_TOKEN);
        require(!isPositiveNetWorthAsset(pool, debt), Errors.INVALID_DEBT_TOKEN);
        require(getPositiveNetWorthAsset(pool, collateral) >= collateralAmount, Errors.COLLATERAL_AMOUNT_EXCEED);
        
        uint256 collateralTokenPrice = ID3Oracle(_ORACLE_).getPrice(collateral);
        uint256 debtTokenPrice = ID3Oracle(_ORACLE_).getPrice(debt);
        uint256 collateralAmountMax = debtToCover.mul(debtTokenPrice).div(collateralTokenPrice.mul(DISCOUNT));
        require(collateralAmount <= collateralAmountMax, Errors.COLLATERAL_AMOUNT_EXCEED);

        AssetInfo storage info = assetInfo[debt];
        BorrowRecord storage record = info.borrowRecord[pool];
        uint256 borrows = record.amount.div(record.interestIndex == 0 ? 1e18 : record.interestIndex).mul(info.borrowIndex);
        require(debtToCover <= borrows, Errors.DEBT_TO_COVER_EXCEED);
        IERC20(debt).transferFrom(msg.sender, address(this), debtToCover);

        record.amount = borrows - debtToCover;
        record.interestIndex = info.borrowIndex;
        IERC20(collateral).transferFrom(pool, msg.sender, collateralAmount);
        ID3MM(pool).updateReserveByVault(collateral);
    }

    // ---------- Liquidate by DODO team ----------
    /// @notice if occuring bad debt, dodo team will start liquidation to balance debt
    function startLiquidation(address pool) external onlyLiquidator nonReentrant {
        accrueInterests();

        require(!ID3MM(pool).isInLiquidation(), Errors.ALREADY_IN_LIQUIDATION);
        require(checkCanBeLiquidatedAfterAccrue(pool), Errors.CANNOT_BE_LIQUIDATED);
        ID3MM(pool).startLiquidation();

        uint256 totalAssetValue = getTotalAssetsValue(pool);
        uint256 totalDebtValue = _getTotalDebtValue(pool);
        require(totalAssetValue < totalDebtValue, Errors.NO_BAD_DEBT);

        uint256 ratio = totalAssetValue.div(totalDebtValue);

        for (uint256 i; i < tokenList.length; i++) {
            address token = tokenList[i];
            AssetInfo storage info = assetInfo[token];
            BorrowRecord storage record = info.borrowRecord[pool];
            uint256 debt = record.amount.div(record.interestIndex == 0 ? 1e18 : record.interestIndex).mul(info.borrowIndex).mul(ratio);
            liquidationTarget[pool][token] = debt;
        }
    }

    function liquidateByDODO(
        address pool,
        LiquidationOrder calldata order,
        bytes calldata routeData,
        address router
    ) external onlyLiquidator nonReentrant {
        uint256 toTokenReserve = IERC20(order.toToken).balanceOf(address(this));
        uint256 fromTokenValue = DecimalMath.mul(ID3Oracle(_ORACLE_).getPrice(order.fromToken), order.fromAmount);

        // swap using Route
        {
            IERC20(order.fromToken).transferFrom(pool, router, order.fromAmount);
            (bool success, bytes memory data) = router.call(routeData);
            if (!success) {
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
        }

        // the transferred-in toToken USD value should not be less than 95% of the transferred-out fromToken
        uint256 receivedToToken = IERC20(order.toToken).balanceOf(address(this)) - toTokenReserve;
        uint256 toTokenValue = DecimalMath.mul(ID3Oracle(_ORACLE_).getPrice(order.toToken), receivedToToken);

        require(toTokenValue.div(fromTokenValue) >= DISCOUNT, Errors.EXCEED_DISCOUNT);
        IERC20(order.toToken).safeTransfer(pool, receivedToToken);
        ID3MM(pool).updateReserveByVault(order.fromToken);
        ID3MM(pool).updateReserveByVault(order.toToken);
    }

    function finishLiquidation(address pool) external onlyLiquidator nonReentrant {
        require(ID3MM(pool).isInLiquidation(), Errors.NOT_IN_LIQUIDATION);
        accrueInterests();

        bool hasPositiveBalance;
        bool hasNegativeBalance;
        for (uint256 i; i < tokenList.length; i++) {
            address token = tokenList[i];
            AssetInfo storage info = assetInfo[token];
            uint256 balance = IERC20(token).balanceOf(pool);
            uint256 debt = liquidationTarget[pool][token];
            int256 difference = int256(balance) - int256(debt);
            if (difference > 0) {
                require(!hasNegativeBalance, Errors.LIQUIDATION_NOT_DONE);
                hasPositiveBalance = true;
            } else if (difference < 0) {
                require(!hasPositiveBalance, Errors.LIQUIDATION_NOT_DONE);
                hasNegativeBalance = true;
                debt = balance; // if balance is less than target amount, just repay with balance
            }

            BorrowRecord storage record = info.borrowRecord[pool];
            uint256 borrows = record.amount;
            if (borrows == 0) continue;

            // note: During liquidation process, the pool's debt will slightly increase due to the generated interests. 
            // The liquidation process will not repay the interests. Thus all dToken holders will share the loss equally.
            uint256 realDebt = borrows.div(record.interestIndex == 0 ? 1e18 : record.interestIndex).mul(info.borrowIndex);
            IERC20(token).transferFrom(pool, address(this), debt);

            info.totalBorrows = info.totalBorrows - realDebt;
            record.amount = 0;
        }

        ID3MM(pool).finishLiquidation();
    }
}

