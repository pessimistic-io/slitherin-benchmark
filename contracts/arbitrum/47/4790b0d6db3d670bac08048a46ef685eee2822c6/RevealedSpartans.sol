//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import "./ERC721EnumerableMetadataMintable.sol";
import "./ERC2981.sol";
import "./Ownable.sol";

contract RevealedSpartans is
    ERC721EnumerableMetadataMintable,
    ERC2981,
    Ownable
{
    constructor(
        address _treasuryWallet,
        uint96 _royaltyNumerator,
        string memory name_,
        string memory symbol_,
        address minter_,
        string memory baseTokenURI_,
        string memory contractURI_,
        address _owner
    )
        ERC721EnumerableMetadataMintable(
            name_,
            symbol_,
            minter_,
            baseTokenURI_,
            contractURI_
        )
    {
        _setDefaultRoyalty(_treasuryWallet, _royaltyNumerator);
        _transferOwnership(_owner);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC2981, ERC721Enumerable) returns (bool) {
        return
            ERC2981.supportsInterface(interfaceId) ||
            ERC721Enumerable.supportsInterface(interfaceId);
    }
}

