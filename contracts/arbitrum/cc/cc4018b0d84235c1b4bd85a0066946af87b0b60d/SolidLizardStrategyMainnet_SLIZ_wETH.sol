//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./SolidLizardStrategy.sol";

contract SolidLizardStrategyMainnet_SLIZ_wETH is SolidLizardStrategy {

    constructor() public {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(0x751F3B8ca139bC1F3482b193297485f14208826a);
        address gauge = address(0x549855586afc1283E90295088ba5Eb51E7236ae8);
        address lizard = address(0x463913D3a3D3D291667D53B8325c598Eb88D3B0e);
        address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

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
        lpLiquidationPath[lizard].push(
            ILizardRouter.Route({
                from: weth,
                to: lizard,
                stable: false
            })
        );
      
    }
}
