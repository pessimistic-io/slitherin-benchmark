// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IERC20.sol";
import "./ISwapRouter.sol";
import "./ArbitrumDeriBurnerStorage.sol";

contract ArbitrumDeriBurnerImplementation is ArbitrumDeriBurnerStorage {

    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant DERI = 0x21E60EE73F17AC0A411ae5D690f908c3ED66Fe12;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant l2GatewayRouter = 0x5288c571Fd7aD117beA99bF60FE0846C4E84F933;
    address public constant L1_DERI = 0xA487bF43cF3b10dffc97A9A744cbB7036965d3b9;
    address public constant L1_DEADLOCK = 0x000000000000000000000000000000000000dEaD;

    function approveSwapRouterForUsdc() external _onlyAdmin_ {
        IERC20(USDC).approve(swapRouter, type(uint256).max);
    }

    function buyDeriForBurn(uint256 usdcAmount, uint256 minDeriAmount) external _onlyAdmin_ {
        require(usdcAmount > 0, 'usdcAmount <= 0');
        require(IERC20(USDC).balanceOf(address(this)) >= usdcAmount, 'Insufficient USDC');

        ISwapRouter(swapRouter).exactInput(ISwapRouter.ExactInputParams({
            path: abi.encodePacked(USDC, uint24(500), WETH, uint24(3000), DERI),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: usdcAmount,
            amountOutMinimum: minDeriAmount
        }));
    }

    function burn() external _onlyAdmin_ {
        uint256 balance = IERC20(DERI).balanceOf(address(this));
        if (balance > 0) {
            IL2GatewayRouter(l2GatewayRouter).outboundTransfer(
                L1_DERI,
                L1_DEADLOCK,
                balance,
                ''
            );
        }
    }

}

interface IL2GatewayRouter {
    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external payable returns (bytes memory);
}

