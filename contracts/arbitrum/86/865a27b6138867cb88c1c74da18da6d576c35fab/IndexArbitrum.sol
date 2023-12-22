// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IndexStrategyUpgradeable } from "./IndexStrategyUpgradeable.sol";
import { IChainlinkAggregatorV3 } from "./IChainlinkAggregatorV3.sol";
import { Constants } from "./Constants.sol";
import { Errors } from "./Errors.sol";
import { SwapAdapter } from "./SwapAdapter.sol";

contract IndexArbitrum is IndexStrategyUpgradeable {
    function equityValuation(bool maximize, bool includeAmmPrice)
        public
        view
        override
        returns (uint256)
    {
        uint256 totalSupply = indexToken.totalSupply();

        if (totalSupply == 0) {
            return 0;
        }

        uint256 amountWNATIVEUnit = _getAmountWNATIVEFromExactIndex(
            Constants.PRECISION
        );

        uint256 priceWNATIVE = oracle.getPrice(
            wNATIVE,
            maximize,
            includeAmmPrice
        );

        return
            (amountWNATIVEUnit * priceWNATIVE * totalSupply) /
            (Constants.DECIMALS * Constants.PRECISION);
    }

    function addSwapRoute(
        address token,
        address router,
        SwapAdapter.DEX dex,
        address pair
    ) external onlyOwner {
        SwapAdapter.PairData memory pairData = SwapAdapter.PairData(
            pair,
            abi.encode(0)
        );

        addSwapRoute(token, router, dex, pairData);
    }

    function addSwapRoute(
        address token,
        address router,
        SwapAdapter.DEX dex,
        address pair,
        uint256 binStep
    ) external onlyOwner {
        SwapAdapter.PairData memory pairData = SwapAdapter.PairData(
            pair,
            abi.encode(binStep)
        );

        addSwapRoute(token, router, dex, pairData);
    }

    function addSwapRoute(
        address token,
        address router,
        SwapAdapter.DEX dex,
        address pair,
        address factory
    ) external onlyOwner {
        SwapAdapter.PairData memory pairData = SwapAdapter.PairData(
            pair,
            abi.encode(factory)
        );

        addSwapRoute(token, router, dex, pairData);
    }
}

