//SPDX-License-Identifier: MIT
/*
  _   _                               
 | \ | |                              
 |  \| | _   _ __  __ __ _  _ __ ___  
 | . ` || | | |\ \/ // _` || '_ ` _ \ 
 | |\  || |_| | >  <| (_| || | | | | |
 |_| \_| \__,_|/_/\_\\__,_||_| |_| |_|
                                                                                                                                                               
*/
                                                              
pragma solidity ^0.8.17;

import "./ERC721SeaDrop.sol";

contract Nuxam is ERC721SeaDrop{
    mapping(uint256 => string) private _actualBaseURIs;

    constructor(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop
    ) ERC721SeaDrop(name, symbol,allowedSeaDrop) {}

    function updateMetadata(uint256[] memory batchNumbers, string[] memory baseURIs) external onlyOwner {
        require(batchNumbers.length == baseURIs.length, "Array lengths do not match");

        for (uint256 i = 0; i < batchNumbers.length; i++) {
            uint256 batchNum = batchNumbers[i];
            string memory NuxambaseURI = baseURIs[i];
            _actualBaseURIs[batchNum] = NuxambaseURI;
        }
    }

    function _batchNumber(uint256 tokenId) internal pure virtual returns (uint256) {
        if (tokenId % 500 == 0) {
            return tokenId / 500;
        } else {
            return (tokenId / 500) + 1;
        }
    }

    function _batchExists(uint256 batchNum) internal view returns (bool) {
        return bytes(_actualBaseURIs[batchNum]).length > 0;
    }

    function _nuxamBaseURI(uint256 tokenId) internal view returns (string memory) {
        uint256 batchNumber = _batchNumber(tokenId);
        require(_batchExists(batchNumber), "BaseURI doesn't exist yet.");
        return _actualBaseURIs[batchNumber];
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        if (_batchExists(_batchNumber(tokenId))) {
            string memory nuxamBaseURI = _nuxamBaseURI(tokenId);
            return bytes(nuxamBaseURI).length != 0 ? string(abi.encodePacked(nuxamBaseURI, _toString(tokenId))) : '';
        } else {
            return _baseURI();
        }
    }

}


