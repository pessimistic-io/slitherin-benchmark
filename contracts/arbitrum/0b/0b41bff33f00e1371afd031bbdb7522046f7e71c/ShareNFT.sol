// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract ShareNFT is ERC721EnumerableUpgradeable, OwnableUpgradeable {
    mapping(address => bool) public _minters;
    event NFTMinted(address _owner, uint256 _id);
    event NFTBurned(uint256 _id);

    function initialize() public initializer {
        __Ownable_init();
        __ERC721_init("MEOW-SHARE-NFT", "MEOW-SHARE");
    }

    /**
     * @dev Function to mint tokens.
     * @param to The address that will receive the minted token.
     * @param tokenId The token id to mint.
     */
    function mint(address to, uint256 tokenId) external {
        require(_minters[msg.sender], "!minter");
        _mint(to, tokenId);
        emit NFTMinted(to,tokenId);
    }

    /**
     * @dev Burns a specific ERC721 token.
     * @param tokenId uint256 id of the ERC721 token to be burned.
     */
    function burn(uint256 tokenId) external {
        require(_minters[msg.sender], "!minter");
        _burn(tokenId);
        emit NFTBurned(tokenId);
    }

    function addMinter(address minter) public onlyOwner {
        _minters[minter] = true;
    }

    function removeMinter(address minter) public onlyOwner {
        _minters[minter] = false;
    }
}

