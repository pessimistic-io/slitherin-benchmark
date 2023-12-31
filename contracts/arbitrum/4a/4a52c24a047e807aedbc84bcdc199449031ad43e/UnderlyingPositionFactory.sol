//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./Clones.sol";
import "./AccessControl.sol";

import "./IUnderlyingPositionFactory.sol";
import {CONTANGO_ROLE} from "./Roles.sol";

contract UnderlyingPositionFactory is IUnderlyingPositionFactory, AccessControl {
    error InvalidMoneyMarket(MoneyMarket mm);

    mapping(MoneyMarket => IMoneyMarket) public moneyMarkets;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function registerMoneyMarket(IMoneyMarket imm) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        moneyMarkets[imm.moneyMarketId()] = imm;
        emit MoneyMarketRegistered(imm.moneyMarketId(), imm);
    }

    function createUnderlyingPosition(PositionId positionId)
        external
        override
        onlyRole(CONTANGO_ROLE)
        returns (IMoneyMarket imm)
    {
        MoneyMarket mm = positionId.getMoneyMarket();
        imm = moneyMarket(mm);

        if (imm.NEEDS_ACCOUNT()) {
            imm = IMoneyMarket(Clones.cloneDeterministic(address(imm), PositionId.unwrap(positionId)));
            emit UnderlyingPositionCreated(address(imm), positionId);
        }
    }

    function moneyMarket(PositionId positionId) external view override returns (IMoneyMarket imm) {
        MoneyMarket mm = positionId.getMoneyMarket();
        imm = moneyMarket(mm);

        if (imm.NEEDS_ACCOUNT()) {
            imm = IMoneyMarket(Clones.predictDeterministicAddress(address(imm), PositionId.unwrap(positionId)));
        }
    }

    function moneyMarket(MoneyMarket mm) public view override returns (IMoneyMarket imm) {
        imm = moneyMarkets[mm];
        if (address(imm) == address(0)) revert InvalidMoneyMarket(mm);
    }
}

