// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesVaultV3} from "./JonesVaultV3.sol";

contract JonesERC20VaultV3 is JonesVaultV3 {
    constructor(
        address _asset,
        address _share,
        address _governor,
        address _feeDistributor,
        uint256 _vaultCap
    ) JonesVaultV3(_asset, _share, _governor, _feeDistributor, _vaultCap) {}

    /**
     * @inheritdoc JonesVaultV3
     */
    function _afterCloseManagementWindow() internal virtual override {}

    /**
     * @inheritdoc JonesVaultV3
     */
    function _afterOpenManagementWindow() internal virtual override {}

    /**
     * @inheritdoc JonesVaultV3
     */
    function _afterDeposit(uint256 assets, uint256 shares)
        internal
        virtual
        override
    {}

    /**
     * @inheritdoc JonesVaultV3
     */
    function _beforeWithdraw(uint256 assets, uint256 shares)
        internal
        virtual
        override
    {}
}

