// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20, ICamelotFactory, ICamelotPair } from "./CamelotInterfaces.sol";

library PriceCalculator {
    ICamelotFactory public constant factory = ICamelotFactory(0x6EcCab422D763aC031210895C81787E87B43A652);
    address public constant USDC_ADDRESS = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant PLS_ADDRESS = 0x51318B7D00db7ACc4026C88c3952B66278B6A67F;
    address public constant DAI_ADDRESS = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    function getPlsInUSDC(uint256 plsAmount) internal view returns (uint256) {
        address wethPlsAdd = factory.getPair(PLS_ADDRESS, WETH_ADDRESS);
        address usdcWethAdd = factory.getPair(WETH_ADDRESS, USDC_ADDRESS);
        ICamelotPair pairWethPls = ICamelotPair(wethPlsAdd);
        ICamelotPair pairUsdcWeth = ICamelotPair(usdcWethAdd);

        uint256 wethAmount = pairWethPls.getAmountOut(plsAmount, PLS_ADDRESS);

        return pairUsdcWeth.getAmountOut(wethAmount, WETH_ADDRESS);
    }
}

