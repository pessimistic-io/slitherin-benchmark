//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IStfxStorage} from "./IStfxStorage.sol";

interface IStfxGmx is IStfxStorage {
    event FundDeadlineChanged(uint256 newDeadline, address indexed stfxAddress);
    event ManagerAddressChanged(address indexed newManager, address indexed stfxAddress);
    event ReferralCodeChanged(bytes32 newReferralCode, address indexed stfxAddress);
    event ClaimedUSDC(address indexed investor, uint256 claimAmount, uint256 timeOfClaim, address indexed stfxAddress);
    event VaultLiquidated(uint256 timeOfLiquidation, address indexed stfxAddress);
    event NoFillVaultClosed(uint256 timeOfClose, address indexed stfxAddress);
    event TradeDeadlineChanged(uint256 newTradeDeadline, address indexed stfxAddress);

    function getStf() external view returns (Stf memory);

    function openPosition(bool _isLimit, uint256 _triggerPrice, uint256 _totalRaised) external payable;

    function closePosition(bool _isLimit, uint256 _size, uint256 _triggerPrice, bool _triggerAboveThreshold)
        external
        payable
        returns (bool);

    function distributeProfits() external returns (uint256, uint256, uint256);

    function cancelOrder(uint256 _orderIndex, bool _isOpen) external returns (uint256);

    function withdraw(address receiver, bool isEth, address token, uint256 amount) external;
}

