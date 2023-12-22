// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "./IERC20.sol";

interface IGFly is IERC20 {
    function MAX_SUPPLY() external returns (uint256);

    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;

    function addMinter(address minter) external;
}

