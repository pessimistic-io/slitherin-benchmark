//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "./ERC721.sol";

contract NFTEnumerable {
    constructor() {}

    struct NFT {
        uint256 tokenID;
        string url;
    }

    function tokensOfOwner(address _owner, address _nft, uint256 _total_supply) public view returns (uint256[] memory) {
        uint256 balance = ERC721(_nft).balanceOf(_owner);
        uint256[] memory tokens = new uint256[](balance);
        unchecked {
            uint256 index;
            for (uint256 i = 1; i <= _total_supply; i++) {
                try ERC721(_nft).ownerOf(i) {
                    if (ERC721(_nft).ownerOf(i) == _owner) {
                        tokens[index] = uint256(i);
                        index++;
                    }
                }
                catch {}
            }
        }
        return tokens;
    }

    function tokensDetailOfOwner(address _owner, address _nft, uint256 _total_supply) public view returns (NFT[] memory) {
        uint256 balance = ERC721(_nft).balanceOf(_owner);
        NFT[] memory nfts = new NFT[](balance);
        unchecked {
            uint256 index;
            for (uint256 i = 1; i <= _total_supply; i++) {
                try ERC721(_nft).ownerOf(i) {
                    if (ERC721(_nft).ownerOf(i) == _owner) {
                        NFT memory nft;
                        nft.tokenID =  uint256(i);
                        nft.url = ERC721(_nft).tokenURI(i);
                        nfts[index] = nft;
                        index++;
                    }
                }
                catch {}
            }
        }
        return nfts;
    }
}
