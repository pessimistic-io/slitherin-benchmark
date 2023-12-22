// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IFiat24Account.sol";
import "./IF24.sol";
import "./EnumerableUintToUintMap.sol";

contract Fiat24Buildings is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using EnumerableUintToUintMap for EnumerableUintToUintMap.UintToUintMap;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct PriceListItem {
        uint256 price;
        bool available;
    }

    EnumerableUintToUintMap.UintToUintMap private buildings;
    mapping (uint256=>PriceListItem) public buildingPriceList;

    IFiat24Account public fiat24Account;
    IF24 public f24;

    error Fiat24Buildings__Suspended();
    error Fiat24Buildings__NoToken();
    error Fiat24Buildings__BuldingNotAvailable();
    error Fiat24Buildings__BuildingForTokenExists();
    error Fiat24Buildings__NotSufficientF24();
    error Fiat24Buildings__NotOperator();

    function initialize(address fiat24AccountAddress_, address f24Address_) public initializer {
        __AccessControl_init_unchained();
        _setupRole(OPERATOR_ROLE, msg.sender);
        fiat24Account = IFiat24Account(fiat24AccountAddress_);
        f24 = IF24(f24Address_);
    }

    function build(uint256 buildingType_) external {
        if(paused()) {
            revert Fiat24Buildings__Suspended();
        }
        uint256 tokenId = getTokenId(msg.sender);
        if(tokenId == 0) {
            revert Fiat24Buildings__NoToken();
        }
        if(!buildingPriceList[buildingType_].available) {
            revert Fiat24Buildings__BuldingNotAvailable();
        }
        if(f24.balanceOf(msg.sender) < buildingPriceList[buildingType_].price) {
            revert Fiat24Buildings__NotSufficientF24();
        }
        if(getBuilding(tokenId) == buildingType_) {
            revert Fiat24Buildings__BuildingForTokenExists();
        }
        if(buildingPriceList[buildingType_].price > 0) {
            f24.burnFrom(msg.sender, buildingPriceList[buildingType_].price);
        }
        buildings.set(tokenId, buildingType_);
    }

    function destroy() external {
        uint256 tokenId = getTokenId(msg.sender);
        if(tokenId == 0) {
            revert Fiat24Buildings__NoToken();
        }
        buildings.remove(tokenId);
    }

    function getBuilding(uint256 tokenId_) public view returns(uint256) {
        if(buildings.contains(tokenId_)) {
            return buildings.get(tokenId_);    
        } else {
            return 0;
        }
    }

    function getBuildingByIndex(uint256 index_) external view returns(uint256, uint256) {
        return buildings.at(index_);
    }

    function getAllTokens() external view returns(EnumerableUintToUintMap.MapEntry[] memory) {
        return buildings.getAll();
    }

    function addBuilding(uint256 buildingType_, uint256 buildingPrice_) external {
        if(!(hasRole(OPERATOR_ROLE, msg.sender))) {
            revert Fiat24Buildings__NotOperator();
        }
        buildingPriceList[buildingType_].price = buildingPrice_;
        buildingPriceList[buildingType_].available = true;
    }

    function removeBuilding(uint256 buildingType_) external {
        if(!(hasRole(OPERATOR_ROLE, msg.sender))) {
            revert Fiat24Buildings__NotOperator();
        }
        delete buildingPriceList[buildingType_];
    }

    function pause() external {
        if(!(hasRole(OPERATOR_ROLE, msg.sender))) {
            revert Fiat24Buildings__NotOperator();
        }    
        _pause();
    }

    function unpause() external {
        if(!(hasRole(OPERATOR_ROLE, msg.sender))) {
            revert Fiat24Buildings__NotOperator();
        }    
        _unpause();
    }

    function getTokenId(address sender_) internal view returns(uint256 tokenId_) {
        try fiat24Account.tokenOfOwnerByIndex(sender_, 0) returns(uint256 tokenId) {
            return tokenId;
        } catch Error(string memory) {
            return fiat24Account.historicOwnership(sender_);
        } catch (bytes memory) {
            return fiat24Account.historicOwnership(sender_);
        }
    }
}
