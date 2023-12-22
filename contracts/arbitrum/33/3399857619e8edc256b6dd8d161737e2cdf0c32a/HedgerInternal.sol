// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { IERC20, SafeERC20 } from "./SafeERC20.sol";

import { HedgerStorage } from "./HedgerStorage.sol";
import { IMasterAgreement } from "./IMasterAgreement.sol";
import { Errors } from "./errors.sol";

library HedgerInternal {
    using HedgerStorage for HedgerStorage.Layout;
    using SafeERC20 for IERC20;

    /* ========== VIEWS ========== */

    function isMasterAgreement(address masterAgreement) internal view returns (bool) {
        return HedgerStorage.layout().masterAgreementMap[masterAgreement];
    }

    function getCollateral(address masterAgreement) internal view returns (address) {
        return HedgerStorage.layout().collateralMap[masterAgreement];
    }

    function getMasterAgreementContract(address masterAgreement) internal pure returns (IMasterAgreement) {
        return IMasterAgreement(masterAgreement);
    }

    /* ========== SETTERS ========== */

    function addMasterAgreement(address masterAgreement, address collateral) internal {
        bool exists = isMasterAgreement(masterAgreement);
        require(!exists, "MasterAgreement already exists");

        // Add MasterAgreement
        HedgerStorage.layout().masterAgreementMap[masterAgreement] = true;

        // Set the Collateral for this MasterAgreement
        HedgerStorage.layout().collateralMap[masterAgreement] = collateral;

        // Approve the Collateral
        _approve(collateral, masterAgreement);

        // Enlist ourselves in the MasterAgreement;
        _enlist(masterAgreement);
    }

    function updateCollateral(address masterAgreement, address collateral) internal {
        bool exists = isMasterAgreement(masterAgreement);
        require(exists, "MasterAgreement does not exist");

        // Set the Collateral for this MasterAgreement
        HedgerStorage.layout().collateralMap[masterAgreement] = collateral;

        // Approve the Collateral
        _approve(collateral, masterAgreement);
    }

    /* ========== PUBLIC WRITES ========== */

    function callExternal(address target, bytes calldata data) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory res) = target.call{ value: msg.value }(data);
        if (!success) {
            revert(Errors.getRevertMsg(res));
        }
    }

    /* ========== PRIVATE WRITES ========== */

    function _approve(address target, address spender) private {
        IERC20(target).safeApprove(spender, type(uint256).max);
    }

    function _enlist(address masterAgreement) private {
        string[] memory url1 = new string[](1);
        string[] memory url2 = new string[](1);
        url1[0] = "wss://hedger.com";
        url2[0] = "https://hedger.com";

        getMasterAgreementContract(masterAgreement).enlist(url1, url2);
    }
}

