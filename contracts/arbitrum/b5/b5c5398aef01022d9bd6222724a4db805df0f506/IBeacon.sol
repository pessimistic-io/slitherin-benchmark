// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC1155Upgradeable.sol";

interface IBeacon is IERC1155Upgradeable {
    // Returns the type of this token. 1 corresponds to founding characters
    //
    function getTokenType(uint256 _tokenId) external view returns(uint8);

    function mintFungibles(address _owner, uint256 _id, uint256 _amount) external returns (uint256);
}
