// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AaveV3.sol";
import "./CommonModule.sol";

abstract contract BorrowModule is CommonModule {

    uint256 public constant INTEREST_RATE_MODE = 2;
    uint16 public constant REFERRAL_CODE = 0;

    address public poolAddressesProvider;
    uint256 public neededHealthFactor;
    uint256 public currentHealthFactor; //not used
    uint256 public liquidationThreshold;

    function _getBorrowLiquidity() internal view returns (uint256 aaveCollateralAmount, uint256 aaveBorrowAmount) {
        return AaveV3BorrowLibrary._getLiquidity(this);
    }

    function getCurrentHealthFactor() public view returns(uint256 _currentHealthFactor) {
        return AaveV3BorrowLibrary._getCurrentHealthFactor(this);
    }

    function _borrowAmount() internal view returns(uint256) {
        return AaveV3BorrowLibrary._borrowAmount(this);
    }

    function _borrowBound(bool isBalance) internal view returns (int256) {
        return AaveV3BorrowLibrary._borrowBound(this, isBalance);
    }

    function _supply(uint256 delta) internal {
        AaveV3BorrowLibrary._supply(this, delta);
    }

    function _withdraw(uint256 delta) internal {
        AaveV3BorrowLibrary._withdraw(this, delta);
    }

    function _withdrawBase(uint256 delta) internal {
        AaveV3BorrowLibrary._withdrawBase(this, delta);
    }

    function _borrow(uint256 delta) internal {
        AaveV3BorrowLibrary._borrow(this, delta);
    }

    function _repay(uint256 delta) internal {
        AaveV3BorrowLibrary._repay(this, delta);
    }

    function _claimBorrowRewards() internal {
        AaveV3BorrowLibrary._claimRewards(this);
    }

    uint256[50] private __gap;
}


library AaveV3BorrowLibrary {

    /// get the current liquidity held in aave in side and base tokens
    function _getLiquidity(BorrowModule self) public view returns (uint256 aaveCollateralAmount, uint256 aaveBorrowAmount) {
        IPool aavePool = IPool(IPoolAddressesProvider(self.poolAddressesProvider()).getPool());
        (uint256 aaveCollateralUsd, uint256 aaveBorrowUsd,,,,) = aavePool.getUserAccountData(address(self));

        aaveCollateralAmount = self.usdToBase(aaveCollateralUsd / 100);
        aaveBorrowAmount = self.usdToSide(aaveBorrowUsd / 100);
    }

    /// get borrow amount in usd
    function _borrowAmount(BorrowModule self) public view returns(uint256) {
        IPool aavePool = IPool(IPoolAddressesProvider(self.poolAddressesProvider()).getPool());
        (, uint256 aaveBorrowUsd,,,,) = aavePool.getUserAccountData(address(self));
        return aaveBorrowUsd / 100;
    }

    /// get current health factor
    function _getCurrentHealthFactor(BorrowModule self) public view returns(uint256 _currentHealthFactor) {
        IPool aavePool = IPool(IPoolAddressesProvider(self.poolAddressesProvider()).getPool());
        (,,,,, _currentHealthFactor) = aavePool.getUserAccountData(address(self));
    }

    /// calculate koef for math library, ratio between healthFactor and liquidationThreshold
    /// @param isBalance flag that controls whether we should balance healthFactor or not
    function _borrowBound(BorrowModule self, bool isBalance) public view returns (int256) {
        uint256 healthFactor;
        if (isBalance) {
            //needed hf parameter
            healthFactor = self.neededHealthFactor();
        } else {
            //current hf parameter, without any changes
            healthFactor = _getCurrentHealthFactor(self);
            if (healthFactor == self.MAX_UINT_VALUE()) {
                healthFactor = self.neededHealthFactor();
            }
        }
        return int256(1e18 * healthFactor / self.liquidationThreshold());
    }

    /// supply base token to aave
    function _supply(BorrowModule self, uint256 delta) public {
        // if delta is MAX we want to use all available assets
        uint256 supplyUsdcAmount = (delta == self.MAX_UINT_VALUE() || self.usdToBase(delta) > self.baseToken().balanceOf(address(self)))
                ? self.baseToken().balanceOf(address(self))
                : self.usdToBase(delta);
        if (supplyUsdcAmount == 0) {
            return;
        }

        IPool aavePool = IPool(IPoolAddressesProvider(self.poolAddressesProvider()).getPool());
        // aave pool may be changed, so we need always approve
        self.baseToken().approve(address(aavePool), supplyUsdcAmount);
        aavePool.supply(
            address(self.baseToken()),
            supplyUsdcAmount,
            address(self),
            self.REFERRAL_CODE()
        );
    }

    /// withdraw base token from aave (delta is usd)
    function _withdraw(BorrowModule self, uint256 delta) public {
        uint256 withdrawUsdcAmount = self.usdToBase(delta);
        IPool aavePool = IPool(IPoolAddressesProvider(self.poolAddressesProvider()).getPool());
        aavePool.withdraw(
            address(self.baseToken()),
            withdrawUsdcAmount,
            address(self)
        );
    }

    /// withdraw base token from aave (delta is base token)
    function _withdrawBase(BorrowModule self, uint256 delta) public {
        IPool aavePool = IPool(IPoolAddressesProvider(self.poolAddressesProvider()).getPool());
        aavePool.withdraw(
            address(self.baseToken()),
            delta,
            address(self)
        );
    }

    /// borrow side token from aave
    function _borrow(BorrowModule self, uint256 delta) public {
        uint256 borrowWethAmount = self.usdToSide(delta);
        IPool aavePool = IPool(IPoolAddressesProvider(self.poolAddressesProvider()).getPool());
        aavePool.borrow(
            address(self.sideToken()),
            borrowWethAmount,
            self.INTEREST_RATE_MODE(),
            self.REFERRAL_CODE(),
            address(self)
        );
    }

    /// repay side token to aave
    function _repay(BorrowModule self, uint256 delta) public {
        // if delta is MAX we want to use all available assets
        uint256 repayWethAmount = (delta == self.MAX_UINT_VALUE() || self.usdToSide(delta) > self.sideToken().balanceOf(address(self)))
                ? self.sideToken().balanceOf(address(self))
                : self.usdToSide(delta);
        if (repayWethAmount == 0) {
            return;
        }
        IPool aavePool = IPool(IPoolAddressesProvider(self.poolAddressesProvider()).getPool());
        // aave pool may be changed, so we need always approve
        self.sideToken().approve(address(aavePool), repayWethAmount);
        aavePool.repay(
            address(self.sideToken()),
            repayWethAmount,
            self.INTEREST_RATE_MODE(),
            address(self)
        );
    }

    /// claim aave rewards (now they are not)
    function _claimRewards(BorrowModule self) public {
        // TODO place here
        return;
    }
}

