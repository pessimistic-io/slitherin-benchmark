// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import { INFTHandler } from "./Camelot.sol";
import "./IERC721.sol";

interface INftTransferHandler is INFTHandler {
  function transferNftPool(address nft, address to, uint tokenId) external;

  error FAILED(string reason);
}

abstract contract NftTransferHandler is INFTHandler, INftTransferHandler {
  bytes4 internal constant _ERC721_RECEIVED = 0x150b7a02;

  function transferNft(address nft, address to, uint tokenId) internal virtual {
    INftTransferHandler(address(this)).transferNftPool(nft, to, tokenId);
  }

  /// @dev Constraint on spNFT._beforeTokenTransfer that requires (!from.isContract() || msg.sender == from). This function should only be called by transferNft
  function transferNftPool(address nft, address to, uint tokenId) external {
    if (msg.sender != address(this)) revert FAILED('NftTransferHandler: FORBIDDEN');
    IERC721(nft).safeTransferFrom(address(this), to, tokenId);
  }

  function onERC721Received(
    address /*operator*/,
    address /*from*/,
    uint256 /*_tokenId*/,
    bytes calldata /*data*/
  ) external virtual override returns (bytes4) {
    return _ERC721_RECEIVED;
  }

  function onNFTHarvest(
    address /*operator*/,
    address /*to*/,
    uint256 /*tokenId*/,
    uint256 /*grailAmount*/,
    uint256 /*xGrailAmount*/
  ) external virtual override returns (bool) {
    return false;
  }

  function onNFTAddToPosition(
    address /*operator*/,
    uint256 /*tokenId*/,
    uint256 /*lpAmount*/
  ) external virtual override returns (bool) {
    return false;
  }

  function onNFTWithdraw(
    address /*operator*/,
    uint256 /*tokenId*/,
    uint256 /*lpAmount*/
  ) external virtual override returns (bool) {
    return false;
  }
}

