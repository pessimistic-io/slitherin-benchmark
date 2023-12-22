// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "./LizardStrategyBase.sol";
import "./IGaugeRamses.sol";
import "./IPairRamses.sol";
import "./IRouterRamses.sol";

contract LizardStrategyRamsesV4 is LizardStrategyBase {
    IPairRamses public ramsesPair;
    IRouterRamses public ramsesRouter;
    IGaugeRamses public ramsesGauge;
    IERC20 public ramsesToken;
    bool public isStable;

    function _localInitialize() internal override {
        ramsesRouter = IRouterRamses(
            0xAAA87963EFeB6f7E0a2711F397663105Acb1805e
        );
        ramsesGauge = IGaugeRamses(0xDBA865F11bb0a9Cd803574eDd782d8B26Ee65767);
        ramsesToken = IERC20(0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418);
        ramsesPair = IPairRamses(0x5513a48F3692Df1d9C793eeaB1349146B2140386);
        isStable = false;

        baseToken = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8); //usdc
        baseDecimals = 10 ** 6;

        maximumMint = 500000 * baseDecimals;

        sideToken = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); //WETH
        sideDecimals = 10 ** 18;

        uniswapPoolFee = 500; // USDC/WETH is safe pair so 0.05% maximum fees
    }

    function _localGiveAllowances() internal override {
        ramsesPair.approve(address(ramsesGauge), type(uint256).max);
        ramsesPair.approve(address(ramsesRouter), type(uint256).max);
        sideToken.approve(address(ramsesRouter), type(uint256).max);
        baseToken.approve(address(ramsesRouter), type(uint256).max);
    }

    function _localPairBalances()
        internal
        view
        override
        returns (uint256 baseBalance, uint256 sideBalance)
    {
        uint256 amount = ramsesGauge.balanceOf(address(this)) +
            ramsesPair.balanceOf(address(this));
        uint256 totalSupply = ramsesPair.totalSupply();
        if (totalSupply == 0) return (0, 0);
        (uint256 reserve0, uint256 reserve1, ) = ramsesPair.getReserves();
        if (address(baseToken) != ramsesPair.token0()) {
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
        return ramsesPair.getAmountOut(amount, address(inToken));
    }

    function _localPairGetReserves()
        internal
        view
        override
        returns (uint256 baseReserve, uint256 sideReserve)
    {
        if (address(baseToken) != ramsesPair.token0())
            (sideReserve, baseReserve, ) = ramsesPair.getReserves();
        else (baseReserve, sideReserve, ) = ramsesPair.getReserves();
    }

    function _localClaimRewards() internal override returns (uint256) {
        uint256 balanceLp = ramsesGauge.balanceOf(address(this));
        if (balanceLp > 0) {
            address[] memory tokens = new address[](1);
            tokens[0] = address(ramsesToken);
            ramsesGauge.getReward(address(this), tokens);
        }

        // sell rewards
        uint256 ramsesBalance = ramsesToken.balanceOf(address(this));
        if (ramsesBalance > 0) {
            IRouterRamses.Route[] memory routes = new IRouterRamses.Route[](1);
            routes[0].from = address(ramsesToken);
            routes[0].to = address(baseToken);
            routes[0].stable = false;

            uint256 amountOut = ramsesRouter.getAmountsOut(
                ramsesBalance,
                routes
            )[1];
            if (amountOut > 0) {
                ramsesToken.approve(address(ramsesRouter), ramsesBalance);
                amountOut = ramsesRouter.swapExactTokensForTokens(
                    ramsesBalance,
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
        bool isReverse = address(baseToken) != ramsesPair.token0();
        ramsesRouter.addLiquidity(
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
        uint256 lpAmount = ramsesPair.balanceOf(address(this));
        // tokenId = 0 because we don't lock it
        ramsesGauge.deposit(lpAmount, 0);
        return lpAmount;
    }

    function _localRemoveLiquidity(
        uint256 amountSide
    ) internal override returns (uint256 lpForUnstake) {
        bool isReverse = address(baseToken) != ramsesPair.token0();

        if (amountSide < type(uint256).max) {
            (uint256 reserve0, uint256 reserve1, ) = ramsesPair.getReserves();
            lpForUnstake =
                (amountSide * ramsesPair.totalSupply()) /
                (isReverse ? reserve0 : reserve1) +
                1;
        } else {
            lpForUnstake =
                ramsesGauge.balanceOf(address(this)) +
                ramsesPair.balanceOf(address(this));
        }

        {
            uint256 lpForWithdraw = Math.min(
                lpForUnstake,
                ramsesGauge.balanceOf(address(this))
            );
            if (lpForWithdraw > 0) ramsesGauge.withdraw(lpForWithdraw);
        }
        lpForUnstake = Math.min(
            lpForUnstake,
            ramsesPair.balanceOf(address(this))
        );
        if (lpForUnstake > 0) {
            ramsesRouter.removeLiquidity(
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

