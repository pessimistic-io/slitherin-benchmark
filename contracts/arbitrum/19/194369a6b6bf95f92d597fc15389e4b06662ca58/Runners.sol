// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC721A.sol";

contract Runners is ERC721A {
    // Sudo NFT variables
    bool minted;
    string constant ipfs = "ipfs://QmUeA3dbnDrZ8hVLYVF3BEwWR2tyibxJr1dQgV5Acd1eCe/";

    constructor() ERC721A("Blade City Runners", "BRUU") {}

    function _baseURI() internal pure override returns (string memory) {
        return ipfs;
    }

    function mint() external payable {
        require(!minted, "Mint already completed");

        _mint(msg.sender, 10000);
        minted = true;
    }
}

