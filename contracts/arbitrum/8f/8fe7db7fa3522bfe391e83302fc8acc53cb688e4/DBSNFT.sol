// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC2981.sol";
import "./Counters.sol";
import "./Strings.sol";

contract DBSNFT is ERC2981, ERC721Enumerable {    
    
    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter private nftCount;
    string public baseUri;        // Base URI  
    string public collectionUri;  // Collection URI  

    mapping(uint256 => uint256) private mintId;  // (monthId => value)

    receive() external payable {}
    constructor(
        string memory _baseUri,
        string memory _collectionUri,
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {
        baseUri = _baseUri;
        collectionUri = _collectionUri;
    }

    function contractURI() public view returns (string memory) {
        return collectionUri;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override(ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }  

    function mintTo(address _to, uint256 _monthId) public payable returns (uint256) {
        uint256 newTokenId = __getNextTokenId(_monthId);
        _safeMint(_to, newTokenId);

        return newTokenId;
    }

    /// @dev Generate tokenId
    function __getNextTokenId(uint _monthId) private returns (uint256 newTokenId_) {        
        nftCount.increment();

        mintId[_monthId] += 1;
        newTokenId_ = _monthId * 1000 + mintId[_monthId];
    }

    /// @dev set royalty for all token ids
    function setDefaultRoyalty(address _receiver, uint256 _royaltyValue) public {
        _setDefaultRoyalty(_receiver, uint96(_royaltyValue));
    }

    function getRoyaltyInfo(uint256 _tokenId, uint256 _salePrice) public view returns (address, uint256) {
        return royaltyInfo(_tokenId, _salePrice);
    }

    /// @notice Set tokenURI in all available cases
    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");

        return string(abi.encodePacked(baseUri, _tokenId.toString(), ".json"));
    }

    function transferNFT(uint256 _tokenId, address _to) external {        
        address seller = ownerOf(_tokenId);
        transferFrom(seller, _to, _tokenId);
    }

    function userTokenIdList(address _owner) external view returns (uint256[] memory _tokensOfOwner) {
        _tokensOfOwner = new uint256[](balanceOf(_owner));
        for (uint256 i; i < balanceOf(_owner); i++) {
            _tokensOfOwner[i] = tokenOfOwnerByIndex(_owner, i);
        }
    }
    
    /// @notice Return total minited NFT count
    function totalSupply() public view override returns (uint256) {
        return nftCount.current();
    }
}
