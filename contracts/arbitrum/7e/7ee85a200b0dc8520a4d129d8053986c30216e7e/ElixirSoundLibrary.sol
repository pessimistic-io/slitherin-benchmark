// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./ERC721URIStorage.sol";
import "./Ownable.sol";
import "./Counters.sol";

/**
 * @title Elixir Sound Library
 * @notice Modified ERC721 contract that allows for token licensing
 */
contract ElixirSoundLibrary is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter public tokenCounter;

    struct SoundData {
        uint256 price;
        string tokenCID;
    }

    event SoundCreated (
        uint256 indexed tokenId,
        string tokenCID,
        uint256 price,
        address indexed tokenOwner
    );

    event SoundLicensed (
        uint256 indexed tokenId,
        uint256 price,
        address tokenOwner,
        address indexed licensee
    );

    event PriceUpdated (
        uint256 indexed tokenId,
        uint256 price,
        address indexed tokenOwner
    );

    string private baseURI;
    mapping(uint256 => uint256) private tokenIdToPrice;
    mapping(uint256 => mapping(address => bool)) public isLicensed;
        
    constructor() ERC721("Elixir", "ELIX") {}
    
    /**
     * @notice Mints sound 
     * @param _data SoundData containing price and tokenCID
     * @dev tokenCID should be an IPFS CID
     */
    function mintSound(SoundData memory _data) external {
        uint256 currentId = tokenCounter.current();
        tokenIdToPrice[currentId] = _data.price;
        
        _safeMint(msg.sender, currentId);
        _setTokenURI(currentId, _data.tokenCID);

        tokenCounter.increment();

        emit SoundCreated(currentId, _data.tokenCID, _data.price, msg.sender);
    }

    /**
     * @notice Licenses sound
     * Licensee's address is tracked -- No transfer of token ownership
     */
    function licenseSound(uint256 _tokenId) external payable {
        require(!isLicensed[_tokenId][msg.sender], "Sound is already licensed");

        address _tokenOwner = ownerOf(_tokenId);
        require(msg.sender != _tokenOwner, "Licensee cannot be the owner");

        uint256 _price = tokenIdToPrice[_tokenId];
        require(msg.value == _price, "Please submit the correct amount of ether");

        isLicensed[_tokenId][msg.sender] = true;

        // 4% fee
        uint256 _fee = _price / 25; 
        
        // Transfer ether to token owner
		(bool success, ) = _tokenOwner.call{value: _price - _fee}("");
		require(success, "Failed to send ether");

        emit SoundLicensed(_tokenId, _price, _tokenOwner, msg.sender);
    }

    /**
     * @notice Allows token owner to update price of sound
     */
    function updatePrice(uint256 _tokenId, uint256 _price) external {
        require(msg.sender == ownerOf(_tokenId), "Only the owner can update the price");
        tokenIdToPrice[_tokenId] = _price;

        emit PriceUpdated(_tokenId, _price, msg.sender);
    }

    /**
     * @notice Returns sound for a given token id
     */
    function sound(uint256 _tokenId) external view returns (uint256 tokenId, uint256 price, string memory uri, address tokenOwner) {
        return (_tokenId, tokenIdToPrice[_tokenId], tokenURI(_tokenId), ownerOf(_tokenId));
    }

    /**
     * @notice Owner withdrawal
     */
  	function withdraw() external onlyOwner {
		(bool success, ) = msg.sender.call{value: address(this).balance}("");
		require(success, "Failed to send ether");
	}

    /**
     * @notice Sets base URI to be appended to token CID
     */
    function setBaseURI(string memory _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }
}
