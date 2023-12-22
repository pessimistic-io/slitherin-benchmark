// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ERC721} from "./ERC721.sol";
import {LibString} from "./LibString.sol";

contract ERC721Token is ERC721("Test", "TEST") {
    string public constant baseURI = "https://ipfs.io/ipfs/bafkreihx7i5zkwgx5w3fy3t357vrtzqmcihkp6i3rjzzbqn267rm5wuxgy/";

    function mint(address _to, uint256 _tokenID) external {
        _mint(_to, _tokenID);
    }

    function tokenURI(uint256 _id) public pure override returns(string memory) {
        return string(abi.encodePacked(baseURI, LibString.toString(_id)));
    }

}

