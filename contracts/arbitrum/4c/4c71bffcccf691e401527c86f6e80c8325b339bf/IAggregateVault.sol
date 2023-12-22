// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { ERC20 } from "./ERC20.sol";

interface IAggregateVault {
    function handleWithdraw(ERC20 asset, uint256 _amount, address _account) external;

    function handleDeposit(ERC20 asset, uint256 _amount, address _account) external;

    function getVaultPPS(address _assetVault) external view returns (uint256);

    function previewWithdrawalFee(address token, uint256 _size) external view returns (uint256);

    function previewDepositFee(uint256 _size) external view returns (uint256);

    function rebalanceOpen() external view returns (bool);
}
