// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC721Upgradeable.sol";
import "./ERC721URIStorageUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./CountersUpgradeable.sol";

contract ChristmasFloc2022 is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private supplyCounter;

    string private tokenURL;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string calldata tokenURL_) public initializer {
        __ERC721_init("ChristmasFloc2022", "CFLOC2022");
        __Ownable_init();

        tokenURL = tokenURL_;
    }

    /** MINTING **/
    function mint() public {
        //Require token to be in the user whitelist
        _mint(msg.sender, totalSupply() + 1);
        _setTokenURI(totalSupply() + 1, tokenURL);
        supplyCounter.increment();
    }

    function totalSupply() public view returns (uint256) {
        return supplyCounter.current();
    }

    function setTokenURL(string memory tokenURL_) external onlyOwner {
        tokenURL = tokenURL_;
    }

    function _tokenURL() internal view returns (string memory) {
        return tokenURL;
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId)
        internal
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
    {
        supplyCounter.decrement();
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
}

