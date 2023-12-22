// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./SafeTransferLib.sol";
import "./ILendingPoolV2.sol";
import "./ILendingPoolV3.sol";
import "./Base.sol";

contract AaveActions is Base {
    using SafeTransferLib for ERC20;

    address internal immutable _lendingPool;
    bool internal immutable _useV2;

    uint256 internal _targetHealthFactor = 11e17; // 1.10 Health factor.
    uint256 internal _allowedDeviation = 1e16; // 1% deviation from target.

    constructor(address lendingPool, bool useV2, address tokenA, address tokenB) {
        _lendingPool = lendingPool;
        _useV2 = useV2;
        ERC20(tokenA).safeApprove(address(lendingPool), type(uint256).max);
        ERC20(tokenB).safeApprove(address(lendingPool), type(uint256).max);
    }

    function getAaveParameters() external view returns (uint256 targetHealthFactor, uint256 allowedDeviation) {
        targetHealthFactor = _targetHealthFactor;
        allowedDeviation = _allowedDeviation;
    }

    // Returns the target ratio of debt to collateral.
    function targetCollateralisationRatio() public view returns (uint256 targetRatio) {
        (,,, uint256 currentLiquidationThreshold,,) = ILendingPoolV2(_lendingPool).getUserAccountData(address(this));
        currentLiquidationThreshold = currentLiquidationThreshold == 0 ? 8500 : currentLiquidationThreshold;
        targetRatio = _targetHealthFactor * 1e4 / 8500;
    }

    function getBorrowedAmount(ERC20 token) public view returns (uint256 tokenDebt) {
        if (_useV2) {
            tokenDebt = ERC20(ILendingPoolV2(_lendingPool).getReserveData(address(token)).variableDebtTokenAddress)
                .balanceOf(address(this));
        } else {
            tokenDebt = ERC20(ILendingPoolV3(_lendingPool).getReserveData(address(token)).variableDebtTokenAddress)
                .balanceOf(address(this));
        }
    }

    function getDepositedAmount(ERC20 token) public view returns (uint256 aTokenBalance) {
        if (_useV2) {
            aTokenBalance = ERC20(ILendingPoolV2(_lendingPool).getReserveData(address(token)).aTokenAddress).balanceOf(
                address(this)
            );
        } else {
            aTokenBalance = ERC20(ILendingPoolV3(_lendingPool).getReserveData(address(token)).aTokenAddress).balanceOf(
                address(this)
            );
        }
    }

    function _healthFactorStatus(uint256 ethPrice)
        internal
        view
        returns (bool needsRebalancing, uint256 factor, uint256 ethAmount)
    {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            ,
            uint256 currentLiquidationThreshold,
            ,
            uint256 healthFactor
        ) = ILendingPoolV2(_lendingPool).getUserAccountData(address(this));
        if (!_useV2) {
            // Need to convert from USD (8 decimals) to ETH.
            totalCollateralBase = totalCollateralBase * ethPrice / 1e20;
            totalDebtBase = totalDebtBase * ethPrice / 1e20;
        }
        needsRebalancing = healthFactor > _targetHealthFactor + _allowedDeviation
            || healthFactor < _targetHealthFactor - _allowedDeviation;
        factor = healthFactor;
        uint256 a = 1e18 * totalCollateralBase * currentLiquidationThreshold / 1e4;
        uint256 b = _targetHealthFactor * totalDebtBase;
        if (factor > _targetHealthFactor) {
            if (a > b) ethAmount = (a - b) / _targetHealthFactor;
        } else {
            if (b > a) ethAmount = (b - a) / _targetHealthFactor;
        }
    }

    function _deposit(ERC20 token, uint256 amount) internal {
        if (_useV2) {
            ILendingPoolV2(_lendingPool).deposit(address(token), amount, address(this), 0);
        } else {
            ILendingPoolV3(_lendingPool).deposit(address(token), amount, address(this), 0);
        }
    }

    function _depositMax(ERC20 token) internal returns (uint256 amount) {
        amount = token.balanceOf(address(this));
        _deposit(token, amount);
    }

    function _withdraw(ERC20 token, uint256 amount) internal {
        if (_useV2) {
            ILendingPoolV2(_lendingPool).withdraw(address(token), amount, address(this));
        } else {
            ILendingPoolV3(_lendingPool).withdraw(address(token), amount, address(this));
        }
    }

    // Notice: this function can fail if we have some outstanding debt.
    function _withdrawMax(ERC20 token) internal returns (uint256 amount) {
        amount = getDepositedAmount(token);
        _withdraw(token, amount);
    }

    function _borrow(ERC20 token, uint256 amount) internal {
        if (_useV2) {
            ILendingPoolV2(_lendingPool).borrow(address(token), amount, 2, 0, address(this));
        } else {
            ILendingPoolV3(_lendingPool).borrow(address(token), amount, 2, 0, address(this));
        }
    }

    function _repay(ERC20 token, uint256 amount) internal {
        if (_useV2) {
            ILendingPoolV2(_lendingPool).repay(address(token), amount, 2, address(this));
        } else {
            ILendingPoolV3(_lendingPool).repay(address(token), amount, 2, address(this));
        }
    }

    function _repayMax(ERC20 token) internal returns (uint256 amount) {
        amount = token.balanceOf(address(this));
        uint256 debt = getBorrowedAmount(token);
        if (amount > debt) amount = debt;
        _repay(token, amount);
    }

    function setHealthFactorParameters(uint256 target, uint256 deviation) external onlyOwner {
        _targetHealthFactor = target;
        _allowedDeviation = deviation;
    }
}

