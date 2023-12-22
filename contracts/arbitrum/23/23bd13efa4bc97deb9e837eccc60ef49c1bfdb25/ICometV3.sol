// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

    struct TotalsBasic {
        uint64 baseSupplyIndex;
        uint64 baseBorrowIndex;
        uint64 trackingSupplyIndex;
        uint64 trackingBorrowIndex;
        uint104 totalSupplyBase;
        uint104 totalBorrowBase;
        uint40 lastAccrualTime;
        uint8 pauseFlags;
    }

interface ICometV3 {
    function supply(address asset, uint256 amount) external;

    function withdraw(address suppliedToken, uint256 amount) external;

    function totalBorrow() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address user) external view returns (uint256);

    function getUtilization() external view returns (uint256);

    function getSupplyRate(uint256 utilization) external view returns (uint256);

    function totalsBasic() external view returns (TotalsBasic memory);
}



