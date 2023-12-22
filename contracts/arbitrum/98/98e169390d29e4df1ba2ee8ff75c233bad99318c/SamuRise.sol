// SPDX-License-Identifier: MIT
// Creator: base64.tech
pragma solidity ^0.8.13;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./ECDSAUpgradeable.sol";

/*
 ▄█        ▄██████▄     ▄████████     ███     
███       ███    ███   ███    ███ ▀█████████▄ 
███       ███    ███   ███    █▀     ▀███▀▀██ 
███       ███    ███   ███            ███   ▀ 
███       ███    ███ ▀███████████     ███     
███       ███    ███          ███     ███     
███▌    ▄ ███    ███    ▄█    ███     ███     
█████▄▄██  ▀██████▀   ▄████████▀     ▄████▀   
▀                                             

   ▄████████    ▄████████   ▄▄▄▄███▄▄▄▄   ███    █▄     ▄████████  ▄█     ▄████████    ▄████████ 
  ███    ███   ███    ███ ▄██▀▀▀███▀▀▀██▄ ███    ███   ███    ███ ███    ███    ███   ███    ███ 
  ███    █▀    ███    ███ ███   ███   ███ ███    ███   ███    ███ ███▌   ███    █▀    ███    █▀  
  ███          ███    ███ ███   ███   ███ ███    ███  ▄███▄▄▄▄██▀ ███▌   ███         ▄███▄▄▄     
▀███████████ ▀███████████ ███   ███   ███ ███    ███ ▀▀███▀▀▀▀▀   ███▌ ▀███████████ ▀▀███▀▀▀     
         ███   ███    ███ ███   ███   ███ ███    ███ ▀███████████ ███           ███   ███    █▄  
   ▄█    ███   ███    ███ ███   ███   ███ ███    ███   ███    ███ ███     ▄█    ███   ███    ███ 
 ▄████████▀    ███    █▀   ▀█   ███   █▀  ████████▀    ███    ███ █▀    ▄████████▀    ██████████ 
                                                       ███    ███                                
samurise.xyz
*/
contract SamuRise is ERC721EnumerableUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using ECDSAUpgradeable for bytes32;

    uint256 public constant TOTAL_MAX_SUPPLY = 10020; 

    address public signatureVerifier;

    mapping(bytes32 => bool) public usedHashes;
    mapping(address => mapping(uint256 => bool)) public addressToTokenIdToInitalized;
    mapping(address => mapping(uint256 => uint256)) public addressToTokenIdToNonce;
    mapping(uint256 => uint256) public tokenIdToWhenMinted;

    string private _baseTokenURI;
    bool private initialized;

    function initialize() public initializer {
        require(!initialized, "Contract instance has already been initialized");
        initialized = true;
        __Ownable_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ERC721_init_unchained("SAMURISE", "SamuRise");
    }

    modifier hasValidSignature(bytes memory _signature, bytes memory message) {
        bytes32 messageHash = ECDSAUpgradeable.toEthSignedMessageHash(keccak256(message));
        require(messageHash.recover(_signature) == signatureVerifier, "Unrecognizable Hash");
        require(!usedHashes[messageHash], "Hash has already been used");

        usedHashes[messageHash] = true;
        _;
    }

    function mint(bytes memory _signature, uint256[] memory _tokenIds, uint256 _nonce)
        external
        hasValidSignature(_signature, abi.encodePacked(msg.sender, _tokenIds, _nonce))
    {
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(!_exists(_tokenIds[i]), "token already exists");
            require(_tokenIds[i] <= TOTAL_MAX_SUPPLY, "token id greater than MAX_SUPPLY");
            require(!addressToTokenIdToInitalized[msg.sender][_tokenIds[i]] || 
                    addressToTokenIdToNonce[msg.sender][_tokenIds[i]] < _nonce, "Nonce is not greater than previous nonce");

            addressToTokenIdToInitalized[msg.sender][_tokenIds[i]] = true;
            addressToTokenIdToNonce[msg.sender][_tokenIds[i]] = _nonce;
            tokenIdToWhenMinted[_tokenIds[i]] = block.timestamp;
            _mint(msg.sender, _tokenIds[i]);
        }
    }

    function burn(bytes memory _signature, uint256[] memory _tokenIds, uint256 _nonce) 
        external
        hasValidSignature(_signature, abi.encodePacked(msg.sender, _tokenIds, _nonce))
    {
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(_exists(_tokenIds[i]), "token does not exist");
            require(!addressToTokenIdToInitalized[msg.sender][_tokenIds[i]] || 
                    addressToTokenIdToNonce[msg.sender][_tokenIds[i]] < _nonce, "Nonce is not greater than previous nonce");

            addressToTokenIdToInitalized[msg.sender][_tokenIds[i]] = true;
            addressToTokenIdToNonce[msg.sender][_tokenIds[i]] = _nonce;
            tokenIdToWhenMinted[_tokenIds[i]] = 0;
            _burn(_tokenIds[i]);
        }
    }

    /* INTERNAL FUNCTIONS */ 

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /* OVERRIDE OF TRANSFER FUNCTIONS */ 
    
    /**
     * @dev overrides transferFrom to prevent transfer if token is staked
     */
    function transferFrom(address from, address to, uint256 tokenId) 
        public override(ERC721Upgradeable, IERC721Upgradeable)
    {
        revert("Token is soulbound, cannot transfer");
    }

    /**
     * @dev overrides safeTransferFrom to prevent transfer if token is staked
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) 
        public override(ERC721Upgradeable, IERC721Upgradeable)
    {
        revert("Token is soulbound, cannot transfer");
    }

    /**
     * @dev overrides safeTransferFrom to prevent transfer if token is staked
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) 
        public override(ERC721Upgradeable, IERC721Upgradeable)
    {
        revert("Token is soulbound, cannot transfer");
    }

    /* OWNER FUNCTIONS */

    function ownerMintToAddress(address _address, uint256[] memory _tokenIds)
        external
        onlyOwner
    {
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(!_exists(_tokenIds[i]), "token already exists");
            require(_tokenIds[i] <= TOTAL_MAX_SUPPLY, "token id greater than MAX_SUPPLY");

            tokenIdToWhenMinted[_tokenIds[i]] = block.timestamp;
            _mint(_address, _tokenIds[i]);
        }
    }

    function ownerBurn(uint256[] memory _tokenIds)
        external
        onlyOwner
    {
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(_exists(_tokenIds[i]), "token does not exist");
            
            tokenIdToWhenMinted[_tokenIds[i]] = 0;
            _burn(_tokenIds[i]);
        }
    }
   
    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function setSignatureVerifier(address _signatureVerifier)
        external
        onlyOwner
    {
        signatureVerifier = _signatureVerifier;
    }

   function _authorizeUpgrade(address) internal override onlyOwner {}
}

