// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./ERC20_IERC20.sol";

interface IWrappedERC20 is IERC20 {
    function depositFor(address account, uint256 amount) external returns (bool);
    function withdrawTo(address account, uint256 amount) external returns (bool);
}
