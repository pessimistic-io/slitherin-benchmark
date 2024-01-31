//
//  ██    ██ ██       █████  ███    ██ ██████       ██  ██████
//  ██    ██ ██      ██   ██ ████   ██ ██   ██      ██ ██    ██
//  ██    ██ ██      ███████ ██ ██  ██ ██   ██      ██ ██    ██
//  ██    ██ ██      ██   ██ ██  ██ ██ ██   ██      ██ ██    ██
//   ██████  ███████ ██   ██ ██   ████ ██████   ██  ██  ██████
//
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

// @title ULAND Hero NFT contract V1 / uland.io
// @author 57pixels@uland.io
// @whitepaper https://uland.io/Whitepaper.pdf

import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeMath.sol";
import "./Strings.sol";


contract ULANDHeroes is
    Initializable,
    ERC721Upgradeable,
    ERC721BurnableUpgradeable,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using SafeMath for uint256;
    using Strings for uint256;

    uint256 private nextTokenId;
    string private _tokenBaseURI;
    mapping(uint256 => string) private _tokenURIs; // Burn URI into token
    mapping(address => bool) public ulandContracts; // ULAND eco-system access
           
    uint256[48] __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC721_init("ULAND Heroes NFT", "UHERO");
        __ERC721Enumerable_init();
        __ERC721Burnable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        nextTokenId = 1;
        _tokenBaseURI = "https://api.uland.io/hero/metadata/";
        ulandContracts[msg.sender] = true;
    }

    modifier onlyUland() {
        require(ulandContracts[msg.sender]);
        _;
    }

    
    /*
	 * @notice Mint methods
	 */
    function mint(
        address _to 
    ) public onlyUland {        
        _safeMint(_to, nextTokenId);
        nextTokenId++;
    }

    function mintId(
        uint256 _tokenId,
        address _to 
    ) public onlyUland {        
        _safeMint(_to, _tokenId);
    }

    /*
	 * @notice Get URI for token metadata
	 */
	function tokenURI(uint256 tokenId)
		public
		view
		override
		returns (string memory)
	{
		require(_exists(tokenId), "NOT_FOUND");

         if (abi.encodePacked(_tokenURIs[tokenId]).length > 0){
            return string(abi.encodePacked(_tokenURIs[tokenId]));
         }
		return string(abi.encodePacked(_tokenBaseURI, tokenId.toString()));
	}  

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function safeMint(address to, uint256 tokenId) public onlyOwner {
        _safeMint(to, tokenId);
    }

    function setUlandContractAllow(address contractAddress, bool access)
        public
        onlyOwner
    {
        ulandContracts[contractAddress] = access;
    }
    function setNextTokenId(uint256 _nextTokenId)
        public
        onlyOwner
    {
        nextTokenId = _nextTokenId;
    }
    
    function setBaseURI(string calldata URI) external onlyOwner {
		_tokenBaseURI = URI;
	}

    function setTokenURI(uint256 tokenId, string calldata URI) external onlyUland {
		_tokenURIs[tokenId] = URI;
	}

    /**
     * @dev Withdraw funds to treasury
     */
    function treasuryWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
    
}

