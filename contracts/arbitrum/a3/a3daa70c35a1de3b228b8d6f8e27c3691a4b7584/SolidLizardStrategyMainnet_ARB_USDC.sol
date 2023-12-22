//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./SolidLizardStrategy.sol";

contract SolidLizardStrategyMainnet_ARB_USDC is SolidLizardStrategy {

    constructor() public {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(0x9cB911Cbb270cAE0d132689cE11c2c52aB2DedBC);
        address gauge = address(0xc43e8F9AE4c1Ef6b8b63CBFEfE8Fe90d375fe11C);
        address lizard = address(0x463913D3a3D3D291667D53B8325c598Eb88D3B0e);
        address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
        address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);

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
        lpLiquidationPath[arb].push(
            ILizardRouter.Route({
                from: weth,
                to: arb,
                stable: false
            })
        );
      
    }
}
