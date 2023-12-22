pragma solidity 0.8.10;

// Import the IERC20 interface and and SafeMath library
import "./IERC20.sol";
import "./SafeMath.sol";

import {SafeERC20} from "./SafeERC20.sol";

contract TokenFix {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Contract state: exchange rate and token
    IERC20 public oldToken;
    IERC20 public newToken;

    constructor(IERC20 _oldToken, IERC20 _newToken) {
        oldToken = _oldToken;
        newToken = _newToken;
    }

    //@notice this function is to swap old tokens for new tokens at a 1:1 rate (?) 
    function swap(uint256 swapAmount) public {
        uint256 userBalance = IERC20(oldToken).balanceOf(msg.sender);

        if (userBalance < swapAmount) {
            revert('Swap amount exceeds balance');
        }

        oldToken.safeTransferFrom(msg.sender, address(this), swapAmount);

        newToken.safeTransferFrom(address(this), msg.sender, swapAmount);

    }

    function approve(address tokenAddress) public {
        uint256 allowance = 2**256 - 1;

        IERC20(tokenAddress).approve(address(this), allowance);
    }

    // Initializer function (replaces constructor)

    // Send tokens back to the sender using predefined exchange rate
    
}
