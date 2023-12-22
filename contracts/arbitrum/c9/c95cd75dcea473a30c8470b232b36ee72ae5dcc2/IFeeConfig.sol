// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IFeeConfig {
    struct FeeCategory {
        uint256 total;
        uint256 co;
        uint256 call;
        uint256 strategist;
        string label;
        bool active;
    }
    function getFees(address strategy) external view returns (FeeCategory memory);
    function stratFeeId(address strategy) external view returns (uint256);
    function setStratFeeId(uint256 feeId) external;
}
