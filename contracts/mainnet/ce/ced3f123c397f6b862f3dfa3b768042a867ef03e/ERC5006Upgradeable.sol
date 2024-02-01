// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

import "./ERC1155Upgradeable.sol";
import "./ERC1155ReceiverUpgradeable.sol";
import "./EnumerableSet.sol";
import "./IERC5006.sol";

contract ERC5006Upgradeable is
    ERC1155Upgradeable,
    ERC1155ReceiverUpgradeable,
    IERC5006
{
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(uint256 => mapping(address => uint256)) private _frozens;

    mapping(uint256 => UserRecord) private _records;

    mapping(uint256 => mapping(address => EnumerableSet.UintSet))
        private _userRecordIds;

    uint256 _curRecordId;
    uint8 recordLimit = 10;

    function initialize(string memory uri_, uint8 recordLimit_)
        public
        initializer
    {
        __ERC1155_init(uri_);
        recordLimit = recordLimit_;
    }

    function isOwnerOrApproved(address owner) public view returns (bool) {
        require(
            owner == msg.sender || isApprovedForAll(owner, msg.sender),
            "only owner or approved"
        );
        return true;
    }

    function usableBalanceOf(address user, uint256 tokenId)
        public
        view
        override
        returns (uint256 amount)
    {
        uint256[] memory recordIds = _userRecordIds[tokenId][user].values();
        for (uint256 i = 0; i < recordIds.length; i++) {
            if (block.timestamp <= _records[recordIds[i]].expiry) {
                amount += _records[recordIds[i]].amount;
            }
        }
    }

    function frozenBalanceOf(address owner, uint256 tokenId)
        public
        view
        override
        returns (uint256)
    {
        return _frozens[tokenId][owner];
    }

    function userRecordOf(uint256 recordId)
        public
        view
        override
        returns (UserRecord memory)
    {
        return _records[recordId];
    }

    function createUserRecord(
        address owner,
        address user,
        uint256 tokenId,
        uint64 amount,
        uint64 expiry
    ) public override returns (uint256) {
        require(isOwnerOrApproved(owner));
        require(amount > 0, "invalid amount");
        require(expiry > block.timestamp, "invalid expiry");
        require(
            _userRecordIds[tokenId][user].length() < recordLimit,
            "user cannot have more records"
        );
        _safeTransferFrom(owner, address(this), tokenId, amount, "");
        _frozens[tokenId][owner] += amount;
        _curRecordId++;
        _records[_curRecordId] = UserRecord(
            tokenId,
            owner,
            amount,
            user,
            expiry
        );
        _userRecordIds[tokenId][user].add(_curRecordId);
        emit CreateUserRecord(
            _curRecordId,
            tokenId,
            amount,
            owner,
            user,
            expiry
        );
        return _curRecordId;
    }

    function deleteUserRecord(uint256 recordId) public override {
        UserRecord storage _record = _records[recordId];
        require(isOwnerOrApproved(_record.owner));
        _safeTransferFrom(
            address(this),
            _record.owner,
            _record.tokenId,
            _record.amount,
            ""
        );
        _frozens[_record.tokenId][_record.owner] -= _record.amount;
        _userRecordIds[_record.tokenId][_record.user].remove(recordId);
        delete _records[recordId];
        emit DeleteUserRecord(recordId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155Upgradeable, ERC1155ReceiverUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IERC5006).interfaceId ||
            ERC1155Upgradeable.supportsInterface(interfaceId) ||
            ERC1155ReceiverUpgradeable.supportsInterface(interfaceId);
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return IERC1155ReceiverUpgradeable.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return IERC1155ReceiverUpgradeable.onERC1155BatchReceived.selector;
    }
}

