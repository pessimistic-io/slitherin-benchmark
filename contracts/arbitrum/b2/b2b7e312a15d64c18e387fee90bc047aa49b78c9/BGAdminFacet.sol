// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DiamondOwnable } from "./DiamondOwnable.sol";
import { DiamondAccessControl } from "./DiamondAccessControl.sol";

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

contract BGAdminFacet is WithModifiers, DiamondAccessControl {
    event PauseStateChanged(bool paused);

    /**
     * @dev Pause the contract
     */
    function pause() external onlyGuardian notPaused {
        gs().paused = true;
        emit PauseStateChanged(true);
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyGuardian {
        if (!gs().paused) revert Errors.GameAlreadyUnPaused();
        gs().paused = false;
        emit PauseStateChanged(false);
    }

    /**
     * @dev Return the paused state
     */
    function isPaused() external view returns (bool) {
        return gs().paused;
    }

    /**
     * @dev Set the Magic address
     */
    function setMagic(address magic) external onlyOwner {
        if (magic == address(0)) revert Errors.InvalidAddress();
        gs().magic = magic;
    }

    /**
     * @dev Set the MagicSwap router address
     */
    function setMagicSwapRouter(address magicSwapRouter) external onlyOwner {
        if (magicSwapRouter == address(0)) revert Errors.InvalidAddress();
        gs().magicSwapRouter = magicSwapRouter;
    }

    /**
     * @dev Set the Magic/gFLY LP address
     */
    function setMagicGFlyLp(address magicGFlyLp) external onlyOwner {
        if (magicGFlyLp == address(0)) revert Errors.InvalidAddress();
        gs().magicGFlyLp = magicGFlyLp;
    }

    /**
     * @dev Set the Battlefly address
     */
    function setBattlefly(address battlefly) external onlyOwner {
        if (battlefly == address(0)) revert Errors.InvalidAddress();
        gs().battlefly = battlefly;
    }

    /**
     * @dev Set the Soulbound address
     */
    function setSoulbound(address soulbound) external onlyOwner {
        if (soulbound == address(0)) revert Errors.InvalidAddress();
        gs().soulbound = soulbound;
    }

    /**
     * @dev Set the GameV2 address
     */
    function setGameV2(address gameV2) external onlyOwner {
        if (gameV2 == address(0)) revert Errors.InvalidAddress();
        gs().gameV2 = gameV2;
    }

    /**
    * @dev Set the Payment Receiver address
     */
    function setPaymentReceiver(address paymentReceiver) external onlyOwner {
        if (paymentReceiver == address(0)) revert Errors.InvalidAddress();
        gs().paymentReceiver = paymentReceiver;
    }

    /**
    * @dev Set the USDC address
     */
    function setUSDC(address usdc) external onlyOwner {
        if (usdc == address(0)) revert Errors.InvalidAddress();
        gs().usdc = usdc;
    }

}

