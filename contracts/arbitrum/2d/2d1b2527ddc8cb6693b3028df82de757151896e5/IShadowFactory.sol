// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IERC1155Maturity.sol";

interface IShadowFactory is IERC1155Maturity {
    function safeTransferFromByShadow(
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) external;

    function deployShadow(uint256 id) external returns (address shadowToken);

    function computeShadowAddress(uint256 id) external view returns (address);

    function getShadowName(uint256 id) external view returns (string memory);

    function getShadowSymbol(uint256 id) external view returns (string memory);

    function getShadowDecimals(uint256 id) external view returns (uint8);
}

