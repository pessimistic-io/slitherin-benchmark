// SPDX-License-Identifier: MIT
// Creator: base64.tech
pragma solidity ^0.8.13;

import "./UUPSUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ERC1155Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./console.sol";

interface ISamuMetadata {
    function equipSamuRise(uint256, uint256) external;
    function unequipSamuRise(uint256, uint256) external;
    function isSamuRiseEquipped(uint256 _samuriseTokenId, uint256 _collectionId) external returns (bool);
    function consume(uint256, uint256) external;
}

contract SamuRiseItemsV3 is ERC1155Upgradeable, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    using ECDSAUpgradeable for bytes32;
    using StringsUpgradeable for uint256;

    string public constant name = "SamuRiseItems"; 
    string public constant symbol = "SAMURISE_ITEMS";
 
    address public signatureVerifier;
    uint256 public collectionIndex;
    address public samuRiseMetadataState;

    mapping(uint256 => uint256) public tokenSupply; 
    mapping(uint256 => uint256) public tokenMaxSupply; 
    mapping(uint256 => ItemType) public collectionIdToItemType;
    mapping(uint256 => bool) public collectionIdToRandomMintExists;
    mapping(uint256 => string) public collectionIdToName;
    mapping(bytes32 => bool) public usedHashes;
    mapping(address => mapping(uint256 =>uint256)) public addressToCollectionToNumMinted;
    
    string private _tokenBaseURI; 

    enum ItemType { CONSUMABLE, EQUIPPABLE, TOTEM }

    enum ItemAction { MINT, CONSUME, EQUIP, UNEQUIP }
  
    /* V3 variables */
    address samuriseQuestContract;
    event BaseURIChanged(string from, string to);

    function initialize() public initializer {
        __ERC1155_init(name);
        __Ownable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        _pause();
    }

    modifier hasValidSignature(bytes memory _signature, bytes memory message) {
        bytes32 messageHash = ECDSAUpgradeable.toEthSignedMessageHash(keccak256(message));
        require(messageHash.recover(_signature) == signatureVerifier, "Unrecognizable Hash");
        require(!usedHashes[messageHash], "Hash has already been used");

        usedHashes[messageHash] = true;
        _;
    }

    modifier itemIsEquippable(uint256 _collectionId) {
        require(collectionIdToItemType[_collectionId] == ItemType.EQUIPPABLE, "item is not equippable");
        _;
    }

    modifier itemIsConsumable(uint256 _collectionId) {
        require(collectionIdToItemType[_collectionId] == ItemType.CONSUMABLE, "item is not consumable");
        _;
    }

    modifier userHoldsThisToken(uint256 _collectionId) {
        require(balanceOf(msg.sender, _collectionId) > 0, "User does not hold any of this token");
        _;
    }

    modifier doesNotExceedCollectionMax(uint256 _collectionId,uint256  _numberToMint)  {
        require(tokenSupply[_collectionId] + _numberToMint <= tokenMaxSupply[_collectionId], "minting would exceed maximum supply for this token");
        _;
    }

    modifier hasNotExceededMaxAllocation(address _address, uint256 _collectionId, uint256 _numberToClaim, uint256 _maxAllocation) {
        require(addressToCollectionToNumMinted[_address][_collectionId] + _numberToClaim <= _maxAllocation, "User has already minted maximum allowance for this collection");
        addressToCollectionToNumMinted[_address][_collectionId] += _numberToClaim;
        _;
    }

    modifier calledFromQuestContract() {
        console.log(msg.sender);
        console.log(samuriseQuestContract);
        require(msg.sender == samuriseQuestContract, "method was not called from Samurise Quest contract");
        _;
    }

    function isValidTokenId(uint256 _collectionId) internal view returns (bool) {
        return _collectionId >= 0 && _collectionId <= collectionIndex;
    }

    function mint(bytes memory _signature, uint256 _collectionId, uint256 _numberToClaim, uint256 _maxAllocation, uint256 _nonce) 
        public
        whenNotPaused 
        doesNotExceedCollectionMax(_collectionId, _numberToClaim)
        hasNotExceededMaxAllocation(msg.sender, _collectionId, _numberToClaim, _maxAllocation)
        hasValidSignature(_signature, abi.encodePacked(msg.sender, uint256(ItemAction.MINT), _collectionId, _numberToClaim, _maxAllocation, _nonce)) 
    {
        _mintItem(msg.sender, _collectionId, _numberToClaim);
    }

    function mintFromQuest(address _originator, uint256 _collectionId, uint256 _numberToClaim, uint256 _maxAllocation) 
        public
        whenNotPaused 
        doesNotExceedCollectionMax(_collectionId, _numberToClaim)
        hasNotExceededMaxAllocation(_originator, _collectionId, _numberToClaim, _maxAllocation)
        calledFromQuestContract()
    {
        _mintItem(_originator, _collectionId, _numberToClaim);
    }

    function _mintItem(address _targetAddress, uint256 _collectionId, uint256 _numberToClaim) private {
         tokenSupply[_collectionId] += _numberToClaim;
        _mint(_targetAddress, _collectionId, _numberToClaim, "");
    }

    function equip(bytes memory _signature, uint256 _collectionId, uint256 _samuriseTokenId, uint256 _nonce) 
        public 
        whenNotPaused 
        itemIsEquippable(_collectionId)
        userHoldsThisToken(_collectionId)
        hasValidSignature(_signature, abi.encodePacked(msg.sender, uint256(ItemAction.EQUIP), _collectionId, _samuriseTokenId, _nonce)) 
    {
        require(!ISamuMetadata(samuRiseMetadataState).isSamuRiseEquipped(_samuriseTokenId, _collectionId), "Item is already equipped to this samurise");

        ISamuMetadata(samuRiseMetadataState).equipSamuRise(_samuriseTokenId, _collectionId);
        tokenSupply[_collectionId]--;
        _burn(msg.sender, _collectionId,1);
    }

    function unequip(bytes memory _signature, uint256 _collectionId, uint256 _samuriseTokenId,  uint256 _nonce) 
        public 
        whenNotPaused 
        itemIsEquippable(_collectionId)
        hasValidSignature(_signature, abi.encodePacked(msg.sender, uint256(ItemAction.UNEQUIP), _collectionId, _samuriseTokenId, _nonce)) 
    {
        require(ISamuMetadata(samuRiseMetadataState).isSamuRiseEquipped(_samuriseTokenId, _collectionId), "Item is not equipped on this samurise");
        
        ISamuMetadata(samuRiseMetadataState).unequipSamuRise(_samuriseTokenId, _collectionId);
        tokenSupply[_collectionId]++;
        _mint(msg.sender, _collectionId, 1, "");
    }

    function consume(bytes memory _signature, uint256 _collectionId, uint256 _samuriseTokenId,  uint256 _nonce)
        public 
        whenNotPaused 
        itemIsConsumable(_collectionId)
        userHoldsThisToken(_collectionId)
        hasValidSignature(_signature, abi.encodePacked(msg.sender, uint256(ItemAction.CONSUME), _collectionId, _samuriseTokenId, _nonce))
    {
        ISamuMetadata(samuRiseMetadataState).consume(_samuriseTokenId, _collectionId);
        tokenSupply[_collectionId]--;
        _burn(msg.sender, _collectionId, 1);
    }

    function uri(uint256 _tokenId) override public view returns (string memory) {
        require(isValidTokenId(_tokenId), "invalid id");
        return string(abi.encodePacked(_tokenBaseURI, _tokenId.toString(), ".json")); 
    }
    
    function totalSupply(uint256 _id) external view returns (uint256) {
        require(isValidTokenId(_id), "invalid id");
        return tokenSupply[_id]; 
    }

    function getTotalNumberOfCollections() public view returns (uint256) {
        return collectionIndex;
    }

    function getCollectionName(uint256 _collectionId) public view returns(string memory) {
        return collectionIdToName[_collectionId];
    }

    function getTokenSupply(uint256 _collectionId) external view returns (uint256){
        return tokenSupply[_collectionId];
    }

    function getTokenMaxSupply(uint256 _collectionId) external view returns (uint256){
        return tokenMaxSupply[_collectionId];
    }

    /* OWNER FUNCTIONS */

    function addCollection(ItemType _itemType, uint256 _totalSupply, string memory _collectionName) external onlyOwner {
        tokenMaxSupply[collectionIndex] = _totalSupply;
        collectionIdToItemType[collectionIndex] = _itemType;
        collectionIdToName[collectionIndex] = _collectionName;

        collectionIndex++;
    }

    function ownerMint(uint256 _collectionId, uint256 _numberToMint)  
        external 
        onlyOwner
        doesNotExceedCollectionMax(_collectionId, _numberToMint)  
    {
        tokenSupply[_collectionId] += _numberToMint;
        _mint(msg.sender, _collectionId, _numberToMint, "");
    }

    function setSamuRiseMetadataState(address _samuRiseMetadataState) external onlyOwner {
        samuRiseMetadataState = _samuRiseMetadataState;
    }

    function setSignatureVerifier(address _signatureVerifier) external onlyOwner {
        signatureVerifier = _signatureVerifier;
    }
    
    function setBaseURI(string memory _URI) external onlyOwner {
        emit BaseURIChanged(_tokenBaseURI, _URI);
        _tokenBaseURI = _URI;
    }
    

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setSamuriseQuestContract(address _address) external onlyOwner {
        samuriseQuestContract = _address;
    }

     
   function _authorizeUpgrade(address) internal override onlyOwner {}
}
