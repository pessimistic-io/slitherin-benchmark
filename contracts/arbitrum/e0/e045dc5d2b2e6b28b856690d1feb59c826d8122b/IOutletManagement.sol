// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// helper interface
interface IOutletManagement {
    // Outlet Data
    struct OutletData {
        // outlet name
        string name;
        // the manager account
        address manager;
        // active flag
        bool isActive;
        // credit quota
        uint256 creditQuota;
        // curculation units
        uint256 circulation;
    }

    function allOutletIds() external view returns (uint256[] memory);

    function outletIdsOf(address account) external view returns (uint256[] memory);

    function getOutletData(uint256 outletId) external view returns (OutletData memory);

    function outletURI(uint256 outletId) external view returns (string memory);
}
