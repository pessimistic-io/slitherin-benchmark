/*











                                                                     
   _|_|    _|_|_|      _|                                            
 _|    _|    _|        _|    _|_|    _|      _|    _|_|    _|  _|_|  
 _|_|_|_|    _|        _|  _|    _|  _|      _|  _|_|_|_|  _|_|      
 _|    _|    _|        _|  _|    _|    _|  _|    _|        _|        
 _|    _|  _|_|_|      _|    _|_|        _|        _|_|_|  _|        
                                                                     
                                                                     

                                                                                                                











*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "./Ownable.sol";
import "./Base64.sol";
import "./ERC721A.sol";


contract AIlover is ERC721A, Ownable {
    enum SaleStatus{ PAUSED, PRESALE, PUBLIC }

    uint public constant COLLECTION_SIZE = 10000;
    uint public constant FIRSTXFREE = 3;
    uint public constant TOKENS_PER_TRAN_LIMIT = 100;
    uint public constant TOKENS_PER_PERSON_PUB_LIMIT = 1000;
    
    
    uint public MINT_PRICE = 0.001 ether;
    SaleStatus public saleStatus = SaleStatus.PAUSED;
    
    string private _baseURL = "ipfs://bafybeial2kc7ccst5a2zapk4vhox7znfs6grlv3zxbrwxabopcq37vhnwq";
    
    mapping(address => uint) private _mintedCount;
    

    constructor() ERC721A("AI lover", "AI lover"){}
    
    
    
    
    
    
    /// @notice Set base metadata URL
    function setBaseURL(string calldata url) external onlyOwner {
        _baseURL = url;
    }

    /// @dev override base uri. It will be combined with token ID
    function _baseURI() internal view override returns (string memory) {
        return _baseURL;
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /// @notice Update current sale stage
    function setSaleStatus(SaleStatus status) external onlyOwner {
        saleStatus = status;
    }

    /// @notice Update public mint price
    function setPublicMintPrice(uint price) external onlyOwner {
        MINT_PRICE = price;
    }

    /// @notice Withdraw contract balance
    function withdraw() external onlyOwner {
        uint balance = address(this).balance;
        require(balance > 0, "No balance");
        payable(owner()).transfer(balance);
    }

    /// @notice Allows owner to mint tokens to a specified address
    function airdrop(address to, uint count) external onlyOwner {
        require(_totalMinted() + count <= COLLECTION_SIZE, "Request exceeds collection size");
        _safeMint(to, count);
    }

    /// @notice Get token URI. In case of delayed reveal we give user the json of the placeholer metadata.
    /// @param tokenId token ID
    function tokenURI(uint tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        string memory baseURI = _baseURI();

        return bytes(baseURI).length > 0 
            ? string(abi.encodePacked(baseURI, "/", _toString(tokenId), ".json")) 
            : "";
    }
    
    function calcTotal(uint count) public view returns(uint) {
        require(saleStatus != SaleStatus.PAUSED, "SpaceCatsClub: Sales are off");

        
        require(msg.sender != address(0));
        uint totalMintedCount = _mintedCount[msg.sender];

        if(FIRSTXFREE > totalMintedCount) {
            uint freeLeft = FIRSTXFREE - totalMintedCount;
            if(count > freeLeft) {
                // just pay the difference
                count -= freeLeft;
            }
            else {
                count = 0;
            }
        }

        
        uint price = MINT_PRICE;

        return count * price;
    }
    
    
    
    /// @notice Mints specified amount of tokens
    /// @param count How many tokens to mint
    function mint(uint count) external payable {
        require(saleStatus != SaleStatus.PAUSED, "SpaceCatsClub: Sales are off");
        require(_totalMinted() + count <= COLLECTION_SIZE, "SpaceCatsClub: Number of requested tokens will exceed collection size");
        require(count <= TOKENS_PER_TRAN_LIMIT, "SpaceCatsClub: Number of requested tokens exceeds allowance (100)");
        require(_mintedCount[msg.sender] + count <= TOKENS_PER_PERSON_PUB_LIMIT, "SpaceCatsClub: Number of requested tokens exceeds allowance (1000)");
        require(msg.value >= calcTotal(count), "SpaceCatsClub: Ether value sent is not sufficient");
        _mintedCount[msg.sender] += count;
        _safeMint(msg.sender, count);
    }
}

