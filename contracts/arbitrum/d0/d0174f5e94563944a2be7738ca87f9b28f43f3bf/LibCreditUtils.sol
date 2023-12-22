// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

// Storage imports
import { LibStorage, BattleflyGameStorage } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

//interfaces
import { IERC20 } from "./IERC20.sol";
import { IERC1155 } from "./IERC1155.sol";

library LibCreditUtils {
    function gs() internal pure returns (BattleflyGameStorage storage) {
        return LibStorage.gameStorage();
    }

    function createCredit(
        uint256 creditType,
        uint256 amount,
        bool redeemGFly,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts
    ) internal {
        if (amount < 1) revert Errors.InvalidAmount();
        if (!gs().creditTypes[creditType]) revert Errors.UnsupportedCreditType();
        LibCreditUtils.transferCreditFunds(amount, redeemGFly, treasureIds, treasureAmounts);
    }

    function upgradeInventorySlot(
        uint256 amount,
        bool redeemGFly,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts
    ) internal {
        if (amount < 1) revert Errors.InvalidAmount();
        LibCreditUtils.transferCreditFunds(amount, redeemGFly, treasureIds, treasureAmounts);
    }

    function transferCreditFunds(uint256 amount,
        bool redeemGFly,
        uint256[] memory treasureIds,
        uint256[] memory treasureAmounts) internal {
        if (redeemGFly) {
            //In case of upgrade with gFLY
            uint256 requiredGFly = amount * gs().gFlyPerCredit;
            IERC20(gs().gFLY).transferFrom(msg.sender, gs().gFlyReceiver, requiredGFly);
        } else {
            //In case of upgrade with Treasures
            if (treasureIds.length != treasureAmounts.length) revert Errors.InvalidArrayLength();
            uint256 requiredTreasures = amount * gs().treasuresPerCredit;
            uint256 receivedTreasures;
            for (uint256 i = 0; i < treasureAmounts.length; i++) {
                receivedTreasures += treasureAmounts[i];
            }
            if (requiredTreasures != receivedTreasures) revert Errors.IncorrectTreasuresAmount();
            IERC1155(gs().treasures).safeBatchTransferFrom(
                msg.sender,
                gs().treasureReceiver,
                treasureIds,
                treasureAmounts,
                "0x0"
            );
        }
    }
}

