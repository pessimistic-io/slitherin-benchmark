// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IERC20.sol";


/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Burnable is IERC20 {
    function burn(uint256 amount) external;

    
}

