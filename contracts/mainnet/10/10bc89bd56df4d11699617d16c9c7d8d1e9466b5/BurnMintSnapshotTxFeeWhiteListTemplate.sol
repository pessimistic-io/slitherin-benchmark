// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Base.sol";
import "./SnapshotFeature.sol";
import "./ERC20MintFeature.sol";
import "./ERC20BurnFeature.sol";
import "./TxFeeFeatureV3.sol";
import "./PausableWithWhitelistFeature.sol";

contract BurnMintSnapshotTxFeeWhiteListTemplate is
    SnapshotFeature,
    ERC20MintFeature,
    ERC20BurnFeature,
    TxFeeFeatureV3,
    PausableWithWhitelistFeature
{
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 amount_,
        uint256 txFee,
        address txFeeBeneficiary
    ) public initializer {
        __ERC20Base_init(name_, symbol_, decimals_, amount_);
        __ERC20MintFeature_init_unchained();
        __ERC20TxFeeFeature_init_unchained(txFee, txFeeBeneficiary);
        __PausableWithWhitelistFeature_init_unchained();
    }

    function _beforeTokenTransfer_hook(
        address from,
        address to,
        uint256 amount
    )
        internal
        virtual
        override(SnapshotFeature, TxFeeFeatureV3, PausableWithWhitelistFeature)
    {
        SnapshotFeature._beforeTokenTransfer_hook(from, to, amount);
        PausableWithWhitelistFeature._beforeTokenTransfer_hook(
            from,
            to,
            amount
        );
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20SnapshotRewrited, ERC20Upgradeable) {
        _beforeTokenTransfer_hook(from, to, amount);
        super._beforeTokenTransfer(from, to, amount);
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override(TxFeeFeatureV3, ERC20Upgradeable)
        returns (bool)
    {
        return TxFeeFeatureV3.transfer(recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override(TxFeeFeatureV3, ERC20Upgradeable) returns (bool) {
        return TxFeeFeatureV3.transferFrom(sender, recipient, amount);
    }
}
