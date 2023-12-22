// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ERC721} from "./ERC721.sol";

contract ERC721TestToken is ERC721("NFT", "NFT") {
    mapping(uint256 => string) private uri;
    uint256 public tokenID;

    function mint(address _to, string calldata _uri) public {
        uri[tokenID] = _uri;
        _mint(_to, tokenID++);
    }

    function batchMint(address _to, string calldata _uri, uint256 _amt) public {
        uint _tokenID = tokenID;
        uint _finalTokenID= _tokenID + _amt;
        for (uint256 _index = _tokenID; _index < _finalTokenID; _index++) {
            uri[_index] = _uri;
            _mint(_to, _index);
        }
        tokenID = _finalTokenID;
    }


    function tokenURI(uint256 id) public view override returns (string memory) {
        return uri[id];
    }
}

