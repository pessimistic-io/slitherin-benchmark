// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./EnumerableSet.sol";
import "./ERC1155Tradable.sol";

contract MetaboardsNfts is ERC1155Tradable {
    using EnumerableSet for EnumerableSet.AddressSet;


    // Types 
    // 1 - property
    // 2 - player
    // 3 - power up
    // 4 - farm boost
    // 5 - value boost

    // classes
    // 1 - common
    // 2 - silver
    // 3 - gold
    // 4 - rare
    // 5 - epic
    // 6 - legend

    struct NftAttributes {
        int256 nftType; // index of the nft type
        int256 nftClass; // rarity class
        int256 nftSetId; // Set this belongs to
        int256 other; // lock time reduction/other stats


    }

    EnumerableSet.AddressSet private _systemContracts;

    // mapping of nft ids that are locked and can not be transfered to anything but a system contract
    mapping(uint256 => bool) public accountLocked;

    // attributes used in game play
    mapping(uint256 => NftAttributes) public nftAttributes;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri
    ) ERC1155Tradable(_name, _symbol, _uri) {

        require(
            _systemContracts.add(address(0)) &&
            _systemContracts.add(address(this)), "error adding system contract");
    }
    event TokenCreated(address indexed account, uint256 tokenId, uint256 maxSupply, uint256 initialSupply );
    
    function create(
        uint256 _maxSupply,
        uint256 _initialSupply,
        string calldata _uri,
        bytes calldata _data,
        bool _accountLocked,
        int256[4] calldata _attrs
    ) public returns (uint256 tokenId) {
        uint256 _id =  super.create(_maxSupply, _initialSupply,_uri,_data);
        
        nftAttributes[_id] = NftAttributes({
            nftType: _attrs[0],
            nftClass: _attrs[1],
            nftSetId: _attrs[2],
            other: _attrs[3]

        });

        if(_accountLocked){
            accountLocked[_id] = true;
        }

        emit TokenCreated(msg.sender,_id,_maxSupply,_initialSupply);
        return _id;
    }

    function setAttributes(uint256 _id, int256[4] calldata _attrs)  external onlyOwner {
        nftAttributes[_id] = NftAttributes({
            nftType: _attrs[0],
            nftClass: _attrs[1],
            nftSetId: _attrs[2],
            other: _attrs[3]
        });
    }

    function addSystemContractAddress(address _addr) external onlyOwner {
        require(_systemContracts.add(_addr), 'list error');
    }

    function removeSystemContractAddress(address _addr) external onlyOwner {
        require(_systemContracts.remove(_addr), 'list error');
    }

    function getAttributes(uint256 _id) external view returns (int256[4] memory){
        return [nftAttributes[_id].nftType,nftAttributes[_id].nftClass,nftAttributes[_id].nftSetId,nftAttributes[_id].other];
    }

    function getCurrentTokenId() public view returns(uint256){
      return _currentTokenID;
    }

    function getNextTokenID() public view returns(uint256){
      return _getNextTokenID();
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override virtual {
        super._beforeTokenTransfer(operator,from,to,ids,amounts,data);

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            require(!accountLocked[id] || _systemContracts.contains(to) || _systemContracts.contains(from), 'account locked');
        }

    }

}
