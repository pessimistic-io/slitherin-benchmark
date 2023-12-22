//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./SolidLizardStrategy.sol";

contract SolidLizardStrategyMainnet_agEUR_USDC is SolidLizardStrategy {

    constructor() public {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(0x5cd95bc186E41419e6B48a0153833C8105781292);
        address gauge = address(0x12981565263628164cDFA32290EBCcdbd7e5cCa4);
        address lizard = address(0x463913D3a3D3D291667D53B8325c598Eb88D3B0e);
        address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
        address agEUR = address(0xFA5Ed56A203466CbBC2430a43c66b9D8723528E7);

        SolidLizardStrategy.initializeBaseStrategy(
            _storage,
            underlying,
            _vault,
            gauge
        );

        rewardTokens.push(lizard);
       
        reward2WETH[lizard].push(
            ILizardRouter.Route({
                from: lizard,
                to: weth,
                stable: false
            })
        );
        lpLiquidationPath[usdc].push(
            ILizardRouter.Route({
                from: weth,
                to: usdc,
                stable: false
            })
        );
        lpLiquidationPath[agEUR].push(
            ILizardRouter.Route({
                from: weth,
                to: usdc,
                stable: false
            })
        );
        lpLiquidationPath[agEUR].push(
            ILizardRouter.Route({
                from: usdc,
                to: agEUR,
                stable: false
            })
        );
    }
}
