// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

import "./ERC20_IERC20Upgradeable.sol";


interface IDCT is IERC20Upgradeable {
    function burn(address _account, uint256 _amount) external;
    function mint(address _account, uint256 _amount) external;
}

