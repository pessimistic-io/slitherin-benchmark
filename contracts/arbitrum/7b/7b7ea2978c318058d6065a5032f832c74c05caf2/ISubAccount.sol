// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

interface ISubAccount {
    function transferMargin(address, address, uint256) external;
    function transferOriginationFee(address, uint256) external;
    function counterPartyRegistry() external view returns (address);
    function feeCollector() external view returns (address);
    function operator() external view returns (address);
    function subAccountState() external view returns (uint8);
}
