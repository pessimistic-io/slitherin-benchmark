// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./Strings.sol";
import "./mock_ERC721A.sol";
import {RevealModule} from "./RevealModule.sol";
import {AllowList} from "./AllowList.sol";
import {ENS} from "./ENS.sol";

contract Gangz721 is ERC721A, RevealModule, AllowList, ENS {
    constructor(bytes32 _merkleRoot, string memory _ensName)
        ERC721A("Gangz", "Gangz")
        AllowList(_merkleRoot)
        ENS(_ensName)
    {
    }

    function mint(uint256 quantity) external payable {
        // `_mint`'s second argument now takes in a `quantity`, not a `tokenId`.
        _mint(msg.sender, quantity);
        for (uint256 i = 0; i < quantity; ++i) {
            _grantSubdomain(Strings.toString(_nextTokenId() - 1), msg.sender);
        }
    }

    function mintWithoutDomain(uint256 quantity) external payable {
        // `_mint`'s second argument now takes in a `quantity`, not a `tokenId`.
        _mint(msg.sender, quantity);
    }
}

