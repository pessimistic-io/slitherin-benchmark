// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Council <council@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.*/

pragma solidity 0.8.19;

// import "../vault/IVault.sol";

/// @title IComptroller Interface
/// @author Enzyme Council <security@enzyme.finance>
interface IComptroller {
    function activate(bool) external;

    function calcGav() external returns (uint256);

    function calcGrossShareValue() external returns (uint256);

    function callOnExtension(address, uint256, bytes calldata) external;

    function destructActivated(uint256, uint256) external;

    function destructUnactivated() external;

    function getDenominationAsset() external view returns (address);

    function getExternalPositionManager() external view returns (address);

    function vaultCallOnContract(
        address,
        bytes4,
        bytes memory
    ) external returns (bytes memory);

    function getFeeManager() external view returns (address);

    function getFundDeployer() external view returns (address);

    function getGasRelayPaymaster() external view returns (address);

    function getIntegrationManager() external view returns (address);

    function getPolicyManager() external view returns (address);

    function getVaultProxy() external view returns (address);

    function getValueInterpreter() external view returns (address);

    function init(address, uint256) external;

    // function permissionedVaultAction(IVault.VaultAction, bytes calldata) external;

    function preTransferSharesHook(address, address, uint256) external;

    function preTransferSharesHookFreelyTransferable(address) external view;

    function setGasRelayPaymaster(address) external;

    function setVaultProxy(address) external;

    function buySharesOnBehalf(
        address,
        uint256,
        uint256
    ) external returns (uint256);

    function redeemSharesOnBehalf(
        address _recipient,
        uint256 _sharesQuantity,
        address[] calldata _payoutAssets,
        uint256[] calldata _payoutAssetPercentages
    ) external returns (uint256[] memory payoutAmounts_);

    function redeemSharesInKindOnBehalf(
        address _recipient,
        uint256 _sharesQuantity,
        address[] calldata _additionalAssets,
        address[] calldata _assetsToSkip
    )
        external
        returns (
            address[] memory payoutAssets_,
            uint256[] memory payoutAmounts_
        );
}

