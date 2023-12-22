//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./SolidLizardStrategy.sol";

contract SolidLizardStrategyMainnet_LUSD_USDC is SolidLizardStrategy {

    constructor() public {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(0xB1E9b823295B3C69ac651C05D987B67189ff20AD);
        address gauge = address(0xa4f536393E277DC63ECfa869d901b4f81cc5462C);
        address lizard = address(0x463913D3a3D3D291667D53B8325c598Eb88D3B0e);
        address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
        address lusd = address(0x93b346b6BC2548dA6A1E7d98E9a421B42541425b);

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
        lpLiquidationPath[lusd].push(
            ILizardRouter.Route({
                from: weth,
                to: usdc,
                stable: false
            })
        );
        lpLiquidationPath[lusd].push(
            ILizardRouter.Route({
                from: usdc,
                to: lusd,
                stable: true
            })
        );
    }
}
