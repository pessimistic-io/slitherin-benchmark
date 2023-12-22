//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./SolidLizardStrategy.sol";

contract SolidLizardStrategyMainnet_wETH_USDC is SolidLizardStrategy {

    constructor() public {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(0xe20F93279fF3538b1ad70D11bA160755625e3400);
        address gauge = address(0x0322CEbACF1f235913bE3FCE407F9F81632ede8B);
        address lizard = address(0x463913D3a3D3D291667D53B8325c598Eb88D3B0e);
        address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

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
      
    }
}
