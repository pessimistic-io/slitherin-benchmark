// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./Strings.sol";
import "./IPrizeNFT.sol";
import {GenerateSVG} from "./GenerateSVG.sol";

contract PrizeNFT is ERC721, ERC721Enumerable, Ownable, IPrizeNFT {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    uint256 public roundId;

    uint256 public poolId;

    constructor(
        uint256 _roundId,
        uint256 _poolId
    )
        ERC721(
            string(
                abi.encodePacked("PrizeNFT-Round-", Strings.toString(_roundId))
            ),
            "PBox"
        )
    {
        roundId = _roundId;
        poolId = _poolId;
    }

    function safeMint(address to) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    function tokenURI(
        uint _tokenId
    ) public view override returns (string memory) {
        GenerateSVG.NFTItemInfo memory record = GenerateSVG.NFTItemInfo({
            poolId: poolId,
            roundId: roundId,
            index: _tokenId
        });

        string memory image = GenerateSVG.constructTokenURI(record);
        string memory _name = string(
            abi.encodePacked("PrizeBox ", Strings.toString(_tokenId))
        );
        string memory desc = string(
            abi.encodePacked(
                "PrizeBox ",
                Strings.toString(_tokenId),
                " is passport"
            )
        );

        return
            string(
                abi.encodePacked(
                    '{"name":"',
                    _name,
                    '","description":"',
                    desc,
                    '","image":"',
                    image,
                    '"}'
                )
            );
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function testV1() public pure returns (uint256) {
        return 1;
    }
}

