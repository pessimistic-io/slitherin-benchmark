// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IERC721Bound {
  function unbind(
    address[] calldata _addresses,
    uint256[] calldata _tokenIds
  ) external;

  function unbind(address _addr, uint256 _tokenId) external;

  function isUnbound(
    address _addr,
    uint256 _tokenId
  ) external view returns (bool);
}

