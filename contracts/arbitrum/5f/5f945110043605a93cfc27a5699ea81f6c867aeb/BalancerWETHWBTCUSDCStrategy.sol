// SPDX-License-Identifier: GNU GPLv3
pragma solidity >=0.8.10;

////////////////////////////////////////////////////////////////////////////////////////
//                                                                                    //
//                                                                                    //
//                              #@@@@@@@@@@@@@@@@@@@@&,                               //
//                      .@@@@@   .@@@@@@@@@@@@@@@@@@@@@@@@@@@*                        //
//                  %@@@,    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    //
//               @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                 //
//             @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@               //
//           *@@@#    .@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             //
//          *@@@%    &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//          @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//                                                                                    //
//          (@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,           //
//          (@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,           //
//                                                                                    //
//            &&@    @@   @@      @   @       @       @   @      @@    @&&            //
//            &@@    @@   @@     @@@ @@@     @_@     @@@ @@@     @@@   @@&            //
//           /&&@     &@@@@    @@  @@  @@  @@ ^ @@  @@  @@  @@   @@@   @&&            //
//                                                                                    //
//          @@@@@      @@@%    *@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//          @@@@@      @@@@    %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//          .@@@@      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             //
//            @@@@@  &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@              //
//                (&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&(                 //
//                                                                                    //
//                                                                                    //
////////////////////////////////////////////////////////////////////////////////////////

// Libraries
import {ERC20} from "./ERC20.sol";
import {BalancerBaseStrategy} from "./BalancerBaseStrategy.sol";

// Interfaces
import {IRewardOnlyGauge} from "./IRewardOnlyGauge.sol";
import {IVault} from "./IVault.sol";

/// @title Balancer WETH/WBTC/USDC Strategy
/// @author 0xdapper

contract BalancerWETHWBTCUSDCStrategy is BalancerBaseStrategy {
    constructor()
        BalancerBaseStrategy(
            ERC20(0x64541216bAFFFEec8ea535BB71Fbc927831d0595),
            IRewardOnlyGauge(0x104f1459a2fFEa528121759B238BB609034C2f01),
            0x64541216bafffeec8ea535bb71fbc927831d0595000100000000000000000002,
            "Umami WETH-WBTC-USDC",
            "umWETH-WBTC-USDC"
        )
    {}

    /**
     * @notice return an array of assets' addresses that will be used as input while joining the pool.
     */
    function _getPoolAssets()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory poolAssets = new address[](3);
        poolAssets[0] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        poolAssets[1] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        poolAssets[2] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
        return poolAssets;
    }

    /**
     * @notice called to swap BAL rewards for underlying pool asset which will be used to join the pool for more BPT.
     * @param amountOfBAL amount of BAL tokens to swap
     * @return poolAsset address of the pool asset that we swapped into
     * @return assetAmount amount of pool asset we got from the swap
     */
    function _swapBALForPoolAsset(uint256 amountOfBAL)
        internal
        override
        returns (address, uint256)
    {
        uint256 wethOut = VAULT.swap(
            IVault.SingleSwap({
                poolId: BAL_WETH_POOL,
                kind: IVault.SwapKind.GIVEN_IN,
                assetIn: address(BAL),
                assetOut: address(WETH),
                amount: amountOfBAL,
                userData: hex""
            }),
            IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            0,
            block.timestamp
        );

        return (address(WETH), wethOut);
    }
}

import {Script} from "./Script.sol";

contract BalancerWETHWBTCUSDCStrategyDeployScript is Script {
    function run() external {
        vm.broadcast();
        BalancerWETHWBTCUSDCStrategy strat = new BalancerWETHWBTCUSDCStrategy();
    }
}

