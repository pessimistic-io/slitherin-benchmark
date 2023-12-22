// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ITradeAccess.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract TradeAccess is ITradeAccess, Initializable, UUPSUpgradeable, OwnableUpgradeable {

    uint8 public constant USER_STATE_UNKNOWN = 0;
    uint8 public constant USER_STATE_ADMIN = 1;
    uint8 public constant USER_STATE_BANNED = 2;

    mapping(address => uint8) private accessList;

    modifier onlyAdmin() {
        require(msg.sender == owner() || userState(msg.sender) == USER_STATE_ADMIN, "AL/Forbidden");
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function userState(address user) public view override returns(uint8) {
        return accessList[user];
    }

    function setGlobalAdmin(address user) external override onlyAdmin {
        accessList[user] = USER_STATE_ADMIN;
    }

    function removeGlobalAdmin(address user) external override onlyAdmin {
        accessList[user] = USER_STATE_UNKNOWN;
    }

    function banUser(address user) external override onlyAdmin {
        accessList[user] = USER_STATE_BANNED;
    }
}

