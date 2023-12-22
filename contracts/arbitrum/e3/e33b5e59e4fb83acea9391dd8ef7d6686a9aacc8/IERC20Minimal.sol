pragma solidity ^0.7.6;

interface IERC20Minimal {
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
}

