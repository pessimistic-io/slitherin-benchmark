// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ERC721A.sol";
import "./Strings.sol";

/**
 * @title MythoItems
 * @notice Minting contract forked from Azuki :D
 */

contract MythoItems is Ownable, ERC721A, ReentrancyGuard {
    bool public pausedPublic;

    mapping(address => bool) public authorized;

    function authorization(address target, bool _authorized) external onlyOwner {
        authorized[target] = _authorized;
    }

    constructor(uint256 maxBatchSize_, uint256 collectionSize_)
        ERC721A("Mytho Items", "MYTHO ITEMS", maxBatchSize_, collectionSize_)
    {
        pausedPublic = true;
    }

    function burnMint(address user, uint256 amount) external {
        if (!authorized[msg.sender]) revert Unauthorized();

        _safeMint(user, amount);
    }

    // metadata URI
    string private _baseTokenURI;

    function pause_status(bool paused) public onlyOwner {
        pausedPublic = paused;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function withdrawMoney() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function setOwnersExplicit(uint256 quantity) external onlyOwner nonReentrant {
        _setOwnersExplicit(quantity);
    }

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    function getOwnershipData(uint256 tokenId) external view returns (TokenOwnership memory) {
        return ownershipOf(tokenId);
    }

    error Unauthorized();
}

