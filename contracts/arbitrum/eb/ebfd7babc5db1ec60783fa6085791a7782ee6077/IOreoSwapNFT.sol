// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;

import "./IERC721.sol";
import "./IERC721Metadata.sol";
import "./IERC721Enumerable.sol";

interface IOreoSwapNFT is IERC721, IERC721Metadata, IERC721Enumerable {
  // getter

  function oreoNames(uint256 tokenId) external view returns (string calldata);

  function categoryInfo(uint256 tokenId)
    external
    view
    returns (
      string calldata,
      string calldata,
      uint256
    );

  function oreoswapNFTToCategory(uint256 tokenId) external view returns (uint256);

  function categoryToOreoSwapNFTList(uint256 categoryId) external view returns (uint256[] memory);

  function currentTokenId() external view returns (uint256);

  function currentCategoryId() external view returns (uint256);

  function categoryURI(uint256 categoryId) external view returns (string memory);

  function getOreoNameOfTokenId(uint256 tokenId) external view returns (string memory);

  // setter
  function mint(address _to, uint256 _categoryId) external returns (uint256);

  function mintBatch(
    address _to,
    uint256 _categoryId,
    uint256 _size
  ) external returns (uint256[] memory);
}

