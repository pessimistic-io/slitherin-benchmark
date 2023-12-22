// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./DataTypes.sol";

// be careful to change these varible order(rename or delete), it will affect the storage layout
abstract contract ProfileNFTStorage {
  uint256 internal constant PROFILE_VERSION = 1;
  address public verifier;
  // mintHistory for each wallet, key is wallet address
  mapping(address => uint256) internal _mintWalletHistory;
  // handleRecords for each handle, key is handle hash
  mapping(bytes32 => uint256) internal _handleRecords;
  // profileRecords for each profile, key is profile id
  mapping(uint256 => DataTypes.Profile) internal _profileRecords;
}

