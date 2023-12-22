// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "./LizardStrategyBase2.sol";
import "./IGaugeChronos.sol";
import "./IPairChronos.sol";
import "./IRouterChronos.sol";
import "./IMaLPNFTChronos.sol";

contract LizardStrategyChronos is LizardStrategyBase2 {
    IPairChronos public chronosPair;
    IRouterChronos public chronosRouter;
    IGaugeChronos public chronosGauge;
    IERC20 public chronosToken;
    bool public isStable;
    IMaLPNFTChronos public maNFTs;

    function _localInitialize() internal override {
        aavePoolAddressesProvider = IPoolAddressesProvider(
            0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb
        );

        chronosRouter = IRouterChronos(
            0xE708aA9E887980750C040a6A2Cb901c37Aa34f3b
        );
        chronosGauge = IGaugeChronos(
            0xdb74aE9C3d1b96326BDAb8E1da9c5e98281d576e
        );
        chronosToken = IERC20(0x15b2fb8f08E4Ac1Ce019EADAe02eE92AeDF06851);
        chronosPair = IPairChronos(0xA2F1C1B52E1b7223825552343297Dc68a29ABecC);
        isStable = false;

        baseToken = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8); //usdc
        baseDecimals = 10 ** 6;

        maximumMint = 500000 * baseDecimals;

        sideToken = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); //WETH
        sideDecimals = 10 ** 18;

        uniswapPoolFee = 500; // USDC/WETH is safe pair so 0.05% maximum fees
        maNFTs = IMaLPNFTChronos(chronosGauge.maNFTs());
    }

    function _localGiveAllowances() internal override {
        chronosPair.approve(address(chronosGauge), type(uint256).max);
        chronosPair.approve(address(chronosRouter), type(uint256).max);
        sideToken.approve(address(chronosRouter), type(uint256).max);
        baseToken.approve(address(chronosRouter), type(uint256).max);
    }

    function _localPairBalances()
        internal
        view
        override
        returns (uint256 baseBalance, uint256 sideBalance)
    {
        uint256 amount = chronosGauge.balanceOf(address(this)) +
            chronosPair.balanceOf(address(this));
        uint256 totalSupply = chronosPair.totalSupply();
        if (totalSupply == 0) return (0, 0);
        (uint256 reserve0, uint256 reserve1, ) = chronosPair.getReserves();
        if (address(baseToken) != chronosPair.token0()) {
            return (
                (reserve1 * amount) / totalSupply,
                (reserve0 * amount) / totalSupply
            );
        } else {
            return (
                (reserve0 * amount) / totalSupply,
                (reserve1 * amount) / totalSupply
            );
        }
    }

    function _localPairGetAmountOut(
        uint256 amount,
        address inToken
    ) internal view override returns (uint256) {
        return chronosPair.getAmountOut(amount, address(inToken));
    }

    function _localPairGetReserves()
        internal
        view
        override
        returns (uint256 baseReserve, uint256 sideReserve)
    {
        if (address(baseToken) != chronosPair.token0())
            (sideReserve, baseReserve, ) = chronosPair.getReserves();
        else (baseReserve, sideReserve, ) = chronosPair.getReserves();
    }

    function _localClaimRewards() internal override returns (uint256) {
        uint256 tokenCount = maNFTs.balanceOf(address(this));
        for (uint256 i = 0; i < tokenCount; i++) {
            uint _tokenId = maNFTs.tokenOfOwnerByIndex(address(this), i);
            if (maNFTs.tokenToGauge(_tokenId) == address(chronosGauge)) {
                chronosGauge.getReward(_tokenId);
            }
        }

        // sell rewards
        uint256 chronosBalance = chronosToken.balanceOf(address(this));
        if (chronosBalance > 0) {
            IRouterChronos.route[] memory routes = new IRouterChronos.route[](
                1
            );
            routes[0].from = address(chronosToken);
            routes[0].to = address(baseToken);
            routes[0].stable = false;

            uint256 amountOut = chronosRouter.getAmountsOut(
                chronosBalance,
                routes
            )[1];
            if (amountOut > 0) {
                chronosToken.approve(address(chronosRouter), chronosBalance);
                amountOut = chronosRouter.swapExactTokensForTokens(
                    chronosBalance,
                    (amountOut * 99) / 100,
                    routes,
                    address(this),
                    block.timestamp
                )[1];

                return amountOut;
            }
        }
        return 0;
    }

    function _localAddLiquidity(
        uint256 baseAmountMax,
        uint256 sideAmountMax
    ) internal override returns (uint256) {
        bool isReverse = address(baseToken) != chronosPair.token0();
        chronosRouter.addLiquidity(
            isReverse ? address(sideToken) : address(baseToken),
            isReverse ? address(baseToken) : address(sideToken),
            isStable,
            isReverse ? sideAmountMax : baseAmountMax,
            isReverse ? baseAmountMax : sideAmountMax,
            0,
            0,
            address(this),
            block.timestamp
        );
        uint256 lpAmount = chronosPair.balanceOf(address(this));

        chronosGauge.deposit(lpAmount);
        return lpAmount;
    }

    function _localRemoveLiquidity(
        uint256 amountSide
    ) internal override returns (uint256 lpForUnstake) {
        bool isReverse = address(baseToken) != chronosPair.token0();

        if (amountSide < type(uint256).max) {
            (uint256 reserve0, uint256 reserve1, ) = chronosPair.getReserves();
            lpForUnstake =
                (amountSide * chronosPair.totalSupply()) /
                (isReverse ? reserve0 : reserve1) +
                1;
        } else {
            lpForUnstake = type(uint256).max;
        }

        if (lpForUnstake > chronosPair.balanceOf(address(this))) {
            uint256 tokenCount = maNFTs.balanceOf(address(this));

            for (uint256 i = tokenCount; i > 0; i--) {
                uint _tokenId = maNFTs.tokenOfOwnerByIndex(
                    address(this),
                    i - 1
                );
                if (maNFTs.tokenToGauge(_tokenId) == address(chronosGauge)) {
                    chronosGauge.withdrawAndHarvest(_tokenId);
                    if (lpForUnstake < type(uint256).max) {
                        if (
                            lpForUnstake <= chronosPair.balanceOf(address(this))
                        ) {
                            break;
                        }
                    }
                }
            }
        }

        lpForUnstake = Math.min(
            lpForUnstake,
            chronosPair.balanceOf(address(this))
        );
        if (lpForUnstake > 0) {
            chronosRouter.removeLiquidity(
                isReverse ? address(sideToken) : address(baseToken),
                isReverse ? address(baseToken) : address(sideToken),
                isStable,
                lpForUnstake,
                0,
                0,
                address(this),
                block.timestamp
            );
        }
        return lpForUnstake;
    }
}

