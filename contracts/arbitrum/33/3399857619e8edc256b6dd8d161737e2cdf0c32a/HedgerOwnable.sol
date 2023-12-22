// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { OwnableInternal } from "./OwnableInternal.sol";
import { HedgerInternal } from "./HedgerInternal.sol";

contract HedgerOwnable is OwnableInternal {
    /* ========== VIEWS ========== */

    function isMasterAgreement(address masterAgreement) public view returns (bool) {
        return HedgerInternal.isMasterAgreement(masterAgreement);
    }

    function getCollateral(address masterAgreement) public view returns (address) {
        return HedgerInternal.getCollateral(masterAgreement);
    }

    /* ========== SETTERS ========== */

    function addMasterAgreement(address masterAgreement, address collateral) public onlyOwner {
        HedgerInternal.addMasterAgreement(masterAgreement, collateral);
    }

    function updateCollateral(address masterAgreement, address collateral) public onlyOwner {
        HedgerInternal.updateCollateral(masterAgreement, collateral);
    }

    /* ========== WRITES ========== */

    function callMasterAgreementOwner(address targetMasterAgreement, bytes calldata data) external payable onlyOwner {
        HedgerInternal.callExternal(targetMasterAgreement, data);
    }

    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(_owner()).call{ value: balance }("");
        require(success, "Failed to send Ether");
    }

    function deposit(address masterAgreement, uint256 amount) external onlyOwner {
        HedgerInternal.getMasterAgreementContract(masterAgreement).deposit(amount);
    }

    function withdraw(address masterAgreement, uint256 amount) external onlyOwner {
        HedgerInternal.getMasterAgreementContract(masterAgreement).withdraw(amount);
    }

    function allocate(address masterAgreement, uint256 amount) external onlyOwner {
        HedgerInternal.getMasterAgreementContract(masterAgreement).allocate(amount);
    }

    function deallocate(address masterAgreement, uint256 amount) external onlyOwner {
        HedgerInternal.getMasterAgreementContract(masterAgreement).deallocate(amount);
    }

    function depositAndAllocate(address masterAgreement, uint256 amount) external onlyOwner {
        HedgerInternal.getMasterAgreementContract(masterAgreement).depositAndAllocate(amount);
    }

    function deallocateAndWithdraw(address masterAgreement, uint256 amount) external onlyOwner {
        HedgerInternal.getMasterAgreementContract(masterAgreement).deallocateAndWithdraw(amount);
    }
}

