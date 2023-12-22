// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./Land.sol";

contract LandFix {
    Land public land;

    constructor(address _land) {
        land = Land(_land);
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) public view returns (uint256) {
        if (index < land.balanceOf(owner)) {
            return land.tokenOfOwnerByIndex(owner, index);
        }
        return 0;
    }

    function upgradeSafe(uint256 _tokenId) public returns (bool) {
        if (land.totalSupply() == 0) return false;
        return land.upgradeSafe(_tokenId);
    }
}

