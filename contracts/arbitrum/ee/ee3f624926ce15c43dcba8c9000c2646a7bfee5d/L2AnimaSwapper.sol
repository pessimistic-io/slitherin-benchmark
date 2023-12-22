pragma solidity ^0.8.9;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import "./ISushiSwapV2Router.sol";
import "./IMagicSwapV2Router.sol";
import "./IWeth.sol";
import "./IERC20.sol";

// https://onthis.xyz
/*
 .d88b.  d8b   db d888888b db   db d888888b .d8888. 
.8P  Y8. 888o  88    88    88   88    88    88   YP 
88    88 88V8o 88    88    88ooo88    88     8bo.   
88    88 88 V8o88    88    88   88    88       Y8b. 
`8b  d8' 88  V888    88    88   88    88    db   8D 
 `Y88P'  VP   V8P    YP    YP   YP Y888888P  8888Y  
*/

contract L2AnimaSwapper is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    address public constant SUSHI_SWAP_V2_ROUTER =
        0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address public constant MAGIC_SWAP_V2_ROUTER =
        0x23805449f91bB2d2054D9Ba288FdC8f09B5eAc79;

    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant MAGIC = 0x539bdE0d7Dbd336b79148AA742883198BBF60342;
    address public constant ANIMA = 0xcCd05A0fcfc1380e9Da27862Adb2198E58e0D66f;

    uint256 public constant SLIPPAGE = 3;
    uint256[50] private _gap;

    function initialize() public initializer {
        __Ownable_init();
    }

    function _contractTokenBalance(address token) private returns (uint256) {
        return IWeth(token).balanceOf(address(this));
    }

    function withdrawERC20(
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

    function _getTokensPath(
        address token0,
        address token1
    ) private pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = token0;
        path[1] = token1;

        return path;
    }

    function _getMinAmountOut(uint256 amountOut, uint256 slippage) private pure returns(uint256){
        return amountOut - ((amountOut * slippage)) / 100;
    }

    function magicAnimaSwapper(address maker) public payable {
        IWeth(WETH).deposit{value: msg.value}();
        IWeth(WETH).approve(SUSHI_SWAP_V2_ROUTER, _contractTokenBalance(WETH));

        uint256 wethAmountToSwap = _contractTokenBalance(WETH);

        uint[] memory magicAmountsOut = ISushiSwapV2Router(SUSHI_SWAP_V2_ROUTER)
            .getAmountsOut(wethAmountToSwap, _getTokensPath(WETH,MAGIC));

        uint256 magicAmountOutMin = _getMinAmountOut(
            magicAmountsOut[1],
            SLIPPAGE
        );

        ISushiSwapV2Router(SUSHI_SWAP_V2_ROUTER).swapExactTokensForTokens(
            wethAmountToSwap,
            magicAmountOutMin,
            _getTokensPath(WETH,MAGIC),
            address(this),
            block.timestamp
        );

        uint[] memory animaAmountsOut = IMagicSwapV2Router(MAGIC_SWAP_V2_ROUTER)
            .getAmountsOut(_contractTokenBalance(MAGIC), _getTokensPath(MAGIC,ANIMA));

        uint256 animaAmountOutMin = _getMinAmountOut(
            animaAmountsOut[1],
            SLIPPAGE
        );

        IERC20(MAGIC).approve(MAGIC_SWAP_V2_ROUTER, _contractTokenBalance(MAGIC));

        IMagicSwapV2Router(MAGIC_SWAP_V2_ROUTER).swapExactTokensForTokens(
            _contractTokenBalance(MAGIC),
            animaAmountOutMin,
             _getTokensPath(MAGIC,ANIMA),
            maker,
            block.timestamp
        );

         if (_contractTokenBalance(WETH) > 0) {
            IWeth(WETH).transfer(maker, _contractTokenBalance(WETH));
        }
         if (_contractTokenBalance(MAGIC) > 0) {
            IERC20(MAGIC).transfer(maker, _contractTokenBalance(WETH));
        }
    }

    receive() external payable {
        magicAnimaSwapper(msg.sender);
    }
}

