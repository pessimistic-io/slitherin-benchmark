//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;



import "./IERC20.sol";
import "./SafeERC20.sol";

library TokenTypes {

    /**
     * Wrapper structure for token and an amount
     */
    struct TokenAmount {
        uint112 amount;
        IERC20 token;
    }
    
}
