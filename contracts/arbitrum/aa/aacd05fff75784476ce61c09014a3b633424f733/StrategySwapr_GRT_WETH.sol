// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.16;

import "./SwaprLPStrategy.sol";

contract StrategySwapr_GRT_WETH is SwaprLPStrategy {

    address grt_weth_diff;

    function initializeStrategy(
        address _store,
        address _vault
    ) public initializer {
        address StakeRewardPool = address(0x0a781dEa2782B890bF04e2EA457A81f5DAe8182F);
        address grt_weth_lp = address(0x828Ec866FA3c4B2dcD6bbe7f2B5C147514936aa8);
        address grt = address(0x23A941036Ae778Ac51Ab04CEa08Ed6e2FE103614);
        address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        address swpr = address(0xdE903E2712288A1dA82942DDdF2c20529565aC30);
        __Strategy_init(
            _store, 
            grt_weth_lp, 
            _vault, 
            StakeRewardPool,
            swpr
        );
        routes[grt] = [swpr, weth, grt];
        routes[weth] = [swpr, weth];
    }
}
