// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./IERC1155.sol";
import "./AccessControlEnumerable.sol";

contract BadgeManager is AccessControlEnumerable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    mapping(address => mapping(uint256 => uint256)) public badgesBoostedMapping; // badge address => id => boosted number (should divided by 1e18)
    mapping(address => mapping(uint256 => bool)) public inBadgesList; // badge address => id => bool

    BadgeData[] public badgesList;

    mapping(address => Delegation[]) public delegationsOfDelegate; // delegate => { owner, badge => { badge address, id } }
    mapping(address => mapping(address => mapping(uint256 => address))) public delegatedListByDelegate; // delegate => badge address => id => owner
    mapping(address => mapping(address => mapping(uint256 => address))) public delegatedListByOwner; //owner => badge address => id => delegator

    mapping(address => bool) public ineligibleList;

    bool public migrationIsOn;

    event BadgeAdded(address indexed _badgeAddress, uint256 _id, uint256 _boostedNumber);
    event BadgeUpdated(address indexed _badgeAddress, uint256 _id, uint256 _boostedNumber);
    event IneligibleListAdded(address indexed _address);
    event IneligibleListRemoved(address indexed _address);

    struct BadgeData {
        address contractAddress;
        uint256 tokenId;
    }

    struct Delegation {
        address owner;
        BadgeData badge;
    }

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
    }

    function getBadgeMultiplier(address _depositorAddress) public view returns (uint256) {
        uint256 badgeMultiplier = 0;

        if (ineligibleList[_depositorAddress]) {
            return badgeMultiplier;
        }

        for (uint256 index = 0; index < delegationsOfDelegate[_depositorAddress].length; index++) {
            Delegation memory delegateBadge = delegationsOfDelegate[_depositorAddress][index];
            BadgeData memory badge = delegateBadge.badge;
            if (IERC1155(badge.contractAddress).balanceOf(delegateBadge.owner, badge.tokenId) > 0) {
                badgeMultiplier = badgeMultiplier + (badgesBoostedMapping[badge.contractAddress][badge.tokenId]);
            }
        }

        return badgeMultiplier;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "BadgeManager: only admin");
        _;
    }

    function delegateBadgeTo(address _badgeContract, uint256 _tokenId, address _delegate) external {
        require(inBadgesList[_badgeContract][_tokenId], "BadgeManager.delegateBadgeTo: invalid badge");

        require(
            IERC1155(_badgeContract).balanceOf(msg.sender, _tokenId) > 0,
            "BadgeManager.delegateBadgeTo: You do not own the badge"
        );

        require(
            delegatedListByOwner[msg.sender][_badgeContract][_tokenId] == address(0),
            "BadgeManager.delegateBadgeTo: already delegated"
        );

        require(
            delegatedListByDelegate[_delegate][_badgeContract][_tokenId] == address(0),
            "BadgeManager.delegateBadgeTo: delegate has already been delegated for the same badge"
        );

        delegationsOfDelegate[_delegate].push(
            Delegation({ owner: msg.sender, badge: BadgeData({ contractAddress: _badgeContract, tokenId: _tokenId }) })
        );

        delegatedListByOwner[msg.sender][_badgeContract][_tokenId] = _delegate;
        delegatedListByDelegate[_delegate][_badgeContract][_tokenId] = msg.sender;
    }

    function addBadge(address _badgeAddress, uint256 _id, uint256 _boostedNumber) external onlyAdmin {
        _addBadge(_badgeAddress, _id, _boostedNumber);
    }

    function batchAddBadges(
        address[] memory _badgeAddresses,
        uint256[] memory _ids,
        uint256[] memory _boostedNumbers
    ) external onlyAdmin {
        require(
            _badgeAddresses.length == _ids.length && _ids.length == _boostedNumbers.length,
            "BadgeManager.batchAddBadge: arrays length mismatch"
        );

        for (uint256 i = 0; i < _badgeAddresses.length; i++) {
            _addBadge(_badgeAddresses[i], _ids[i], _boostedNumbers[i]);
        }
    }

    function _addBadge(address _badgeAddress, uint256 _id, uint256 _boostedNumber) internal {
        require(
            !inBadgesList[_badgeAddress][_id],
            "BadgeManager._addBadge: already in badgelist, please try to update"
        );

        inBadgesList[_badgeAddress][_id] = true;
        badgesList.push(BadgeData({ contractAddress: _badgeAddress, tokenId: _id }));
        badgesBoostedMapping[_badgeAddress][_id] = _boostedNumber;
        emit BadgeAdded(_badgeAddress, _id, _boostedNumber);
    }

    function updateBadge(address _badgeAddress, uint256 _id, uint256 _boostedNumber) external onlyAdmin {
        _updateBadge(_badgeAddress, _id, _boostedNumber);
    }

    function batchUpdateBadges(
        address[] memory _badgeAddresses,
        uint256[] memory _ids,
        uint256[] memory _boostedNumbers
    ) external onlyAdmin {
        require(
            _badgeAddresses.length == _ids.length && _ids.length == _boostedNumbers.length,
            "BadgeManager.batchUpdateBadges: arrays length mismatch"
        );

        for (uint256 i = 0; i < _badgeAddresses.length; i++) {
            _updateBadge(_badgeAddresses[i], _ids[i], _boostedNumbers[i]);
        }
    }

    function _updateBadge(address _badgeAddress, uint256 _id, uint256 _boostedNumber) internal {
        require(
            inBadgesList[_badgeAddress][_id],
            "BadgeManager._updateBadge: badgeAddress not in badgeList, please try to add first"
        );

        badgesBoostedMapping[_badgeAddress][_id] = _boostedNumber;
        emit BadgeUpdated(_badgeAddress, _id, _boostedNumber);
    }

    function addIneligibleList(address _address) external onlyAdmin {
        require(
            !ineligibleList[_address],
            "BadgeManager.addIneligibleList: address already in ineligiblelist, please try to update"
        );
        ineligibleList[_address] = true;
        emit IneligibleListAdded(_address);
    }

    function removeIneligibleList(address _address) external onlyAdmin {
        require(
            ineligibleList[_address],
            "BadgeManager.removeIneligibleList: address not in ineligiblelist, please try to add first"
        );
        ineligibleList[_address] = false;
        emit IneligibleListRemoved(_address);
    }

    function getDelegationsOfDelegate(address _delegate) public view returns (Delegation[] memory) {
        return delegationsOfDelegate[_delegate];
    }

    function getDelegationsOfDelegateLength(address _delegate) public view returns (uint256) {
        return delegationsOfDelegate[_delegate].length;
    }

    function getDelegateByBadge(
        address _owner,
        address _badgeContract,
        uint256 _tokenId
    ) public view returns (address) {
        return delegatedListByOwner[_owner][_badgeContract][_tokenId];
    }

    function getDelegateByBadges(
        address[] memory _ownerAddresses,
        address[] memory _badgeContracts,
        uint256[] memory _tokenIds
    ) public view returns (address[] memory) {
        require(_badgeContracts.length == _tokenIds.length, "BadgeManager.getDelegateByBadges: arrays length mismatch");
        require(_ownerAddresses.length == _tokenIds.length, "BadgeManager.getDelegateByBadges: arrays length mismatch");

        address[] memory delegatedAddresses = new address[](_badgeContracts.length);
        for (uint256 i = 0; i < _badgeContracts.length; i++) {
            delegatedAddresses[i] = delegatedListByOwner[_ownerAddresses[i]][_badgeContracts[i]][_tokenIds[i]];
        }
        return delegatedAddresses;
    }
}

