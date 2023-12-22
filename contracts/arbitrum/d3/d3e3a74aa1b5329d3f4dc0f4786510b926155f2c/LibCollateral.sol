// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {LibCollateralStorage} from "./LibCollateralStorage.sol";
import {LibFundStorage} from "./LibFundStorage.sol";

library LibCollateral {
    event OnCollateralStateChanged(
        uint indexed termId,
        LibCollateralStorage.CollateralStates indexed oldState,
        LibCollateralStorage.CollateralStates indexed newState
    );
    event OnReimbursementWithdrawn(uint indexed termId, address indexed user, uint indexed amount);

    /// @param _termId term id
    /// @param _newState collateral state
    function _setState(uint _termId, LibCollateralStorage.CollateralStates _newState) internal {
        LibCollateralStorage.Collateral storage collateral = LibCollateralStorage
            ._collateralStorage()
            .collaterals[_termId];
        LibCollateralStorage.CollateralStates oldState = collateral.state;
        collateral.state = _newState;
        emit OnCollateralStateChanged(_termId, oldState, _newState);
    }

    /// @param _termId term id
    /// @param _depositor Address of the depositor
    function _withdrawReimbursement(uint _termId, address _depositor) internal {
        require(LibFundStorage._fundExists(_termId), "Fund does not exists");
        LibCollateralStorage.Collateral storage collateral = LibCollateralStorage
            ._collateralStorage()
            .collaterals[_termId];

        uint amount = collateral.collateralPaymentBank[_depositor];
        require(amount > 0, "Nothing to claim");
        collateral.collateralPaymentBank[_depositor] = 0;

        (bool success, ) = payable(_depositor).call{value: amount}("");
        require(success);

        emit OnReimbursementWithdrawn(_termId, _depositor, amount);
    }
}

