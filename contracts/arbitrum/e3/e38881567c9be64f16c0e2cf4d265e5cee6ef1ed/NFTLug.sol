//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./Counters.sol";

contract NFTLuggage is ERC721Enumerable, Pausable, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;
    string public baseExtension = ".json";
    Counters.Counter private _tokenIdCounter;
    struct infoLuggage{
        uint8 qualityVa;
        uint8 typeVa;
    }

    mapping(uint256 => infoLuggage) public infoLuggageList;
    mapping(address => bool) public whitelistAddress;
    constructor() ERC721("NFT Luggage", "Lug") {}

    modifier isWhitelistAddress()
    {
        require(whitelistAddress[msg.sender], "You are not an operator");
        _;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://metadata.lux.world/luggage/";
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), baseExtension)) : "";
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function safeMint(address to) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    function batchMint(address toAddress, uint8 number, uint8 _quality, uint8 _type) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        for (uint i = 0; i < number; i++) {
            _tokenIdCounter.increment();
            tokenId = _tokenIdCounter.current();
            _safeMint(toAddress, tokenId);
            infoLuggageList[tokenId] = infoLuggage(_quality,_type);
        }
    }

    function addwhitelistAddress(address[] calldata _address, bool state) external onlyOwner
    {
        for(uint i=0; i < _address.length; i++)
        {
            whitelistAddress[_address[i]] = state;
        }
    }

    function transferWithAmountNft(address _receiverAdd, uint256[] memory _tokenID) external isWhitelistAddress
    {
        for(uint i=0; i < _tokenID.length; i++)
        {
            _transfer(msg.sender, _receiverAdd, _tokenID[i]);
        }
    }

    function viewInfoLuggage(uint256 _tokenId) external view returns(uint8, uint8)
    {
        return (infoLuggageList[_tokenId].qualityVa, infoLuggageList[_tokenId].typeVa);
    }
}
