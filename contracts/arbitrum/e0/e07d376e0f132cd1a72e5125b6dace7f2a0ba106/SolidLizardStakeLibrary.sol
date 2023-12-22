// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CommonModule.sol";
import "./SolidLizard.sol";
import "./IStaker.sol";

import "./console.sol";

abstract contract StakeModule is CommonModule {

    ILizardRouter01 public router;
    ILizardGauge public gauge;
    ILizardPair public pair;
    IERC20 public slizToken;
    bool public isStable;
    bool public isStableReward0;
    uint256 public allowedStakeSlippageBp;
    IStaker public staker;

    function _getStakeLiquidity() internal view returns (uint256 wethBalance, uint256 usdcBalance) {
        return SolidLizardStakeLibrary._getLiquidity(this);
    }

    function _pricePool() internal view returns (int256) {
        return SolidLizardStakeLibrary._pricePool(this);
    }

    function _sideAmount() internal view returns (uint256) {
        return SolidLizardStakeLibrary._sideAmount(this);
    }

    function _addLiquidity(uint256 delta) internal {
        SolidLizardStakeLibrary._addLiquidity(this, delta);
    }

    function _removeLiquidity(uint256 delta) internal {
        SolidLizardStakeLibrary._removeLiquidity(this, delta);
    }

    function _claimStakeRewards() internal {
        SolidLizardStakeLibrary._claimRewards(this);
    }

    function getGeneralPoolPrice() public view returns (uint256) {
        return SolidLizardStakeLibrary._poolPrice(this);
    }

    uint256[49] private __gap;
}


library SolidLizardStakeLibrary {

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
        uint256 balanceLp = self.gauge().balanceOf(address(self.staker()));
        (baseBalance, sideBalance) = _getLiquidityByLp(self, balanceLp);
    }

    function _getLiquidityByLp(StakeModule self, uint256 balanceLp) internal view returns (uint256 baseBalance, uint256 sideBalance) {
        (uint256 baseReserve, uint256 sideReserve) = _getReserves(self);
        baseBalance = baseReserve * balanceLp / self.pair().totalSupply();
        sideBalance = sideReserve * balanceLp / self.pair().totalSupply();
    }

    function _sideAmount(StakeModule self) public view returns (uint256) {
        uint256 balanceLp = self.gauge().balanceOf(address(self.staker()));
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
        return self.pair().getAmountOut(self.sideDecimals(), address(self.sideToken()));
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
            self.isStable(),
            isReverse ? sideAmount : baseAmount,
            isReverse ? baseAmount : sideAmount,
            0,
            0,
            address(self),
            block.timestamp
        );

        // stake
        uint256 balanceLp = self.pair().balanceOf(address(self));
        self.pair().approve(address(self.staker()), balanceLp);
        self.staker().deposit(address(self.gauge()), balanceLp, address(self.pair()));
    }

    function _removeLiquidity(StakeModule self, uint256 delta) public {
        uint256 balanceLp = self.gauge().balanceOf(address(self.staker()));
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
        self.staker().withdraw(address(self.gauge()), lpForUnstake, address(self.pair()));

        // remove liquidity
        bool isReverse = _isReverse(self);
        self.pair().approve(address(self.router()), lpForUnstake);
        self.router().removeLiquidity(
            isReverse ? address(self.sideToken()) : address(self.baseToken()),
            isReverse ? address(self.baseToken()) : address(self.sideToken()),
            self.isStable(),
            lpForUnstake,
            0,
            0,
            address(self),
            block.timestamp
        );
    }

    function _claimRewards(StakeModule self) public {
        // claim rewards
        uint256 balanceLp = self.gauge().balanceOf(address(self.staker()));
        if (balanceLp > 0) {
            address[] memory tokens = new address[](1);
            tokens[0] = address(self.slizToken());
            self.staker().harvestRewards(address(self.gauge()), tokens);
        }

        // sell rewards
        uint256 slizBalance = self.slizToken().balanceOf(address(self));
        if (slizBalance > 0) {
            uint256 amountOut = SolidLizardLibrary.getAmountsOut(
                self.router(),
                address(self.slizToken()),
                address(self.baseToken()),
                self.isStableReward0(),
                slizBalance
            );

            if (amountOut > 0) {
                SolidLizardLibrary.singleSwap(
                    self.router(),
                    address(self.slizToken()),
                    address(self.baseToken()),
                    self.isStableReward0(),
                    slizBalance,
                    amountOut * 99 / 100,
                    address(this)
                );
            }
        }
    }
}

