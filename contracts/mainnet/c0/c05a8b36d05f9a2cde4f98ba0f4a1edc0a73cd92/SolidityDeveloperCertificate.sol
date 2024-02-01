// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC721.sol";
import "./Ownable.sol";

contract SolidityDeveloperCertificate is ERC721 {
    constructor() ERC721("Solidity Developer Certificate", "SDC") {
        _safeMint(_msgSender(), 0);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://bafkreicyn3oc2jpjeklv7pavdgdvuhryilq6267ram6uyxrp3jihjrusny.ipfs.nftstorage.link/";
    }
}

