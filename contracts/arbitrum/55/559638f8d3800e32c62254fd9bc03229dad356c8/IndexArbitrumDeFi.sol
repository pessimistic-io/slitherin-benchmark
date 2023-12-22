// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";

import { IndexStrategyUpgradeable } from "./IndexStrategyUpgradeable.sol";
import { IChainlinkAggregatorV3 } from "./IChainlinkAggregatorV3.sol";
import { Constants } from "./Constants.sol";
import { Errors } from "./Errors.sol";
import { SwapAdapter } from "./SwapAdapter.sol";

contract IndexArbitrumDeFi is UUPSUpgradeable, IndexStrategyUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IndexStrategyInitParams calldata initParams)
        external
        initializer
    {
        __UUPSUpgradeable_init();
        __IndexStrategyUpgradeable_init(initParams);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

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

        uint256 amountWNATIVE = _getAmountWNATIVEFromExactIndex(totalSupply);

        uint256 priceWNATIVE = oracle.getPrice(
            wNATIVE,
            maximize,
            includeAmmPrice
        );

        return (amountWNATIVE * priceWNATIVE) / Constants.DECIMALS;
    }

    function addSwapRoute(
        address token0,
        address token1,
        address router,
        SwapAdapter.DEX dex,
        address pair
    ) external onlyOwner {
        SwapAdapter.PairData memory pairData = SwapAdapter.PairData(
            pair,
            abi.encode(0)
        );

        addSwapRoute(token0, token1, router, dex, pairData);
    }

    function addSwapRoute(
        address token0,
        address token1,
        address router,
        SwapAdapter.DEX dex,
        address pair,
        uint256 binStep
    ) external onlyOwner {
        SwapAdapter.PairData memory pairData = SwapAdapter.PairData(
            pair,
            abi.encode(binStep)
        );

        addSwapRoute(token0, token1, router, dex, pairData);
    }
}

