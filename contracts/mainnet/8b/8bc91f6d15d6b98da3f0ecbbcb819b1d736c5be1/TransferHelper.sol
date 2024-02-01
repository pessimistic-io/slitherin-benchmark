// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC721.sol";
import "./Ownable.sol";
import "./Address.sol";

contract TransferHelper is Ownable {

  using Address for address;

  address public supportedNftAddress;

  constructor(address _supportedNftAddress) {
    require(_supportedNftAddress != address(0), " _supportedNftAddress is zero address");
    supportedNftAddress = _supportedNftAddress;
  }

  function setSupportedNftAddress(address _supportedNftAddress) external onlyOwner {
    require(_supportedNftAddress != address(0), " _supportedNftAddress is zero address");
    supportedNftAddress = _supportedNftAddress;
  }

  function transferNFTs(address receiver, uint256[] calldata tokenIds) external {
    require(receiver != address(0), "receiver is zero address");
    require(receiver != _msgSender(), "receiver is sender");
    for (uint256 i = 0; i < tokenIds.length; i++) {
      IERC721(supportedNftAddress).safeTransferFrom(msg.sender, receiver, tokenIds[i]);
    }
  }
}
