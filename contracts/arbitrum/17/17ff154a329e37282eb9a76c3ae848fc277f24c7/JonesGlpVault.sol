// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 Jones DAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

pragma solidity ^0.8.10;

import {JonesBaseGlpVault} from "./JonesBaseGlpVault.sol";
import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {IAggregatorV3} from "./IAggregatorV3.sol";
import {IStakedGlp} from "./IStakedGlp.sol";
import {IJonesGlpLeverageStrategy} from "./IJonesGlpLeverageStrategy.sol";

contract JonesGlpVault is JonesBaseGlpVault {
    uint256 private freezedAssets;

    constructor()
        JonesBaseGlpVault(
            IAggregatorV3(0xDFE51CC551949704E5C52C7BB98DCC3fd934E7fa),
            IERC20Metadata(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf),
            "GLP Vault Receipt Token",
            "GVRT"
        )
    {}
    // ============================= Public functions ================================ //

    function deposit(uint256 _assets, address _receiver)
        public
        override(JonesBaseGlpVault)
        whenNotPaused
        returns (uint256)
    {
        _validate();
        return super.deposit(_assets, _receiver);
    }

    /**
     * @dev See {openzeppelin-IERC4626-_burn}.
     */
    function burn(address _user, uint256 _amount) public onlyOperator {
        _validate();
        _burn(_user, _amount);
    }

    /**
     * @notice Return total asset deposited
     * @return Amount of asset deposited
     */
    function totalAssets() public view override returns (uint256) {
        if (freezedAssets != 0) {
            return freezedAssets;
        }

        return super.totalAssets() + strategy.getUnderlyingGlp();
    }

    // ============================= Private functions ================================ //

    function _validate() private {
        IERC20 asset = IERC20(asset());
        uint256 balance = asset.balanceOf(address(this));

        if (balance > 0) {
            asset.transfer(receiver, balance);
        }
    }
}

