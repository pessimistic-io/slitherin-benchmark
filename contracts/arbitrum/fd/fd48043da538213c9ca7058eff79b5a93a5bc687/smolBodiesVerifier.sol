//SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.17;

import "./ERC721.sol";
import "./IERC721Enumerable.sol";

interface iBodiesFarm {
  function ownsToken(address _collection, address _owner, uint256 _tokenId) external view returns (bool);
}

contract smolBodiesVerifier {
    iBodiesFarm private farm;
    IERC721Enumerable private bodies;

    constructor() {
        farm = iBodiesFarm(0xEc895f620D1c103d5Bbc85CcE3b623C958Ce35cC);
        bodies = IERC721Enumerable(0x17DaCAD7975960833f374622fad08b90Ed67D1B5);
    }

    function balanceOf(address owner) external view returns (uint256) {
        uint256 balance = bodies.balanceOf(owner);

        if (balance > 0) {
            return balance;
        }

        require(balance > 0, "No Smol Bodies Found.");

        uint256 supply = bodies.totalSupply();

        // If no balance, loop through farmers to see if one matches the owner being requested.
        for (uint256 index = 0; index < supply; index++) {
            if (ownerOf(index) == owner) {
                return 1;
            }
        }

        return 0;
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = bodies.ownerOf(tokenId);

        if (owner != address(farm)) {
            return owner;
        }

        bool isOwner = farm.ownsToken(address(bodies), msg.sender, tokenId);

        return isOwner ? msg.sender : address(0);
    }
}
