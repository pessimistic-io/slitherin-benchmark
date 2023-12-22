// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

interface IGlpRebalanceRouter {

    function netGlpRebalance(uint256[5] memory lastAllocations, uint256[5] memory nextAllocations) external view returns (int256[5] memory glpVaultDeltaExecute, int[5] memory glpVaultDeltaAccount);

}

