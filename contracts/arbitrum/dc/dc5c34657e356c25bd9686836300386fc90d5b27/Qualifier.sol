// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./AccessControl.sol";
import "./EnumerableSet.sol";
import "./IQualifier.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @title Qualifier contract qualifies the user and the asset to be used for lending
/// @author DeFragDAO
/// @custom:experimental This is an experimental contract
contract Qualifier is IQualifier, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private allowListUsers;
    EnumerableSet.UintSet private allowListTokenIds;

    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");

    // Events For Whitelisting User Addresses
    event AddedUserToAllowList(address indexed operator, address user);
    event RemovedUserFromAllowList(address indexed operator, address user);

    // Events For Whitelisting Smols721 IDs
    event AddedTokenIdToAllowList(address indexed operator, uint256 tokenId);
    event RemovedTokenIdFromAllowList(
        address indexed operator,
        uint256 tokenId
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice gets all user on allow list
     * @return array - allow list array
     */
    function getUsersAllowList() public view returns (address[] memory) {
        return EnumerableSet.values(allowListUsers);
    }

    /**
     * @notice gets all Ids on allow list
     * @return array - all tokenIds on allow list
     */
    function getTokenIdsAllowList() public view returns (uint256[] memory) {
        return EnumerableSet.values(allowListTokenIds);
    }

    /**
     * @notice checks if specific user is on allow list
     * @return bool - returns true if user is on allow list
     */
    function isUserAllowListed(
        address _userAddress
    ) public view returns (bool) {
        return EnumerableSet.contains(allowListUsers, _userAddress);
    }

    /**
     * @notice checks if specific tokenId is on allow list
     * @return bool - returns true if tokenId is on allow list
     */
    function isTokenIdAllowListed(uint256 _tokenId) public view returns (bool) {
        return EnumerableSet.contains(allowListTokenIds, _tokenId);
    }

    /**
     * @notice adds user to allow list
     */
    function addToUsersAllowList(address _userAddress) public onlyAdmin {
        EnumerableSet.add(allowListUsers, _userAddress);
        emit AddedUserToAllowList(msg.sender, _userAddress);
    }

    /**
     * @notice adds tokenId to allow list
     */
    function addToTokenIdsAllowList(uint256 _tokenId) public onlyAdmin {
        EnumerableSet.add(allowListTokenIds, _tokenId);
        emit AddedTokenIdToAllowList(msg.sender, _tokenId);
    }

    /**
     * @notice removes user to allow list
     */
    function removeFromUsersAllowList(address _userAddress) public onlyAdmin {
        EnumerableSet.remove(allowListUsers, _userAddress);
        emit RemovedUserFromAllowList(msg.sender, _userAddress);
    }

    /**
     * @notice removes tokenId to allow list
     */
    function removeFromTokenIdsAllowList(uint256 _tokenId) public onlyAdmin {
        EnumerableSet.remove(allowListTokenIds, _tokenId);
        emit RemovedTokenIdFromAllowList(msg.sender, _tokenId);
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFRAG_SYSTEM_ADMIN_ROLE, msg.sender),
            "Qualifier: caller not admin"
        );
        _;
    }
}

