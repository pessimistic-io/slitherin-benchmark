// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./ERC2981.sol";
import "./Ownable.sol";
import "./Counters.sol";

contract SmulipFounders is ERC721, ERC2981, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;
    
    Counters.Counter private _tokenIdCounter;

    uint256 public maxSupply = 20;
    bool public metadataLocked = false;
    
    string public baseURI = "ipfs://QmfAR5YKCCK2D4aU7rHecNFMVwqNUKkr3YdihgWvjqgjjs/";

    address public royaltyWallet = 0xD929F6bE1F17996D8aD37Df7269032247014cC62;
    address public mintWallet = 0xF496B0759C4CC9487971FE82D22f5480958d997E;

    event updatedURI (string oldURI, string newURI);
    event lockedURI (string finalURI);

    constructor() ERC721("Founders of the Garden", "FSMULIP") {
        _setDefaultRoyalty(royaltyWallet, 750);
        batchMint(mintWallet, maxSupply);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Invalid token ID");
        string memory URI = _baseURI();
        return bytes(URI).length > 0 ? string(abi.encodePacked(URI, tokenId.toString(), ".json")) : "";
    }

    function setURI(string memory newURI) public onlyOwner {
        require(metadataLocked == false, "URI is locked");
        string memory oldURI = baseURI;
        baseURI = newURI;
        emit updatedURI(oldURI, newURI);
    }

    function lockURI() public onlyOwner {
        require(metadataLocked == false, "Already locked");
        metadataLocked = true;
        emit lockedURI(baseURI);
    }

    function batchMint(address to, uint256 amount) internal onlyOwner {
        require(_tokenIdCounter.current() + amount <= maxSupply, "Amount > maxSupply");
        for (uint i=1; i <= amount; i++) {
            _tokenIdCounter.increment();
            _safeMint(to, _tokenIdCounter.current());
        }
    }

    function setDefaultRoyalty(address royaltyReciever, uint96 royaltyFeeNumerator) external onlyOwner {
        _setDefaultRoyalty(royaltyReciever, royaltyFeeNumerator);
    }

    function removeRoyaltyInfo() public onlyOwner {
        _deleteDefaultRoyalty();
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
