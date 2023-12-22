// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./DataType.sol";
import "./TradePerpLogic.sol";

interface IController {
    function tradePerp(uint256 _vaultId, uint64 _pairId, TradePerpLogic.TradeParams memory _tradeParams)
        external
        returns (DataType.TradeResult memory);

    function updateMargin(uint64 _pairGroupId, int256 _marginAmount) external returns (uint256 vaultId);

    function updateMarginOfIsolated(
        uint64 _pairGroupId,
        uint256 _isolatedVaultId,
        int256 _marginAmount,
        bool _moveFromMainVault
    ) external returns (uint256 isolatedVaultId);

    function setAutoTransfer(uint256 _isolatedVaultId, bool _autoTransferDisabled) external;

    function getSqrtPrice(uint256 _pairId) external view returns (uint160);

    function getSqrtIndexPrice(uint256 _pairId) external view returns (uint160);

    function getVault(uint256 _id) external view returns (DataType.Vault memory);

    function getPairGroup(uint256 _id) external view returns (DataType.PairGroup memory);

    function getAsset(uint256 _id) external view returns (DataType.PairStatus memory);

    function getVaultStatus(uint256 _id) external returns (DataType.VaultStatusResult memory);
}

