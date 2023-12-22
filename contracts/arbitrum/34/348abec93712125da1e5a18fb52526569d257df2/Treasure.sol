// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IERC20 } from "./IERC20.sol";
import { IERC721 } from "./IERC721.sol";
import { IERC1155 } from "./IERC1155.sol";

contract Treasure {
  bytes32 public immutable secretHash;

  constructor(bytes32 _secretHash) {
    secretHash = _secretHash;
  }

  modifier validate(string memory _secret) {
    require(keccak256(abi.encodePacked(_secret)) == secretHash, "Incorrect secret");
    _;
  }

  function withdrawErc20(address _token, uint256 _amount, string memory _secret) external validate(_secret) {
    IERC20(_token).transfer(msg.sender, _amount);
  }

  function withdrawErc721(address _token, uint256 _tokenId, string memory _secret) external validate(_secret) {
    IERC721(_token).transferFrom(address(this), msg.sender, _tokenId);
  }

  function withdrawErc1155(address _token, uint256 _tokenId, uint256 _amount, string memory _secret) external validate(_secret) {
    IERC1155(_token).safeTransferFrom(address(this), msg.sender, _tokenId, _amount, "");
  }

  function withdrawEth(string memory _secret) external validate(_secret) {
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    require(success, "Failed to withdraw ETH from contract"); 
  }

  receive() external payable {}
  fallback() external payable {}
}
