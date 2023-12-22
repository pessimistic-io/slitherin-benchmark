// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { AccessControlERC2771 } from "./AccessControlERC2771.sol";
import { HedgerInternal } from "./HedgerInternal.sol";

contract HedgerERC2771 is AccessControlERC2771 {
    /* ========== ACCOUNTS ========== */

    function addFreeMarginIsolated(
        address masterAgreement,
        uint256 amount,
        uint256 positionId
    ) external onlyRole(SIGNER_ROLE) {
        HedgerInternal.getMasterAgreementContract(masterAgreement).addFreeMarginIsolated(amount, positionId);
    }

    function addFreeMarginCross(address masterAgreement, uint256 amount) external onlyRole(SIGNER_ROLE) {
        HedgerInternal.getMasterAgreementContract(masterAgreement).addFreeMarginCross(amount);
    }

    function removeFreeMargin(address masterAgreement) external onlyRole(SIGNER_ROLE) {
        HedgerInternal.getMasterAgreementContract(masterAgreement).removeFreeMarginCross();
    }

    /* ========== TRADES ========== */

    function openPosition(
        address masterAgreement,
        uint256 rfqId,
        uint256 filledAmountUnits,
        uint256 avgPriceUsd,
        bytes16 uuid,
        uint256 lockedMarginB
    ) external onlyRole(SIGNER_ROLE) {
        HedgerInternal.getMasterAgreementContract(masterAgreement).openPosition(
            rfqId,
            filledAmountUnits,
            avgPriceUsd,
            uuid,
            lockedMarginB
        );
    }

    function closePosition(
        address masterAgreement,
        uint256 positionId,
        uint256 avgPriceUsd
    ) external onlyRole(SIGNER_ROLE) {
        HedgerInternal.getMasterAgreementContract(masterAgreement).closePosition(positionId, avgPriceUsd);
    }

    function updateUuid(address masterAgreement, uint256 positionId, bytes16 uuid) external onlyRole(SIGNER_ROLE) {
        HedgerInternal.getMasterAgreementContract(masterAgreement).updateUuid(positionId, uuid);
    }
}

