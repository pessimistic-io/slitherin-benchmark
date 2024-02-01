// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./ERC721URIStorageUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./MerkleProof.sol";
import "./ERC721RoyaltyUpgradeable.sol";
import "./NativeMetaTransactionUpgradeable.sol";
import "./ContextMixin.sol";


/// @custom:security-contact mihindu@alphadevs.com
contract FloatingFriendsNFT is Initializable, ERC721Upgradeable, ERC721EnumerableUpgradeable,ERC721RoyaltyUpgradeable, ERC721URIStorageUpgradeable, PausableUpgradeable, AccessControlUpgradeable, ERC721BurnableUpgradeable, UUPSUpgradeable,NativeMetaTransactionUpgradeable,ContextMixin {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    
    /**
     * @notice Merkle root hash for whitelist addresses
     */
    bytes32 public _merkleRoot;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    CountersUpgradeable.Counter private _tokenIdCounter;
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    string private _baseURIextended;
    string private _updatedContractURI;
    uint256 _mintPrice;
    uint256 _mintWhitelistedPrice;
    bool private _isContractPaused;
    bool private _isContractPausedByAdmin;
    uint private _maxSupply;
    uint private _getFreeBuyCount;
    uint private _getFree;
    uint private _promoBefore;
    uint private _salesStarsIn;
    mapping(address => uint) private _promoClaimers;
    uint private _maxWhitelistCountPerWallet;
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(string memory name, string memory symbol,uint mintPrice, uint saleStartsIn ,string memory baseURI,uint maxSupply,uint getFreeBuyCount,uint getFree,uint promoBefore,address royaltyReceiver,uint96 royaltyFeeBasePoint,bytes32 merkleRoot) initializer public {
        _merkleRoot = merkleRoot;
        _mintPrice = mintPrice;
        _mintWhitelistedPrice = mintPrice;
        _maxWhitelistCountPerWallet = 3;
        _maxSupply = maxSupply;        
        _setPromoDetails(getFreeBuyCount, getFree, promoBefore);
        _salesStarsIn = block.timestamp + ( saleStartsIn * 1 minutes);
        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __EIP712_init(name);
        __Pausable_init();
        __AccessControl_init();
        __ERC721Burnable_init();
        __UUPSUpgradeable_init();
        __ERC721Royalty_init();

        _grantRole(DEFAULT_ADMIN_ROLE, 0x3Fccf88790840682C45BcDa9446602aE1FCeDb2d);
        _grantRole(PAUSER_ROLE, _msgSender());
        _grantRole(MINTER_ROLE, _msgSender());
        _grantRole(UPGRADER_ROLE, _msgSender());
        setBaseURI(baseURI);
        _updatedContractURI = baseURI;
        _setDefaultRoyalty(royaltyReceiver, royaltyFeeBasePoint);

    }

    function setAdminRole(bytes32 role, address account) public onlyRole(UPGRADER_ROLE) {
        _grantRole(role, account);
    }

    function setMintPrice(uint _setMintPrice) public onlyRole(UPGRADER_ROLE) {
        _mintPrice = _setMintPrice;
    }

    function setWhitelistMintPrice(uint _setwhitelistMintPrice) public onlyRole(UPGRADER_ROLE) {
        _mintWhitelistedPrice = _setwhitelistMintPrice;
    }

    function setMaxWhitelistCountPerWallet(uint _setMaxWhitelistCountPerWallet) public onlyRole(UPGRADER_ROLE) {
        _maxWhitelistCountPerWallet = _setMaxWhitelistCountPerWallet;
    }

    function setSaleStart(uint _saleStartsIn) public onlyRole(UPGRADER_ROLE) {
        _salesStarsIn = block.timestamp + ( _saleStartsIn * 1 minutes);
    }

    function contractURI() public view returns (string memory) {
        return string(abi.encodePacked(_updatedContractURI , "contractMetadata"));
    }

    function setContractURI(string memory baseContractURI_) public onlyRole(MINTER_ROLE) {
        _updatedContractURI = baseContractURI_;
    }
    
    function setBaseURI(string memory baseURI_) public onlyRole(MINTER_ROLE) {
        _baseURIextended = baseURI_;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIextended;
    }

    function _setPromoDetails(uint getFreeBuyCount,uint getFree,uint promoBefore) internal virtual {
        _getFreeBuyCount = getFreeBuyCount;
        _getFree = getFree;
        _promoBefore = promoBefore;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        require(!_isContractPausedByAdmin, "the contract is already paused by admin");
        _isContractPaused = true;
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        require(!_isContractPausedByAdmin, "the contract is paused by admin only admin can unpause");
        _isContractPaused = false;
        _unpause();
    }

    function safeMint(address to) public onlyRole(MINTER_ROLE) {
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, '');
    }

    function setTokenURI(uint256 tokenId, string memory _tokenURI) public onlyRole(MINTER_ROLE) {
        _setTokenURI(tokenId, _tokenURI);
    }

    function mintAsset(uint256 _mintAmount) public payable {
        require(!_isContractPaused, "the contract is paused");        
        require(_mintAmount > 0, "need to mint at least 1 NFT");
        require(msg.value == _mintPrice * _mintAmount, "Not Enough Ether");
        require(block.timestamp >= _salesStarsIn,"Sale not Started");
        // Handle Buy X get X free for First X NFTs
        if(_getFreeBuyCount >0 && _getFree > 0 && _mintAmount >= _getFreeBuyCount && totalSupply() < _promoBefore && _promoClaimers[_msgSender()] == 0 ){
            _promoClaimers[_msgSender()] += 1;
            _mintAmount +=  1;
        }
        require((totalSupply() + _mintAmount ) < _maxSupply, "maxSupply Reached");
        for (uint i=0; i<_mintAmount; i++) {
            _tokenIdCounter.increment();
            uint256 tokenId = _tokenIdCounter.current();        
            _safeMint(_msgSender(), tokenId);
            _setTokenURI(tokenId, '');
        }    
    }    

    function mintAssetWhitelisted(uint256 _mintAmount,bytes32[] calldata _merkleProof) public payable {
        require(!_isContractPaused, "the contract is paused");
        require(verifyAddress(_merkleProof), "INVALID_PROOF");
        require(_mintAmount > 0, "need to mint at least 1 NFT");
        require(msg.value == _mintWhitelistedPrice * _mintAmount, "Not Enough Ether");
        // Handle Max Sale Purchases
        require((balanceOf(_msgSender()) + _mintAmount) <= _maxWhitelistCountPerWallet, "Max Sale Limit Reached - Only 3 per Wallet");
        require((totalSupply() + _mintAmount ) < _maxSupply, "maxSupply Reached");
        for (uint i=0; i<_mintAmount; i++) {
            _tokenIdCounter.increment();
            uint256 tokenId = _tokenIdCounter.current();        
            _safeMint(_msgSender(), tokenId);
            _setTokenURI(tokenId, '');
        }    
    }    

    function adminPause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _isContractPausedByAdmin = true;
        _pause();
    }

    function adminUnpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _isContractPausedByAdmin = false;
        _unpause();
    }

    function adminWithdraw() public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint balance = address(this).balance;
        payable(_msgSender()).transfer(balance);
    }
   
    function withdraw() public whenNotPaused onlyRole(MINTER_ROLE) {
        uint balance = address(this).balance;
        payable(_msgSender()).transfer(balance);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId)
        internal
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable,ERC721RoyaltyUpgradeable)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function countClaimed(address claimedAddress)
        public
        view
        returns ( uint256)
    {
        return _promoClaimers[claimedAddress];
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable,ERC721RoyaltyUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

     // This is to support Native meta transactions, never use msg.sender directly, use _msgSender() instead
    function _msgSender() internal override view returns (address) {
        return ContextMixin.msgSender();
    }

     /**
     * @notice Change merkle root hash
     */
    function setMerkleRoot(bytes32 merkleRootHash) external onlyRole(MINTER_ROLE)
    {
        _merkleRoot = merkleRootHash;
    }

    /**
     * @notice Verify merkle proof of the address
     */
    function verifyAddress(bytes32[] calldata _merkleProof) private 
    view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
        return MerkleProof.verify(_merkleProof, _merkleRoot, leaf);
    }


    // Modifiers
    modifier isWhitelisted(bytes32[] calldata _merkleProof) {
        require(verifyAddress(_merkleProof), "INVALID_PROOF");
        _;
    }

    
   
}

