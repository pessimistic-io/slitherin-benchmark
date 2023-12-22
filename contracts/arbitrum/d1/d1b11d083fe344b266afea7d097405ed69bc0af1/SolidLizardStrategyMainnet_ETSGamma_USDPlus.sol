//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./SolidLizardStrategy.sol";

contract SolidLizardStrategyMainnet_ETSGamma_USDPlus is SolidLizardStrategy {

    constructor() public {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(0x97e5f60fA17816011039B908C19Fa4B43DE73731);
        address gauge = address(0xF5E17c2a60D4eF718F6b233d284978BEEb060eD6);
        address lizard = address(0x463913D3a3D3D291667D53B8325c598Eb88D3B0e);
        address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        address etsGamma = address(0x813fFCC4Af3e810E6b447235cC88A02f00454453);
        address usdPlus = address(0xe80772Eaf6e2E18B651F160Bc9158b2A5caFCA65);
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
        lpLiquidationPath[usdPlus].push(
            ILizardRouter.Route({
                from: weth,
                to: usdc,
                stable: false
            })
        );
        lpLiquidationPath[usdPlus].push(
            ILizardRouter.Route({
                from: usdc,
                to: usdPlus,
                stable: true
            })
        );
        lpLiquidationPath[etsGamma].push(
            ILizardRouter.Route({
                from: weth,
                to: usdc,
                stable: false
            })
        );
        lpLiquidationPath[etsGamma].push(
            ILizardRouter.Route({
                from: usdc,
                to: usdPlus,
                stable: true
            })
        );
        lpLiquidationPath[etsGamma].push(
            ILizardRouter.Route({
                from: usdPlus,
                to: etsGamma,
                stable: true
            })
        );
    }
}
