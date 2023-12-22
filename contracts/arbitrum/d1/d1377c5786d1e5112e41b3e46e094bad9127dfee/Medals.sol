// contracts/Medals.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./OwnableUpgradeable.sol";
import "./MerkleProofUpgradeable.sol";
import "./ERC1155URIStorageUpgradeable.sol";
import "./ERC1155SupplyUpgradeable.sol";
import "./ERC1155BurnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";



contract Medals is   ERC1155Upgradeable, OwnableUpgradeable, UUPSUpgradeable,  ERC1155BurnableUpgradeable, ERC1155SupplyUpgradeable, ERC1155URIStorageUpgradeable{

    mapping(uint256 => Medal) medals;


    struct Medal {

        string name;
        mapping(uint256 => MintSet) mintSets;

        /*
        if remainingSupply = 0
        MintSet.currentSupply < MintSet.totalLimit
        can't mint

        比如Medal的这个remainingSupply是2000
        Medal有3种sellingSet，每种MintSet中的都是1000
        则先到先得 remainingSupply变为0时 各MintSet将不能继续工作
        */

        uint256 remainingSupply;
    }

    struct MintSet {
        uint256 cost;
        uint256 startTime;
        uint256 endTime;
        uint8 preLimit;
        uint256 totalLimit;
        uint256 currentSupply;
        mapping(address => uint256) mintRecord;
        bool needWl;
        bytes32 wlMerkleRoot;
    }

    struct MintSetInfo {
        uint256 cost;
        uint256 startTime;
        uint256 endTime;
        uint8 preLimit;
        uint256 totalLimit;
        uint256 currentSupply;
        bool needWl;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory _uri)  initializer  public {
        __ERC1155_init(_uri);
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __ERC1155URIStorage_init();
    }



    function withdraw(uint256 _balance) public payable onlyOwner {
        (bool os,) = payable(owner()).call{value : _balance}("");
        require(os);
    }


    function initMedal(uint256 _id, string memory _name, uint256 _remainingSupply) public onlyOwner {
        medals[_id].name = _name;
        medals[_id].remainingSupply = _remainingSupply;
    }

    function getName(uint256 _id) public view returns (string memory) {
        return medals[_id].name;
    }

    function setName(uint256 _id, string memory _name) public onlyOwner {
        medals[_id].name = _name;
    }

    function getRemainingSupply(uint256 _id) public view returns (uint256) {
        return medals[_id].remainingSupply;
    }

    function getMintInfo(uint256 _id, uint256 _type) public view returns (MintSetInfo memory) {
        MintSetInfo memory info = MintSetInfo(medals[_id].mintSets[_type].cost,
            medals[_id].mintSets[_type].startTime,
            medals[_id].mintSets[_type].endTime,
            medals[_id].mintSets[_type].preLimit,
            medals[_id].mintSets[_type].totalLimit,
            medals[_id].mintSets[_type].currentSupply,
            medals[_id].mintSets[_type].needWl);
        return info;
    }

    function getMintAddressRecord(uint256 _id, uint256 _type) public view returns (uint256) {

        return medals[_id].mintSets[_type].mintRecord[msg.sender];

    }


    function modifyMintSet(uint256 _id, uint256 _type, uint256 _cost,
        uint256 _startTime,
        uint256 _endTime,
        uint8 _preLimit,
        uint256 _totalLimit,
        uint256 _currentSupply,
        bool _needWl) public onlyOwner {

        medals[_id].mintSets[_type].cost = _cost;
        medals[_id].mintSets[_type].startTime = _startTime;
        medals[_id].mintSets[_type].endTime = _endTime;
        medals[_id].mintSets[_type].preLimit = _preLimit;
        medals[_id].mintSets[_type].totalLimit = _totalLimit;
        medals[_id].mintSets[_type].currentSupply = _currentSupply;
        medals[_id].mintSets[_type].needWl = _needWl;
    }

    function modifyMintSetSimple(uint256 _id, uint256 _type, uint256 _cost,
        uint256 _startTime,
        uint256 _endTime,
        uint8 _preLimit,
        bool _needWl) public onlyOwner {

        medals[_id].mintSets[_type].cost = _cost;
        medals[_id].mintSets[_type].startTime = _startTime;
        medals[_id].mintSets[_type].endTime = _endTime;
        medals[_id].mintSets[_type].preLimit = _preLimit;
        medals[_id].mintSets[_type].needWl = _needWl;
    }

    function setMintSetWlMerkleRoot(uint256 _id, uint256 _type, bytes32 _merkle) public onlyOwner {

        medals[_id].mintSets[_type].wlMerkleRoot = _merkle;

    }


    //_mint(address to, uint256 id, uint256 amount, bytes memory data)

    function mint(address _to, uint256 _id, uint256 amount) public onlyOwner {
        _mint(_to, _id, amount, "");
    }

    function mintPublic(address _to, uint256 _id, uint256 _amount, uint256 _mintSet, bytes32[] calldata _proof) public payable {
        MintSet storage mintSet = medals[_id].mintSets[_mintSet];
        require(
            block.timestamp > mintSet.startTime &&
            block.timestamp < mintSet.endTime,
            "activity offline"
        );

        require(_amount >= 1, "amount error");

        require(msg.value >= mintSet.cost * _amount, "insufficient funds");

        if (mintSet.needWl) {
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
            require(
                MerkleProofUpgradeable.verify(_proof, mintSet.wlMerkleRoot, leaf),
                "invalid proof"
            );
        }


        mintSet.currentSupply = mintSet.currentSupply + _amount;
        //revert when  medals[_id].remainingSupply - _amount < 0
        require(_amount <= medals[_id].remainingSupply, "medal total amount limit");
        medals[_id].remainingSupply = medals[_id].remainingSupply - _amount;

        require(mintSet.currentSupply <= mintSet.totalLimit, "mint total amount limit");

        mintSet.mintRecord[msg.sender] = mintSet.mintRecord[msg.sender] + _amount;
        require(mintSet.mintRecord[msg.sender] <= mintSet.preLimit, "pre amount limit");

        _mint(_to, _id, _amount, "");
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}


    function uri(uint256 _id) public view override(ERC1155URIStorageUpgradeable, ERC1155Upgradeable) returns (string memory) {
        return ERC1155URIStorageUpgradeable.uri(_id);
    }
    function _beforeTokenTransfer(address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data) internal override(ERC1155SupplyUpgradeable, ERC1155Upgradeable)
    {
        return ERC1155SupplyUpgradeable._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function setTokenURI(uint256 tokenId, string memory tokenURI) public  onlyOwner {
        _setURI( tokenId,  tokenURI);
    }
    function setTokenBaseURI(string memory buri_) public  onlyOwner {
        _setBaseURI(buri_);
    }

    function setBaseURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }


}

