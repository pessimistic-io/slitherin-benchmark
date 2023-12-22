// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./AccessControl.sol";
import "./EnumerableSet.sol";
import "./ILegionMetadataStore.sol";
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

    address public legionsMetadataAddress;

    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");

    event AddedToTheList(address indexed operator, address user);
    event RemovedFromTheList(address indexed operator, address user);

    constructor(address _legionsMetadataAddress) {
        legionsMetadataAddress = _legionsMetadataAddress;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function getAllowList() public view returns (address[] memory) {
        return EnumerableSet.values(allowListUsers);
    }

    function isAllowListed(address _userAddress) public view returns (bool) {
        return EnumerableSet.contains(allowListUsers, _userAddress);
    }

    function addToAllowList(address _userAddress) public onlyAdmin {
        EnumerableSet.add(allowListUsers, _userAddress);
        emit AddedToTheList(msg.sender, _userAddress);
    }

    function removeFromAllowList(address _userAddress) public onlyAdmin {
        EnumerableSet.remove(allowListUsers, _userAddress);
        emit RemovedFromTheList(msg.sender, _userAddress);
    }

    function isAcceptableNFT(uint256 _tokenId) public view returns (bool) {
        (
            LegionGeneration generation,
            LegionRarity rarity
        ) = ILegionMetadataStore(legionsMetadataAddress).genAndRarityForLegion(
                _tokenId
            );

        return
            generation == LegionGeneration.GENESIS &&
            rarity == LegionRarity.COMMON;
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFRAG_SYSTEM_ADMIN_ROLE, msg.sender),
            "Qualifier: caller not admin"
        );
        _;
    }
}

