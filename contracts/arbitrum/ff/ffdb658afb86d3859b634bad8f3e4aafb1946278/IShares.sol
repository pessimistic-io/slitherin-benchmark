// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./IERC1155Upgradeable.sol";

interface IShares is IERC1155Upgradeable {
    function mint(address shareId, address to, uint256 amount) external;

    function burnFrom(
        address shareId,
        address account,
        uint256 amount
    ) external;

    // Get the user's balance under a specific blockNumber
    // If zero blockNumber is passed, it will return the latest balance
    function balanceOf(
        address account,
        uint256 id,
        uint256 blockNumber
    ) external view returns (uint256);

    function balanceOf(
        address account,
        address shareId,
        uint256 blockNumber
    ) external view returns (uint256);

    // Get the total supply under a specific blockNumber
    // If zero blockNumber is passed, it will return the latest total supply
    function totalSupply(
        uint256 id,
        uint256 blockNumber
    ) external view returns (uint256);

    function totalSupply(uint256) external view returns (uint256);

    function totalSupply(
        address shareId,
        uint256 blockNumber
    ) external view returns (uint256);

    // Get the members under a specific blockNumber
    // If zero blockNumber is passed, it will return the latest total supply
    function members(
        uint256 id,
        uint256 blockNumber
    ) external view returns (uint256);

    function members(uint256) external view returns (uint256);

    function members(
        address shareId,
        uint256 blockNumber
    ) external view returns (uint256);

    // Get the total supply under a specific blockNumber
    function convertSharesId(address idaddr) external view returns (uint256);

    /**
     * @dev Indicates whether any token exist with a given id, or not.
     */
    function exists(uint256 id) external view returns (bool);
}

