// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./SemanticBaseStruct.sol";
import {StringUtils} from "./StringUtils.sol";


library NameServiceLogic {
    using StringUtils for *;

    uint256 constant HOLD_PREDICATE_INDEX = 1;
    uint256 constant RESOLVE_PREDICATE_INDEX = 2;

    function register(uint256 tokenId, address owner, uint256 sIndex, bool resolve,
        mapping(uint256 => uint256) storage _tokenIdOfName,
        mapping(uint256 => uint256) storage _nameOf,
        mapping(address => uint256) storage _ownedResolvedName,
        mapping(uint256 => address) storage _ownerOfResolvedName,
        mapping(uint256 => uint256) storage _tokenIdOfResolvedName) external returns (SubjectPO[] memory) {
        _tokenIdOfName[sIndex] = tokenId;
        _nameOf[tokenId] = sIndex;
        SubjectPO[] memory subjectPOList = new SubjectPO[](1);
        if (resolve) {
            setNameForAddr(owner, sIndex, _tokenIdOfName, _ownedResolvedName,
                _ownerOfResolvedName, _tokenIdOfResolvedName);
            subjectPOList[0] = SubjectPO(RESOLVE_PREDICATE_INDEX, sIndex);
        } else {
            subjectPOList[0] = SubjectPO(HOLD_PREDICATE_INDEX, sIndex);
        }
        return subjectPOList;
    }


    /**
     * To set a record for resolving the name, linking the name to an address.
     * @param addr : The owner of the name. If the address is zero address, then the link is canceled.
     */
    function setNameForAddr(address addr, uint256 dSIndex,
        mapping(uint256 => uint256) storage _tokenIdOfName, mapping(address => uint256) storage _ownedResolvedName,
        mapping(uint256 => address) storage _ownerOfResolvedName, mapping(uint256 => uint256) storage _tokenIdOfResolvedName) public {
        if (addr != address(0)) {
            require(_ownerOfResolvedName[dSIndex] == address(0), "NameService:already resolved");
            if(_ownedResolvedName[addr] != 0){
                delete _ownerOfResolvedName[_ownedResolvedName[addr]];
            }
        } else {
            require(_ownerOfResolvedName[dSIndex] != address(0), "NameService:not resolved");
            delete _ownedResolvedName[_ownerOfResolvedName[dSIndex]];
        }
        _ownedResolvedName[addr] = dSIndex;
        _ownerOfResolvedName[dSIndex] = addr;
        _tokenIdOfResolvedName[dSIndex] = _tokenIdOfName[dSIndex];
    }

    function updatePIndexOfToken(address addr, SPO storage spo) public {
        if (addr == address(0)) {
            spo.pIndex[0] = HOLD_PREDICATE_INDEX;
        } else {
            spo.pIndex[0] = RESOLVE_PREDICATE_INDEX;
        }
    }


    function checkValidLength(string memory name,
        uint256 _minNameLength,
        uint256 _maxNameLength,
        mapping(uint256 => uint256) storage _nameLengthControl,
        mapping(uint256 => uint256) storage _countOfNameLength) external view returns (bool){
        uint256 len = name.strlen();
        if (len < _minNameLength || len > _maxNameLength) {
            return false;
        }
        if (_nameLengthControl[len] == 0) {
            return true;
        } else if (_nameLengthControl[len] - _countOfNameLength[len] > 0) {
            return true;
        }
        return false;
    }
}
