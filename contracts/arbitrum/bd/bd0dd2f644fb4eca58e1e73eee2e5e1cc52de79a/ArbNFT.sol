//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./ERC721URIStorage.sol";
import "./Counters.sol";
import "./Ownable.sol";


contract ArbNFT is Ownable, ERC721URIStorage  {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    constructor(string memory name, string memory symbol) ERC721(name,symbol) public {
    }


    function mint(address to, string memory uri) internal {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _mint(to, newTokenId);
        _setTokenURI(newTokenId, uri);
    }

    function _batchMint(address[] memory tos, string[] memory uris) internal {
        require(tos.length == uris.length, "INVALID_INPUT_LENTHS");
        for ( uint i = 0; i < tos.length; i++) {
            mint(tos[i], uris[i]);
        }
    }


}
