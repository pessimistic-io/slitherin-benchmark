// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ERC20.sol";
import "./FixedPointMathLib.sol";

import "./IUniswapV2Router02.sol";
// import "sushiswap/protocols/furo/contracts/libraries/UniswapV2Library.sol";

contract Airdrop {
    using FixedPointMathLib for uint256;

    function hunt_for_airdrop(address[] memory tokenAddresses, address dumpAddress) public payable {
        // require( msg.value >= 0.1 ether, "Send 0.1 ETH to hunt for airdrop" );
        IUniswapV2Router02 router = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            address[] memory path = new address[](2);
            path[0] = router.WETH();
            path[1] = tokenAddresses[i];

            // UniswapV2Library.getAmountIn(0.00, reserveIn, reserveOut);
            router.swapETHForExactTokens{value: address(this).balance}(
                0.001 ether, path, address(this), block.timestamp
            );
            ERC20(tokenAddresses[i]).transfer(dumpAddress, 0.001 ether);
            // require(address(this).balance >= balance.divWadDown(2), "Not enough ETH");
        }
    }

    receive() external payable {}
}

