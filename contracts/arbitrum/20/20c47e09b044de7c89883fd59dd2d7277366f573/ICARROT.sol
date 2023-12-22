// SPDX-License-Identifier: MIT
import "./IERC20.sol";
pragma solidity 0.8.15;

interface ICARROT is IERC20 {
    function burn(address from, uint256 amount) external;

    function mint(address to, uint256 amount) external;

    function balanceOf(address account_) external view returns (uint256);

}
