//SPDX-License-Identifier: MIT
import "./IERC721MintableBurnable.sol";
import "./ERC721Bridge.sol";

pragma solidity 0.8.17;

contract ERC721MintingBridge is ERC721Bridge {

    // Avoid stack too deep error
    struct ConstructorParams{
        address lzEndpoint;
        IERC721[5] nfts;
        address owner;
        uint maxEpochLimit;
        uint epochDuration;
        uint epochLimit;
    }

    constructor(
        ConstructorParams memory constructorParams
    ) ERC721Bridge(
        constructorParams.lzEndpoint,
        constructorParams.nfts,
        constructorParams.owner,
        constructorParams.maxEpochLimit,
        constructorParams.epochDuration,
        constructorParams.epochLimit
    ) {}

    // @dev Here we implement burning (default behavior is transfer to bridge)
    function _lockNft(address from, NftTier nftTier, uint tokenId) internal override {
        IERC721 nft = nfts[uint(nftTier)];
        require(nft.ownerOf(tokenId) == from, "!owner");
        IERC721MintableBurnable(address(nft)).burn(tokenId);
    }

    // @dev Here we implement minting (default behavior is transfer to user)
    function _unlockNft(address to, NftTier nftTier, uint tokenId) internal override {
        IERC721MintableBurnable(address(nfts[uint(nftTier)])).mint(to, tokenId);
    }
}

