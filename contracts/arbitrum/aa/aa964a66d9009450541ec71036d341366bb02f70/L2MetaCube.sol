// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {ERC721EnumerableUpgradeable} from "./ERC721EnumerableUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "./AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";

import {IL2MetaCube} from "./IL2MetaCube.sol";

contract L2MetaCube is IL2MetaCube, ERC721EnumerableUpgradeable, PausableUpgradeable, AccessControlEnumerableUpgradeable {

    // 0x2172861495e7b85edac73e3cd5fbb42dd675baadf627720e687bcfdaca025096;
    bytes32 private constant _ROLE_ADMIN = keccak256("ROLE_ADMIN");

    // 0xaeaef46186eb59f884e36929b6d682a6ae35e1e43d8f05f058dcefb92b601461;
    bytes32 private constant _ROLE_MINTER = keccak256("ROLE_MINTER");

    string private _baseURI_;

    mapping(uint8 => uint256) private _levelTokenId;

    function initialize() initializer public {
        __AccessControlEnumerable_init();
        __ERC721_init("L2MetaCube", "L2MetaCube");
        __ERC721Enumerable_init();
        __Pausable_init();
        //
        _setRoleAdmin(_ROLE_ADMIN, _ROLE_ADMIN);
        _setRoleAdmin(_ROLE_MINTER, _ROLE_ADMIN);
        //
        _grantRole(_ROLE_ADMIN, _msgSender());
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControlEnumerableUpgradeable, ERC721EnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function pause() public onlyRole(_ROLE_ADMIN) {
        _pause();
    }

    function unpause() public onlyRole(_ROLE_ADMIN) {
        _unpause();
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseURI_;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal whenNotPaused override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function setBaseURI(string calldata baseURI) external onlyRole(_ROLE_ADMIN) {
        _baseURI_ = baseURI;
    }

    function batchBurn(uint256[] calldata tokenIdArr) external {
        uint256 length = tokenIdArr.length;
        for (uint256 i_ = 0; i_ < length;) {
            uint256 tokenId = tokenIdArr[i_];
            require(_isApprovedOrOwner(_msgSender(), tokenId), "L2MetaCube: caller is not token owner or approved");
            _burn(tokenId);
            unchecked {i_++;}
        }
    }

    function mintForLevel(address to_, uint8 level_, uint256 levelStartTokenId_) external returns (uint256) {
        require(hasRole(_ROLE_MINTER, _msgSender()), "L2MetaCube: caller access denied");
        require(levelStartTokenId_ != 0, "L2MetaCube: level start tokenId is zero");
        if (_levelTokenId[level_] == 0) {
            _levelTokenId[level_] = levelStartTokenId_;
        } else {
            _levelTokenId[level_] += 1;
        }
        _safeMint(to_, _levelTokenId[level_]);
        return _levelTokenId[level_];
    }

    function viewLevelTokenIds(uint8[] calldata levelArr_) external view returns (uint256[] memory) {
        uint256 length = levelArr_.length;
        uint256[] memory tokenIdArr_ = new uint256[](length);
        for (uint256 i_ = 0; i_ < length;) {
            tokenIdArr_[i_] = _levelTokenId[levelArr_[i_]];
            unchecked {i_++;}
        }
        return tokenIdArr_;
    }

    function viewTokenIds(address account_, uint256 startIndex_, uint256 endIndex_) external view returns (uint256[] memory tokenIdArr_){
        if (startIndex_ >= 0 && endIndex_ >= startIndex_) {
            uint256 len = endIndex_ + 1 - startIndex_;
            uint256 total = balanceOf(account_);
            uint256 arrayLen = len > total ? total : len;
            tokenIdArr_ = new uint256[](arrayLen);
            uint256 arrayIndex_ = 0;
            for (uint256 index_ = startIndex_; index_ < ((endIndex_ > total) ? total : endIndex_);) {
                uint256 tokenId_ = tokenOfOwnerByIndex(account_, index_);
                tokenIdArr_[arrayIndex_] = tokenId_;
                unchecked{++index_; ++arrayIndex_;}
            }
        }
        return tokenIdArr_;
    }

}

