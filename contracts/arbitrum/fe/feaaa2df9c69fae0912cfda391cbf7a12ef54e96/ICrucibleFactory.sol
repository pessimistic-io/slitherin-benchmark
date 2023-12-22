// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

interface ICrucibleFactory {
    function getCrucible(
        address baseToken,
        uint64 feeOnTransferX10000,
        uint64 feeOnWithdrawX10000
    ) external view returns (address);

    function router() external view returns (address);
}

