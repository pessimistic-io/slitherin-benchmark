//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./Counters.sol";


contract MevRobotsMint is ERC721Enumerable, Ownable {
    using Strings for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    mapping(uint256 => string ) _tokenURI;

    // Constants
    function maxSupply() internal pure returns (uint){
        return 104;  // Not sure
    }

    constructor() ERC721("Model Eros Village - Proto","MEV-Proto"){

    }

    function robotsMint(address[] calldata wAddresses) public onlyOwner {
        require(
            wAddresses.length < maxSupply() + 1,
            "Too many Addresses"
        );
        require(
            totalSupply() < maxSupply(),
            "Max Supply"
        );

        for (uint i = 0; i < wAddresses.length; ) {
            uint newTokenID = _tokenIds.current() + 1;
            _mint(wAddresses[i],newTokenID);
            _tokenIds.increment();
            unchecked {
                ++i;
            }
        }
    }

    function baseURI() internal pure returns (string memory) {
        return "ipfs://bafybeiaxzo3smg3ooa6a7qzhj62z42necvpnpdjurbz3ffkb4roth3fvtm/MevRobots";
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory){
      require(_exists(tokenId), "");
      if (bytes(_tokenURI[tokenId]).length > 0) {
          return _tokenURI[tokenId];
      }
      return string(abi.encodePacked(baseURI(), tokenId.toString(), ".json"));
    }

    function setTokenURI(string memory uri, uint tokenId ) public onlyOwner {
        if (tokenId == 0){
            for(uint i = 1; i<=totalSupply(); ){
                string memory linktext = string(abi.encodePacked(uri, i.toString(), ".json"));
                _tokenURI[i] = linktext;
                unchecked {
                    ++i;
                }
            }
        }else{
            _tokenURI[tokenId] = uri;
        }
    }

}
