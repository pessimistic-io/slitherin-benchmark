// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { AccessControlERC2771 } from "./AccessControlERC2771.sol";
import { HedgerInternal } from "./HedgerInternal.sol";

contract HedgerERC2771 is AccessControlERC2771 {
    function callMasterAgreementSigner(
        address targetMasterAgreement,
        bytes calldata data
    ) external payable onlyRole(SIGNER_ROLE) {
        HedgerInternal.callExternal(targetMasterAgreement, data);
    }

    function openPosition(
        address masterAgreement,
        uint256 rfqId,
        uint256 filledAmountUnits,
        uint256 avgPriceUsd,
        bytes16 uuid
    ) external onlyRole(SIGNER_ROLE) {
        HedgerInternal.getMasterAgreementContract(masterAgreement).openPosition(
            rfqId,
            filledAmountUnits,
            avgPriceUsd,
            uuid
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

