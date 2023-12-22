// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;


/**
 * @dev Modifier 'onlyOwner' becomes available, where owner is the contract deployer
 */
import "./Ownable.sol";

/**
 * @dev ERC721 token standard
 */
import "./ERC721Enumerable.sol";



contract PFP is Ownable, ERC721Enumerable { 

    string public preRevealURI;

    bool public revealed;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {}


    // --- MAPPING --- //

    mapping(uint => string) tokenURIs;
    
    
    // --- EVENTS --- //
    
    event TokenMinted(uint256 tokenId, address indexed recipient);
    
  
    // --- VIEW --- //
    
    /**
     * @dev Returns tokenURI
     */
    function tokenURI(uint256 _tokenId) public view override returns(string memory) {

        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");
        
        if (revealed) {
            return tokenURIs[_tokenId];
        }
        
        return preRevealURI;
    }


    // --- ONLY OWNER --- //
    

    /**
     * @dev Set pre reveal URI
     */
    function setPreRevealURI(string memory _URI) external onlyOwner {
        preRevealURI = _URI;
    }

    /**
     * @dev Set reveal status
     */
    function setRevealStatus(bool _status) external onlyOwner {
        revealed = _status;
    }

    /**
     * @dev Batch set token URIs
     */
    function batchSetURI(uint[] memory _tokenIds, string[] memory _URIs) external onlyOwner {

        require(
            _tokenIds.length == _URIs.length,
            "Argument array lengths differs"
        );

        for (uint i=0; i<_tokenIds.length; i++) {
            tokenURIs[_tokenIds[i]] = _URIs[i];
        }
    }

    /**
     * @dev Airdrop 1 token to each address in array '_to'
     * @param _to - array of address' that tokens will be sent to
     */
    function airDrop(address[] calldata _to) external onlyOwner {

        for (uint i=0; i<_to.length; i++) {
            uint tokenId = totalSupply() + 1;
            _mint(_to[i], tokenId);
            emit TokenMinted(tokenId, _to[i]);
        }
    }

    
}
