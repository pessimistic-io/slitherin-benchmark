// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity >=0.7.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "./BalancerErrors.sol";
import "./OwnableUpgradeable.sol";

import "./IAuthorizedManagers.sol";
import "./KacyErrors.sol";

contract AuthorizedManagers is IAuthorizedManagers, OwnableUpgradeable {
    mapping(address => bool) private _factories;
    mapping(address => uint8) private _manager;

    event ManagerAllowanceUpdated(address indexed manager, uint256 poolsAmount);

    function initialize() public initializer {
        __Ownable_init();
    }

    function setFactory(address factory) external onlyOwner {
        _require(!_factories[factory], Errors.ADDRESS_ALREADY_ALLOWLISTED);
        _factories[factory] = true;
    }

    function removeFactory(address factory) external onlyOwner {
        _require(_factories[factory], Errors.ADDRESS_NOT_ALLOWLISTED);
        _factories[factory] = false;
    }

    function getAllowedPoolsToCreate(address manager) external view returns (uint8) {
        return _manager[manager];
    }

    function canCreatePool(address manager) external view override returns (bool) {
        return _manager[manager] > 0;
    }

    function setManager(address manager, uint8 qtdApproved) external onlyOwner {
        require(manager != address(0), KacyErrors.ZERO_ADDRESS);
        _manager[manager] = qtdApproved;
        emit ManagerAllowanceUpdated(manager, qtdApproved);
    }

    function managerCreatedPool(address manager) external override {
        _require(_factories[msg.sender] && _manager[manager] > 0, Errors.SENDER_NOT_ALLOWED);
        _manager[manager]--;
    }
}

