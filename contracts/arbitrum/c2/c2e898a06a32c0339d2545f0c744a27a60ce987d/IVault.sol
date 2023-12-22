// SPDX-License-Identifier: UNLICENSED
// Author: @stevieraykatz
// https://github.com/coinlander/Coinlander

pragma solidity ^0.8.10;

// @TODO investigate EIP-712 for external method calls 

interface IVault {

    event VaultUnlocked(address winner);
    event RandomnessOracleChanged(address currentOracle, address newOracle);
    event RandomnessRequested(address requester, uint16 requestId);
    event RandomnessFulfilled(uint16 requestId, uint16 result);
    function requestFragments(address _requester, uint256 amount) external;
    function setSweetRelease() external;
    function claimKeepersVault() external;
    function fundPrizePurse() payable external;
    function getClaimablesByAddress(address user) view external returns(uint256);
}
