// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ERC721A.sol";
import "./Strings.sol";

/**
 * @title MythoFrogs
 * @notice Minting contract forked from Azuki :D
 */

contract Mytho is Ownable, ERC721A, ReentrancyGuard {
    uint256 public price = 0.05 ether;
    bool public pausedAllowlist;
    bool public pausedPublic;

    mapping(address => uint256) public allowlist;

    constructor(uint256 maxBatchSize_, uint256 collectionSize_)
        ERC721A("Mytho Frogs", "MYTHO", maxBatchSize_, collectionSize_)
    {
        pausedAllowlist = true;
        pausedPublic = true;
    }

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    function allowlistMint(uint256 _amount) external payable callerIsUser {
        uint256 mintsLeft = allowlist[msg.sender];

        require(!pausedAllowlist, "Not live");
        require(mintsLeft >= _amount, "no spots left");
        require(price != 0, "allowlist sale has not begun yet");
        require(allowlist[msg.sender] > 0, "not eligible for allowlist mint");
        require(totalSupply() + _amount <= collectionSize, "reached max supply");

        allowlist[msg.sender] = allowlist[msg.sender] - _amount;
        _safeMint(msg.sender, _amount);

        refundIfOver(price * _amount);
    }

    function publicSaleMint(uint256 quantity) external payable callerIsUser {
        require(!pausedPublic, "Not live");
        require(totalSupply() + quantity <= collectionSize, "reached max supply");

        _safeMint(msg.sender, quantity);
        refundIfOver(price * quantity);
    }

    function refundIfOver(uint256 _price) private {
        require(msg.value >= _price, "Need to send more ETH.");
        if (msg.value > _price) {
            payable(msg.sender).transfer(msg.value - _price);
        }
    }

    function isPublicSaleOn() public view returns (bool) {
        return pausedPublic;
    }

    function seedAllowlist(address[] memory addresses, uint256[] memory numSlots) external onlyOwner {
        require(addresses.length == numSlots.length, "addresses does not match numSlots length");
        for (uint256 i = 0; i < addresses.length; i++) {
            allowlist[addresses[i]] = numSlots[i];
        }
    }

    // For marketing etc.
    function devMint(uint256 quantity) external onlyOwner {
        require(totalSupply() + quantity <= collectionSize, "reached max supply");
        require(quantity % maxBatchSize == 0, "can only mint a multiple of the maxBatchSize");

        uint256 numChunks = quantity / maxBatchSize;

        for (uint256 i = 0; i < numChunks; i++) {
            _safeMint(msg.sender, maxBatchSize);
        }
    }

    function togglePauseAllowlist(bool _status) external onlyOwner {
        pausedAllowlist = _status;
    }

    function togglePausePublic(bool _status) external onlyOwner {
        pausedPublic = _status;
    }

    // metadata URI
    string private _baseTokenURI;

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
}

