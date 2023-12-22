// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";

/**
 * @dev Interface of the OFT standard
 */
interface ISled is IERC20 {
    function mint(address _to, uint256 amount_) external;
}

