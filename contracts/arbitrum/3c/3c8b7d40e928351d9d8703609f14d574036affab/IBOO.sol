// SPDX-License-Identifier: MIT LICENSE
pragma solidity >0.8.0;
import "./IERC20Upgradeable.sol";

interface IBOO is IERC20Upgradeable {
    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function cap() external view returns (uint256);

    function setAllocationAddress(address fundingAddress, uint256 allocation) external;

    function removeAllocationAddress(address fundingAddress) external;
}

