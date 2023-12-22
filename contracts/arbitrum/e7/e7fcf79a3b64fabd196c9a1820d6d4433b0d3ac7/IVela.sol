// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IVELA {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function maxSupply() external view returns (uint256);
}

