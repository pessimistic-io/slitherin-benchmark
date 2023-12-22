//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import "./ISwapRouter.sol";
import "./TransferHelper.sol";
import "./IWeth.sol";
import "./IGmxExchangeRouter.sol";

// https://onthis.xyz
/*
 .d88b.  d8b   db d888888b db   db d888888b .d8888. 
.8P  Y8. 888o  88    88    88   88    88    88   YP 
88    88 88V8o 88    88    88ooo88    88     8bo.   
88    88 88 V8o88    88    88   88    88       Y8b. 
`8b  d8' 88  V888    88    88   88    88    db   8D 
 `Y88P'  VP   V8P    YP    YP   YP Y888888P  8888Y  
*/

contract L2GmPurchaser is OwnableUpgradeable {
    address public constant UNISWAP_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant GMX_ROUTER =
        0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6;
    address public constant GMX_EXCHANGE_ROUTER =
        0x7C68C7866A64FA2160F78EEaE12217FFbf871fa8;
    address public constant GMX_VAULT =
        0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55;
    address public constant GMX_READER =
        0x22199a49A999c351eF7927602CFB187ec3cae489;
    address public constant MARKET_TOKEN =
        0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;
    uint24 public constant POOL_FEE = 500;
    uint256 public constant EXECUTION_FEE = 0.00748 ether;

    uint256[50] private _gap;

    function initialize() public initializer {
        __Ownable_init();
    }

    /// @notice Used withdrawing native/erc20 tokens from contract(in case if they were accidentally sended)
    function withdrawTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).transfer(to, amount);
        }
    }

    function _createGmxDeposit(
        address maker,
        uint256 amount
    ) private returns (bytes32) {
        IGmxExchangeRouter(GMX_EXCHANGE_ROUTER).sendWnt{value: EXECUTION_FEE}(
            GMX_VAULT,
            EXECUTION_FEE
        );
        IGmxExchangeRouter(GMX_EXCHANGE_ROUTER).sendTokens(
            WETH,
            GMX_VAULT,
            amount
        );

        return
            IGmxExchangeRouter(GMX_EXCHANGE_ROUTER).createDeposit(
                IGmxExchangeRouter.CreateDepositParams(
                    maker,
                    address(0),
                    address(0),
                    MARKET_TOKEN,
                    WETH,
                    USDC,
                    new address[](0),
                    new address[](0),
                    0,
                    false,
                    EXECUTION_FEE,
                    0
                )
            );
    }

    /// @notice Wraps ETH & creates deposit at GMX V2 pool(WETH/USDC);
    /// @return Returns req key from GMX
    function swapAndProvideLiqudity(
        address maker
    ) public payable returns (bytes32) {
        uint256 wethBefore = IWeth(WETH).balanceOf(address(this));
        IWeth(WETH).deposit{value: msg.value}();
        uint256 wethAfter = IWeth(WETH).balanceOf(address(this));
        IERC20(WETH).approve(GMX_ROUTER, type(uint256).max);

        return _createGmxDeposit(maker, wethAfter - wethBefore);
    }

    /// @notice Used for depositing funds that will subsidize execution fees for users
    receive() external payable {}
}

