// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OutletManagement.sol";
import "./ISurfVoucher.sol";

contract OutletManagementHelper {
    OutletManagement public outletManagement;

    constructor(OutletManagement _outletManagement) {
        outletManagement = _outletManagement;
    }

    function allOutletIds() external view returns (uint256[] memory) {
        return outletManagement.allOutletIds();
    }

    function outletIdsOf(address account) external view returns (uint256[] memory) {
        return outletManagement.outletIdsOf(account);
    }

    function getOutletData(uint256 outletId) external view returns (OutletManagement.OutletData memory) {
        return outletManagement.getOutletData(outletId);
    }

    function outletURI(uint256 outletId) external view returns (string memory) {
        return outletManagement.outletURI(outletId);
    }

    function isOwner(address account) external view returns (bool) {
        return outletManagement.owner() == account;
    }

    function isManager(address account) external view returns (bool) {
        return outletManagement.outletIdsOf(account).length > 0;
    }

    function batchGetOutletData(uint256[] memory outletIds) external view returns (OutletManagement.OutletData[] memory) {
        OutletManagement.OutletData[] memory result = new OutletManagement.OutletData[] (outletIds.length);
        for (uint i = 0; i < outletIds.length; i++) {
            result[i] = outletManagement.getOutletData(outletIds[i]);
        }

        return result;
    }

    function batchGetOutletURI(uint256[] memory outletIds) external view returns (string[] memory) {
        string[] memory result = new string[] (outletIds.length);

        for (uint i = 0; i < outletIds.length; i++) {
            result[i] = outletManagement.outletURI(outletIds[i]);
        }

        return result;
    }

    function summary() external view returns (uint256[] memory) {
        uint256[] memory outletIds = outletManagement.allOutletIds();

        uint256 totalCreditQuota; 
        uint256 totalCirculation; 
        for (uint i = 0; i < outletIds.length; i++) {
            OutletManagement.OutletData memory outletData = outletManagement.getOutletData(outletIds[i]);
            totalCreditQuota = totalCreditQuota + outletData.creditQuota;
            totalCirculation = totalCirculation + outletData.circulation;
        }

        uint256[] memory result = new uint256[] (3);
        result[0] = totalCreditQuota;
        result[1] = totalCirculation;

        ISurfVoucher surfVoucher = outletManagement.surfVoucher();
        result[2] = surfVoucher.tokensInSlot(outletManagement.slotId());

        return result;
    }

    function getTokenIds(address account) external view returns (uint256[] memory) {
        ISurfVoucher surfVoucher = outletManagement.surfVoucher();
        uint256 balance = surfVoucher.balanceOf(account);

        uint256[] memory result = new uint256[] (balance);
        for (uint256 i = 0; i < balance; i++) {
            result[i] = surfVoucher.tokenOfOwnerByIndex(account, i);
        }

        return result;
    }

    function batchGetTokenURI(uint256[] memory tokenIds) external view returns (string[] memory) {
        ISurfVoucher surfVoucher = outletManagement.surfVoucher();

        string[] memory result = new string[] (tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            result[i] = surfVoucher.tokenURI(tokenIds[i]);
        }

        return result;
    }
}

