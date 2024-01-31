// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

// name: TheShopNFT
// contract by: buildship.xyz

import "./ERC721Community.sol";

contract TSF is ERC721Community {
    constructor() ERC721Community("TheShopNFT", "TSF", 7777, 500, START_FROM_ONE, "ipfs://bafybeifubj6ggenfkzb2gla57qfbqz7vmfukcrsk4flburtseb3weoilcy/",
                                  MintConfig(0.07 ether, 3, 3, 0, 0x0962BC74A8506Cff71B3501F2F19150B1f164568, false, false, false)) {}
}

