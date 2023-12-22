//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.18;

import "./ERC20_IERC20Upgradeable.sol";

interface IRexbit is IERC20Upgradeable {
    event PriceChanged(uint256 oldPrice, uint256 newPrice, uint256 time);

    function price() external view returns (uint256);

    function decimals() external view returns (uint256);

    function updatePrice(uint256 newPrice) external;

    function mint(address to, uint256 value) external;
}

