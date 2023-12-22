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

    /**
     * @dev Set the USDC Original address
     */
    function setUSDCOriginal(address usdcOriginal) external onlyOwner {
        if (usdcOriginal == address(0)) revert Errors.InvalidAddress();
        gs().usdcOriginal = usdcOriginal;
    }

    /**
    * @dev Set the ARB address
     */
    function setArb(address arb) external onlyOwner {
        if (arb == address(0)) revert Errors.InvalidAddress();
        gs().arb = arb;
    }

    /**
     * @dev Set the WETH address
     */
    function setWETH(address weth) external onlyOwner {
        if (weth == address(0)) revert Errors.InvalidAddress();
        gs().weth = weth;
    }

    /**
     * @dev Set the USDCDataFeedAddress address
     */
    function setUSDCDataFeedAddress(address usdcDataFeedAddress) external onlyOwner {
        if (usdcDataFeedAddress == address(0)) revert Errors.InvalidAddress();
        gs().usdcDataFeedAddress = usdcDataFeedAddress;
    }

    /**
     * @dev Set the ETHDataFeedAddress address
     */
    function setETHDataFeedAddress(address ethDataFeedAddress) external onlyOwner {
        if (ethDataFeedAddress == address(0)) revert Errors.InvalidAddress();
        gs().ethDataFeedAddress = ethDataFeedAddress;
    }

    /**
     * @dev Set the MagicDataFeedAddress address
     */
    function setMagicDataFeedAddress(address magicDataFeedAddress) external onlyOwner {
        if (magicDataFeedAddress == address(0)) revert Errors.InvalidAddress();
        gs().magicDataFeedAddress = magicDataFeedAddress;
    }

    /**
     * @dev Set the ArbDataFeedAddress address
     */
    function setArbDataFeedAddress(address arbDataFeedAddress) external onlyOwner {
        if (arbDataFeedAddress == address(0)) revert Errors.InvalidAddress();
        gs().arbDataFeedAddress = arbDataFeedAddress;
    }

    /**
     * @dev Set the SushiswapRouter address
     */
    function setSushiswapRouter(address sushiswapRouter) external onlyOwner {
        if (sushiswapRouter == address(0)) revert Errors.InvalidAddress();
        gs().sushiswapRouter = sushiswapRouter;
    }

    /**
     * @dev Set the UniswapV3Router address
     */
    function setUniswapV3Router(address uniswapV3Router) external onlyOwner {
        if (uniswapV3Router == address(0)) revert Errors.InvalidAddress();
        gs().uniswapV3Router = uniswapV3Router;
    }

    /**
     * @dev Set the UniswapV3Quoter address
     */
    function setUniswapV3Quoter(address uniswapV3Quoter) external onlyOwner {
        if (uniswapV3Quoter == address(0)) revert Errors.InvalidAddress();
        gs().uniswapV3Quoter = uniswapV3Quoter;
    }

    /**
     * @dev Set usdcToUsdcOriginalPoolFee
     */
    function setUsdcToUsdcOriginalPoolFee(uint24 usdcToUsdcOriginalPoolFee) external onlyOwner {
        gs().usdcToUsdcOriginalPoolFee = usdcToUsdcOriginalPoolFee;
    }

    /**
     * @dev Set the SequencerUptimeFeedAddress address
     */
    function setSequencerUptimeFeedAddress(address sequencerUptimeFeedAddress) external onlyOwner {
        if (sequencerUptimeFeedAddress == address(0)) revert Errors.InvalidAddress();
        gs().sequencerUptimeFeedAddress = sequencerUptimeFeedAddress;
    }

    /**
     * @dev Set the Sequencer Grace Period
     */
    function setSequencerGracePeriod(uint256 sequencerGracePeriod) external onlyOwner {
        gs().sequencerGracePeriod = sequencerGracePeriod;
    }
}

