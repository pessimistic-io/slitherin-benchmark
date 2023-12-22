// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface ICreditToken {
   function burn(address account, uint256 id, uint256 value) external;
   function burnBatch(address account, uint256[] memory ids, uint256[] memory values) external;
   function mint(address to, uint256 id, uint256 value) external;
   function mintBatch(
      address to,
      uint256[] memory ids,
      uint256[] memory amounts
   ) external;
   function balanceOf(address user, uint256 tokenId) external view returns(uint256);
}

