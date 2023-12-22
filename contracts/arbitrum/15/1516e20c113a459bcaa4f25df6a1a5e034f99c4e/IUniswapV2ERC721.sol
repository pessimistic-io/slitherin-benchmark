// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./IERC721.sol";
import "./IERC721Metadata.sol";

interface IUniswapV2ERC721 is IERC721, IERC721Metadata {
    function decimals() external view returns (uint8);

    function liquidityOf(uint256 tokenId) external view returns (uint256);

    function totalLiquidityOf(address owner) external view returns (uint256);

    function tokenIdCounter() external view returns (uint256);
}

