// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 */
interface IUSDT {
    function name() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external returns (uint);

    function balances(address) external returns (uint);

    function balanceOf(address _owner) external returns (uint balance);

    function allowance(address owner, address spender) external returns (uint);

    function allowed(address, address) external returns (uint);

    function approve(address spender, uint value) external;

    function basisPointsRate() external view returns (uint256);

    function maximumFee() external view returns (uint256);

    function transfer(address to, uint value) external;

    function transferFrom(address from, address to, uint value) external;

    function setParams(uint newBasisPoints, uint newMaxFee) external;
}
