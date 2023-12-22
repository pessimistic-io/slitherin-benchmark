// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {IERC721EnumerableUpgradeable} from "./IERC721EnumerableUpgradeable.sol";

import {ITreasureChest} from "./ITreasureChest.sol";

contract TreasureChestShop is OwnableUpgradeable, PausableUpgradeable {
    IERC20Upgradeable public crds;
    IERC721EnumerableUpgradeable public cradlesCrystalPass;
    ITreasureChest public treasureChest;

    event BuyTreasureChest(address buyer, uint cradlesCrystalPassTokenId);

    function __TreasureChestShop_init(
        IERC20Upgradeable crds_,
        IERC721EnumerableUpgradeable cradlesCrystalPass_,
        ITreasureChest treasureChest_
    ) external initializer {
        __Ownable_init_unchained();
        _pause();

        crds = crds_;
        cradlesCrystalPass = cradlesCrystalPass_;
        treasureChest = treasureChest_;
    }

    function buyTreasureChest() external whenNotPaused {
        address sender = msg.sender;
        // 100 crds + 1 cradlesCrystalPass
        uint cradlesCrystalPassTokenId = cradlesCrystalPass.tokenOfOwnerByIndex(sender, 0);
        cradlesCrystalPass.transferFrom(
            sender,
            address(this),
            cradlesCrystalPassTokenId
        );
        crds.transferFrom(sender, address(this), 100e18);
        treasureChest.mint(sender);
        emit BuyTreasureChest(sender, cradlesCrystalPassTokenId);
    }

    function emergencyWithdraw() external onlyOwner {
        crds.transfer(owner(), crds.balanceOf(address(this)));
    }

    function flipPause() external onlyOwner {
        paused() ? _unpause() : _pause();
    }

    uint[47] private __gap;
}

