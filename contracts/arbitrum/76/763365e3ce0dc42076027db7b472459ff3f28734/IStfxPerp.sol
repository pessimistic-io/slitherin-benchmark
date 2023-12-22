//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IStfxStorage} from "./IStfxStorage.sol";

interface IStfxPerp is IStfxStorage {
    event FundDeadlineChanged(uint256 newDeadline, address indexed stfxAddress);
    event ManagerAddressChanged(address indexed newManager, address indexed stfxAddress);
    event ReferralCodeChanged(bytes32 newReferralCode, address indexed stfxAddress);
    event ClaimedUSDC(address indexed investor, uint256 claimAmount, uint256 timeOfClaim, address indexed stfxAddress);
    event VaultLiquidated(uint256 timeOfLiquidation, address indexed stfxAddress);
    event NoFillVaultClosed(uint256 timeOfClose, address indexed stfxAddress);
    event TradeDeadlineChanged(uint256 newTradeDeadline, address indexed stfxAddress);

    function openPosition() external returns (bool);

    function closePosition() external returns (bool);
}

