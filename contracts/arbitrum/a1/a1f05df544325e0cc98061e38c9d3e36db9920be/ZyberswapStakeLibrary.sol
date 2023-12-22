// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CommonModule.sol";
import "./Zyberswap.sol";

import "./console.sol";

abstract contract StakeModule is CommonModule {

    IZyberRouter02 public router;
    IZyberChef public chef;
    IZyberPair public pair;
    IERC20 public zybToken;
    uint256 public pid;
    uint256 public allowedStakeSlippageBp;

    function _getStakeLiquidity() internal view returns (uint256 wethBalance, uint256 usdcBalance) {
        return ZyberswapStakeLibrary._getLiquidity(this);
    }

    function _pricePool() internal view returns (int256) {
        return ZyberswapStakeLibrary._pricePool(this);
    }

    function _sideAmount() internal view returns (uint256) {
        return ZyberswapStakeLibrary._sideAmount(this);
    }

    function _addLiquidity(uint256 delta) internal {
        ZyberswapStakeLibrary._addLiquidity(this, delta);
    }

    function _removeLiquidity(uint256 delta) internal {
        ZyberswapStakeLibrary._removeLiquidity(this, delta);
    }

    function _claimStakeRewards() internal {
        ZyberswapStakeLibrary._claimRewards(this);
    }

    function getGeneralPoolPrice() public view returns (uint256) {
        return ZyberswapStakeLibrary._poolPrice(this);
    }

    uint256[50] private __gap;
}


library ZyberswapStakeLibrary {

    function _isReverse(StakeModule self) public view returns (bool) {
        return address(self.baseToken()) != self.pair().token0();
    }

    function _getReserves(StakeModule self) public view returns (uint256, uint256) {
        (uint256 reserve0, uint256 reserve1,) = self.pair().getReserves();
        if (_isReverse(self)) {
            return (reserve1, reserve0);
        } else {
            return (reserve0, reserve1);
        }
    }

    function _getLiquidity(StakeModule self) public view returns (uint256 baseBalance, uint256 sideBalance) {
        (uint256 balanceLp,,,) = self.chef().userInfo(self.pid(), address(self));
        (baseBalance, sideBalance) = _getLiquidityByLp(self, balanceLp);
    }

    function _getLiquidityByLp(StakeModule self, uint256 balanceLp) internal view returns (uint256 baseBalance, uint256 sideBalance) {
        (uint256 baseReserve, uint256 sideReserve) = _getReserves(self);
        baseBalance = baseReserve * balanceLp / self.pair().totalSupply();
        sideBalance = sideReserve * balanceLp / self.pair().totalSupply();
    }

    function _sideAmount(StakeModule self) public view returns (uint256) {
        (uint256 balanceLp,,,) = self.chef().userInfo(self.pid(), address(self));
        (, uint256 sideBalance) = _getLiquidityByLp(self, balanceLp);
        return self.sideToUsd(sideBalance);
    }

    function _pricePool(StakeModule self) public view returns (int256) {
        (uint256 baseReserve, uint256 sideReserve) = _getReserves(self);
        return int256(self.baseToUsd(baseReserve) * 1e18 / self.sideToUsd(sideReserve));
    }

    // TODO при расчёте учитывается комиссия. Нужно переделать на расчёт без комиссии для всех v2 стратегий.
    // TODO Если делать через резервы, то формула работает не для всех пулов
    function _poolPrice(StakeModule self) public view returns (uint256) {
        return ZyberswapLibrary.getAmountsOut(
            self.router(),
            address(self.sideToken()),
            address(self.baseToken()),
            self.sideDecimals()
        );
    }

    function _isSamePrices(StakeModule self) public view returns (bool) {
        uint256 poolPrice = _poolPrice(self);
        uint256 oraclePrice = self.usdToBase(self.sideToUsd(self.sideDecimals()));
        uint256 deltaPrice;
        if (poolPrice > oraclePrice) {
            deltaPrice = poolPrice - oraclePrice;
        } else {
            deltaPrice = oraclePrice - poolPrice;
        }

        return (deltaPrice * 10000 / oraclePrice <= self.allowedStakeSlippageBp());
    }

    function _addLiquidity(StakeModule self, uint256 delta) public {
        if (self.baseToken().balanceOf(address(self)) == 0 || self.sideToken().balanceOf(address(self)) == 0) {
            return;
        }

        uint256 baseAmount = self.baseToken().balanceOf(address(self)) - (delta == self.MAX_UINT_VALUE() ? 0 : self.usdToBase(delta));
        uint256 sideAmount = self.sideToken().balanceOf(address(self));

        if (self.baseToUsd(baseAmount) <= 10 ** 2 || self.sideToUsd(sideAmount) <= 10 ** 2 || !_isSamePrices(self)) {
            return;
        }

        // add liquidity
        bool isReverse = _isReverse(self);
        self.baseToken().approve(address(self.router()), baseAmount);
        self.sideToken().approve(address(self.router()), sideAmount);
        self.router().addLiquidity(
            isReverse ? address(self.sideToken()) : address(self.baseToken()),
            isReverse ? address(self.baseToken()) : address(self.sideToken()),
            isReverse ? sideAmount : baseAmount,
            isReverse ? baseAmount : sideAmount,
            0,
            0,
            address(self),
            block.timestamp
        );

        // stake
        uint256 balanceLp = self.pair().balanceOf(address(self));
        self.pair().approve(address(self.chef()), balanceLp);
        self.chef().deposit(self.pid(), balanceLp);
    }

    function _removeLiquidity(StakeModule self, uint256 delta) public {
        (uint256 balanceLp,,,) = self.chef().userInfo(self.pid(), address(self));
        if (delta == 0 || balanceLp == 0 || !_isSamePrices(self)) {
            return;
        }

        uint256 lpForUnstake;
        if (delta == self.MAX_UINT_VALUE()) {
            lpForUnstake = balanceLp;
        } else {
            uint256 sideDelta = self.usdToSide(delta);
            (, uint256 sideBalance) = _getLiquidityByLp(self, balanceLp);
            lpForUnstake = sideDelta * balanceLp / sideBalance + 1;
            if (lpForUnstake > balanceLp) {
                lpForUnstake = balanceLp;
            }
        }

        // unstake
        self.chef().withdraw(self.pid(), lpForUnstake);

        // remove liquidity
        bool isReverse = _isReverse(self);
        self.pair().approve(address(self.router()), lpForUnstake);
        self.router().removeLiquidity(
            isReverse ? address(self.sideToken()) : address(self.baseToken()),
            isReverse ? address(self.baseToken()) : address(self.sideToken()),
            lpForUnstake,
            0,
            0,
            address(self),
            block.timestamp
        );
    }

    function _claimRewards(StakeModule self) public {
        // claim rewards
        (uint256 balanceLp,,,) = self.chef().userInfo(self.pid(), address(self));
        if (balanceLp > 0) {
            self.chef().deposit(self.pid(), 0);
        }

        // sell rewards
        uint256 zybBalance = self.zybToken().balanceOf(address(self));
        if (zybBalance > 0) {
            uint256 amountOut = ZyberswapLibrary.getAmountsOut(
                self.router(),
                address(self.zybToken()),
                address(self.baseToken()),
                zybBalance
            );

            if (amountOut > 0) {
                ZyberswapLibrary.singleSwap(
                    self.router(),
                    address(self.zybToken()),
                    address(self.baseToken()),
                    zybBalance,
                    amountOut * 99 / 100,
                    address(this)
                );
            }
        }
    }
}

