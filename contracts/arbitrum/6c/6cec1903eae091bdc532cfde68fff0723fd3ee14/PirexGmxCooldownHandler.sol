// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IRewardRouterV2} from "./IRewardRouterV2.sol";
import {IStakedGlp} from "./IStakedGlp.sol";
import {IPirexGmx} from "./IPirexGmx.sol";

contract PirexGmxCooldownHandler {
    using SafeTransferLib for ERC20;

    IPirexGmx public immutable pirexGmx;

    error MustBePirexGmx();

    constructor() {
        pirexGmx = IPirexGmx(msg.sender);
    }

    /**
        @notice Mint + stake GLP and deposit them into PirexGmx on behalf of a user
        @param  rewardRouter   IRewardRouterV2  GLP Reward Router interface instance
        @param  stakedGlp      IStakedGlp       StakedGlp interface instance
        @param  glpManager     address          GlpManager contract address
        @param  token          address          GMX-whitelisted token for minting GLP
        @param  tokenAmount    uint256          Whitelisted token amount
        @param  minUsdg        uint256          Minimum USDG purchased and used to mint GLP
        @param  minGlp         uint256          Minimum GLP amount minted from ERC20 tokens
        @param  receiver       address          pxGLP receiver
        @return deposited      uint256          GLP deposited
        @return postFeeAmount  uint256          pxGLP minted for the receiver
        @return feeAmount      uint256          pxGLP distributed as fees
     */
    function depositGlp(
        IRewardRouterV2 rewardRouter,
        IStakedGlp stakedGlp,
        address glpManager,
        address token,
        uint256 tokenAmount,
        uint256 minUsdg,
        uint256 minGlp,
        address receiver
    )
        external
        payable
        returns (
            uint256 deposited,
            uint256 postFeeAmount,
            uint256 feeAmount
        )
    {
        if (msg.sender != address(pirexGmx)) revert MustBePirexGmx();

        ERC20(token).safeApprove(glpManager, tokenAmount);

        deposited = token == address(0)
            ? rewardRouter.mintAndStakeGlpETH{value: msg.value}(minUsdg, minGlp)
            : rewardRouter.mintAndStakeGlp(token, tokenAmount, minUsdg, minGlp);

        // Handling stakedGLP approvals for each call in case its updated on PirexGmx
        stakedGlp.approve(address(pirexGmx), deposited);

        (postFeeAmount, feeAmount) = pirexGmx.depositFsGlp(deposited, receiver);
    }
}

