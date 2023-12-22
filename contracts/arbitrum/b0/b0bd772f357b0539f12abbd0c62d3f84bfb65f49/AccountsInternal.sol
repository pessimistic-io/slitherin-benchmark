// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IERC20 } from "./IERC20.sol";
import { MasterStorage, Position, PositionState } from "./MasterStorage.sol";
import { ConstantsInternal } from "./ConstantsInternal.sol";

library AccountsInternal {
    using MasterStorage for MasterStorage.Layout;

    /* ========== VIEWS ========== */

    function getAccountBalance(address party) internal view returns (uint256) {
        return MasterStorage.layout().accountBalances[party];
    }

    function getMarginBalance(address party) internal view returns (uint256) {
        return MasterStorage.layout().marginBalances[party];
    }

    function getLockedMarginIsolated(address party, uint256 positionId) internal view returns (uint256) {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position storage position = s.allPositionsMap[positionId];

        require(position.partyA == party || position.partyB == party, "Invalid party");
        return position.partyA == party ? position.lockedMarginA : position.lockedMarginB;
    }

    function getLockedMarginCross(address party) internal view returns (uint256) {
        return MasterStorage.layout().crossLockedMargin[party];
    }

    function getLockedMarginReserved(address party) internal view returns (uint256) {
        return MasterStorage.layout().crossLockedMarginReserved[party];
    }

    /* ========== WRITES ========== */

    function deposit(address party, uint256 amount) internal {
        MasterStorage.Layout storage s = MasterStorage.layout();

        IERC20 collateral = IERC20(ConstantsInternal.getCollateral());
        require(collateral.balanceOf(party) >= amount, "Insufficient collateral balance");

        bool success = collateral.transferFrom(party, address(this), amount);
        require(success, "Failed to deposit collateral");
        s.accountBalances[party] += amount;
    }

    function withdraw(address party, uint256 amount) internal {
        MasterStorage.Layout storage s = MasterStorage.layout();

        require(s.accountBalances[party] >= amount, "Insufficient account balance");
        s.accountBalances[party] -= amount;
        bool success = IERC20(ConstantsInternal.getCollateral()).transfer(party, amount);
        require(success, "Failed to withdraw collateral");
    }

    function withdrawRevenue(address delegate, uint256 amount) internal {
        MasterStorage.Layout storage s = MasterStorage.layout();

        require(s.accountBalances[address(this)] >= amount, "Insufficient account balance");
        s.accountBalances[address(this)] -= amount;
        bool success = IERC20(ConstantsInternal.getCollateral()).transfer(delegate, amount);
        require(success, "Failed to withdraw collateral");
    }

    function allocate(address party, uint256 amount) internal {
        MasterStorage.Layout storage s = MasterStorage.layout();

        require(s.accountBalances[party] >= amount, "Insufficient account balance");
        s.accountBalances[party] -= amount;
        s.marginBalances[party] += amount;
    }

    function deallocate(address party, uint256 amount) internal {
        MasterStorage.Layout storage s = MasterStorage.layout();

        require(s.marginBalances[party] >= amount, "Insufficient margin balance");
        s.marginBalances[party] -= amount;
        s.accountBalances[party] += amount;
    }

    function addFreeMarginIsolated(address party, uint256 amount, uint256 positionId) internal {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position storage position = s.allPositionsMap[positionId];

        require(s.accountBalances[party] >= amount, "Insufficient account balance");
        s.accountBalances[party] -= amount;

        require(position.partyA == party || position.partyB == party, "Invalid party");
        require(
            position.state != PositionState.CLOSED && position.state != PositionState.LIQUIDATED,
            "Invalid position state"
        );

        if (position.partyA == party) {
            position.lockedMarginA += amount;
        } else {
            position.lockedMarginB += amount;
        }
    }

    function addFreeMarginCross(address party, uint256 amount) internal {
        MasterStorage.Layout storage s = MasterStorage.layout();

        require(s.marginBalances[party] >= amount, "Insufficient margin balance");
        s.marginBalances[party] -= amount;
        s.crossLockedMargin[party] += amount;
    }

    function removeFreeMarginCross(address party) internal returns (uint256 removedAmount) {
        MasterStorage.Layout storage s = MasterStorage.layout();

        require(s.openPositionsCrossLength[party] == 0, "Removal denied");
        require(s.crossLockedMargin[party] > 0, "No locked margin");

        uint256 amount = s.crossLockedMargin[party];
        s.crossLockedMargin[party] = 0;
        s.marginBalances[party] += amount;

        return amount;
    }
}

