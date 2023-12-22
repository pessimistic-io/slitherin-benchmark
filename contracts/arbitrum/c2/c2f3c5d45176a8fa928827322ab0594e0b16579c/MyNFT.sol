// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ERC721} from "./ERC721.sol";
import {Ownable} from "./Ownable.sol";

error NotWhitelisted(address minter);
error CallerHasMinted(address minter);
error MintLimitReached(uint256 mintLimit);
error NotOnWhitelist(address addressToRemove);
error WhitelistLimitReached(uint256 whitelistLimit);
error AlreadyWhitelisted(address whitelistedAddress);

/// Optimism only
contract MyNFT is
    ERC721,
    Ownable
{
    uint256 public cap;
    uint256 private mintCounter;
    uint256 public whitelistCounter;
    string public tknURI;

    mapping(address => bool) whitelist;
    mapping(address => bool) hasMinted;

    constructor(string memory _name,string memory _symbol,uint8 _cap, string memory _tokenURI) ERC721(_name, _symbol) {
        cap=_cap;
        tknURI=_tokenURI;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory)
    {
        return tknURI;
    }

    function isWhitelisted(address _a) public view virtual returns (bool) {
        bool isWhitelisted_ = whitelist[_a];

        if (isWhitelisted_) {
            return isWhitelisted_;
        } else {
            return false;
        }
    }

    function addToWhitelist(
        address[] memory _toWhitelist
    ) external onlyOwner returns (bool) {
        if (whitelistCounter >= cap)
            revert WhitelistLimitReached(whitelistCounter);

        uint256 addresses = _toWhitelist.length;

        for (uint256 i = 0; i < addresses; i++) {
            address a_ = _toWhitelist[i]; // Get address to whitelist

            // Revert if the address has been whitelisted
            if (isWhitelisted(a_)) revert AlreadyWhitelisted(a_);

            whitelistCounter += 1; // Increment counter for whitelist
            whitelist[a_] = true; // Add to whitelist
        }

        return true; // Confirmation that function added addresses to whitelist
    }

    function removeFromWhitelist(
        address[] memory _toWhitelist
    ) external onlyOwner returns (bool) {

        uint256 addresses = _toWhitelist.length;

        for (uint256 i = 0; i < addresses; i++) {
            // Get address to remove from whitelist
            address a_ = _toWhitelist[i];

            if (whitelist[a_] == true) {
                whitelistCounter -= 1; // Decrement counter for whitelist
                whitelist[a_] = false;
            }
        }

        return true;
    }

    function mint() external {
        address _to = msg.sender;

        if (!isWhitelisted(_to)) revert NotWhitelisted(_to);
        if (msg.sender!=owner() && hasMinted[_to]) revert CallerHasMinted(_to);
        if (mintCounter >= cap) revert MintLimitReached(mintCounter);

        mintCounter += 1;

        _safeMint(_to, mintCounter);
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}

