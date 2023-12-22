// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";
import "./ERC721Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./Strings.sol";

contract NFT is ERC721, ERC721Enumerable, ERC721URIStorage, ERC721Burnable, Pausable, Ownable {
    // Events
    event burnToken(address indexed operator, address indexed owner, uint256 indexed tokenId);

    string baseURI;
    uint256 public firstGenerationAmount = 0;

    constructor() ERC721("NFT", "NFT") {}

    function getFirstGenerationAmount() public view returns (uint256) {
        return firstGenerationAmount;
    }

    function getIsFirstGenerationAmount(uint256 tokenId) public view returns (bool) {
        return tokenId < firstGenerationAmount;
    }

    function setFirstGenAmount(uint256 _allowedAmount) external onlyOwner {
        firstGenerationAmount = _allowedAmount;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to)
        public
        onlyOwner
        whenNotPaused
    {
        uint256 supply = totalSupply();

        uint256 tokenId = supply;
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, Strings.toString(tokenId));
    }

    function isApprovedForAll(
        address _owner,
        address _operator
    ) public override(IERC721, ERC721) view returns (bool isOperator) {
      // if OpenSea's ERC721 Proxy Address is detected, auto-return true
        if (_operator == address(0x58807baD0B376efc12F5AD86aAc70E78ed67deaE)) {
            return true;
        }
        
        // otherwise, use the default ERC721.isApprovedForAll()
        return ERC721.isApprovedForAll(_owner, _operator);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function burn(uint256 tokenId) public override {
        address owner = ownerOf(tokenId);
        emit burnToken(_msgSender(), owner, tokenId);
        super.burn(tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

