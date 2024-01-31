// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8;

import "./IERC1155Upgradeable.sol";

interface IERC1155V0 is IERC1155Upgradeable {}

interface IERC1155V1 is IERC1155Upgradeable {
    function burn(
        address account,
        uint256 id,
        uint256 value
    ) external;

    function burnBatch(
        address account,
        uint256[] memory ids,
        uint256[] memory values
    ) external;
}

interface IERC1155SupplyV0 is IERC1155V0 {
    /**
     * @dev Total amount of tokens in with a given id.
     */
    function totalSupply(uint256 id) external view returns (uint256);

    /**
     * @dev Indicates whether any token exist with a given id, or not.
     */
    function exists(uint256 id) external view returns (bool);
}

interface IERC1155SupplyV1 is IERC1155SupplyV0 {
    /**
     * @dev Amount of unique tokens minted.
     */
    function getLargestTokenId() external view returns (uint256);
}

interface IERC1155SupplyV2 is IERC1155V1 {
    /**
     * @dev Total amount of tokens in with a given id.
     */
    function totalSupply(uint256 id) external view returns (uint256);

    /**
     * @dev Indicates whether any token exist with a given id, or not.
     */
    function exists(uint256 id) external view returns (bool);

    /**
     * @dev Amount of unique tokens minted.
     */
    function getLargestTokenId() external view returns (uint256);
}

