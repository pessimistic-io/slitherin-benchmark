// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

// import "./Bank.sol";

struct Stake {
    uint16 tokenId;
    uint80 value;
    address owner;
}

interface ISpaceShip {
  function addManyToBankAndPack(address account, uint16[] calldata tokenIds) external;
  function randomAlienOwner(uint256 rand) external view returns (address);
  function bank(uint256) external view returns(uint16, uint80, address);
  function totalHeartEarned() external view returns(uint256);
  function lastClaimTimestamp() external view returns(uint256);
  function setOldTokenInfo(uint256 _tokenId) external;
  
  function pack(uint256, uint256) external view returns(Stake memory);
  function packIndices(uint256) external view returns(uint256);

}
