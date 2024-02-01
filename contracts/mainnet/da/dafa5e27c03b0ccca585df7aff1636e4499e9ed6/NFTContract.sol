// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC721AUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract NFTContract is ERC721AUpgradeable, OwnableUpgradeable {
    string private _baseTokenURI;

    function initialize(string memory _name, string memory _symbol)
        public
        initializerERC721A
        initializer
    {
        __ERC721A_init(_name, _symbol);
        __Ownable_init();
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string calldata baseUri) external onlyOwner {
        _baseTokenURI = baseUri;
    }

    // Batch Airdrop NFTs
    function batchAirdrop(address[] calldata recipients, uint64[] calldata nums)
        external
        onlyOwner
    {
        uint256 length = recipients.length;
        require(length > 0, "No Accounts Provided");
        require(length == nums.length, "Invalid Arguments");

        for (uint256 i = 0; i < length; ) {
            _safeMint(recipients[i], nums[i]);
            unchecked {
                i++;
            }
        }
    }

    // Airdrop NFT
    function airdrop(address to, uint32 num) external onlyOwner {
        _safeMint(to, num);
    }
}

