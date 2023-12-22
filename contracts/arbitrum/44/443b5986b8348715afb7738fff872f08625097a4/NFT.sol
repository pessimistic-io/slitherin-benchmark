// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC721.sol";
import "./Strings.sol";

/// @title A Web3 event using ERC721
/// @author Kevin Tan
/// @notice You can use this contract for mint and transfer NFT.
/// @dev All function calls are currently implemented without side effects
contract NFT is ERC721, Ownable, Pausable {
    using Strings for uint256;

    bool public baseURILocked;
    uint256 public mintStartTime;
    uint256 public mintEndTime;
    uint256 public maxMintAmount;

    string public baseURI;
    string public provenanceHash;

    event TokenMinted(uint256 indexed tokenId, address owner);
    event BaseURIUpdated(string indexed oldValue, string indexed newValue);

    constructor(
        string memory name,
        string memory symbol,
        string memory _provenanceHash,
        string memory _baseUri,
        uint256 _mintStartTime,
        uint256 _mintEndTime,
        uint256 _maxMintAmount
    ) ERC721(name, symbol) {
        require(_mintStartTime < _mintEndTime, 'Invalid Time.');
        require(block.timestamp + 24 * 3600 < _mintEndTime, 'Invalid mintEndTime');
        provenanceHash = _provenanceHash;
        baseURI = _baseUri;
        mintStartTime = _mintStartTime;
        mintEndTime = _mintEndTime;
        maxMintAmount = _maxMintAmount;
    }

    /// @notice Owner can only mint their the NFT and transfer NFT to receiver.
    /// @param tokenId the tokenId
    /// @param receiver The address of the user receiving the nft.
    /// @return the new token id
    function mintNFT(uint256 tokenId, address receiver) external onlyOwner whenNotPaused returns (uint256) {
        require(block.timestamp > mintStartTime, 'Minting is not yet allowed.');
        require(block.timestamp < mintEndTime, 'Minting period has ended.');
        require(tokenId < maxMintAmount, 'TokenID exceeds the max mint amount.');
        require(balanceOf(receiver) == 0, 'Receiver must have only one NFT');

        _safeMint(receiver, tokenId);

        emit TokenMinted(tokenId, receiver);
        return tokenId;
    }

    /// @notice Users can burn their nft using this function.
    /// @param tokenId nft id
    function burn(uint256 tokenId) external whenNotPaused {
        require(ownerOf(tokenId) == msg.sender || owner() == msg.sender, 'Onwer should be owner');
        _burn(tokenId);
    }

    /// @notice Owner can update the mint end time using this function.
    /// @param mintEndTime_ mint end time 
    function updateMintEndTime(uint256 mintEndTime_) external onlyOwner whenNotPaused {
        require(mintEndTime_ > mintStartTime && mintEndTime_ > block.timestamp, 'Invalid mintEndTime');
        mintEndTime = mintEndTime_;
    }

    /// @notice Owner can update the max mint count using this function.
    /// @param maxMintAmount_ max value
    function updateMaxMintAmount(uint256 maxMintAmount_) external onlyOwner whenNotPaused {
        require(0 < maxMintAmount_, 'Invalid maxMintAmount');
        require(block.timestamp < mintEndTime, 'The event was finished');
        maxMintAmount = maxMintAmount_;
    }



    /// @notice factory can destroy this event.
    function destroy() external view onlyOwner whenNotPaused {
        require(block.timestamp < mintStartTime, 'destroy must be before starting');
        paused();
    }

    /**
     * @notice Users can get their tokenURI with tokenId.
     * @param tokenId nft id
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(ownerOf(tokenId) != address(0), 'ERC721Metadata: URI query for nonexistent token');
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : '';
    }

    /**
     * @notice Factory can lock the baseURI.
     */
    function lockURI() external onlyOwner whenNotPaused {
        require(bytes(baseURI).length > 0, 'Invalid baseURI');
        baseURILocked = true;
    }

    /**
     * @notice Function to set the newBaseURI
     * @param _newBaseURI new base URI
     */
    function setBaseURI(string memory _newBaseURI) external onlyOwner whenNotPaused {
        require(baseURILocked == false, 'Already locked baseURI');
        emit BaseURIUpdated(baseURI, _newBaseURI);
        baseURI = _newBaseURI;
    }

    /// @notice Function to set the NFT provenance
    /// @param _provenance nft provenance
    function setProvenance(string memory _provenance) external onlyOwner whenNotPaused {
        provenanceHash = _provenance;
    }
}

