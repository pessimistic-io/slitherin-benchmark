//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./SolidLizardStrategy.sol";

contract SolidLizardStrategyMainnet_ARB_wETH is SolidLizardStrategy {

    constructor() public {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(0xCeD06c9330B02C378C31c7b12570B1C38AbfcEA6);
        address gauge = address(0xeCEe212b65a54cA7725aA19DCEed45effB3cf385);
        address lizard = address(0x463913D3a3D3D291667D53B8325c598Eb88D3B0e);
        address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
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
        lpLiquidationPath[arb].push(
            ILizardRouter.Route({
                from: weth,
                to: arb,
                stable: false
            })
        );
      
    }
}
