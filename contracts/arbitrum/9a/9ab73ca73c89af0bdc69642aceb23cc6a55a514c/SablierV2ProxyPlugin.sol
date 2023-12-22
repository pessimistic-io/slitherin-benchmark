// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IPRBProxy } from "./IPRBProxy.sol";
import { IPRBProxyPlugin } from "./IPRBProxyPlugin.sol";
import { ISablierV2Lockup } from "./ISablierV2Lockup.sol";
import { ISablierV2LockupSender } from "./ISablierV2LockupSender.sol";

import { OnlyDelegateCall } from "./OnlyDelegateCall.sol";
import { ISablierV2Archive } from "./ISablierV2Archive.sol";
import { ISablierV2ProxyPlugin } from "./ISablierV2ProxyPlugin.sol";
import { Errors } from "./ud2x18_Errors.sol";

/*

███████╗ █████╗ ██████╗ ██╗     ██╗███████╗██████╗     ██╗   ██╗██████╗
██╔════╝██╔══██╗██╔══██╗██║     ██║██╔════╝██╔══██╗    ██║   ██║╚════██╗
███████╗███████║██████╔╝██║     ██║█████╗  ██████╔╝    ██║   ██║ █████╔╝
╚════██║██╔══██║██╔══██╗██║     ██║██╔══╝  ██╔══██╗    ╚██╗ ██╔╝██╔═══╝
███████║██║  ██║██████╔╝███████╗██║███████╗██║  ██║     ╚████╔╝ ███████╗
╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝╚══════╝╚═╝  ╚═╝      ╚═══╝  ╚══════╝

██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗    ██████╗ ██╗     ██╗   ██╗ ██████╗ ██╗███╗   ██╗
██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝╚██╗ ██╔╝    ██╔══██╗██║     ██║   ██║██╔════╝ ██║████╗  ██║
██████╔╝██████╔╝██║   ██║ ╚███╔╝  ╚████╔╝     ██████╔╝██║     ██║   ██║██║  ███╗██║██╔██╗ ██║
██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗   ╚██╔╝      ██╔═══╝ ██║     ██║   ██║██║   ██║██║██║╚██╗██║
██║     ██║  ██║╚██████╔╝██╔╝ ██╗   ██║       ██║     ███████╗╚██████╔╝╚██████╔╝██║██║ ╚████║
╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝       ╚═╝     ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝╚═╝  ╚═══╝

*/

/// @title SablierV2ProxyPlugin
/// @notice See the documentation in {ISablierV2ProxyPlugin}.
contract SablierV2ProxyPlugin is
    OnlyDelegateCall, // 0 inherited components
    ISablierV2ProxyPlugin // 2 inherited components
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISablierV2ProxyPlugin
    ISablierV2Archive public immutable override archive;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(ISablierV2Archive archive_) {
        archive = archive_;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPRBProxyPlugin
    function getMethods() external pure returns (bytes4[] memory methods) {
        methods = new bytes4[](1);
        methods[0] = this.onStreamCanceled.selector;
    }

    /*//////////////////////////////////////////////////////////////////////////
                               NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISablierV2LockupSender
    /// @notice Forwards the refunded assets to the proxy owner when the recipient cancel a stream whose sender is the
    /// proxy contract.
    /// @dev Requirements:
    /// - Must be delegate called.
    /// - The caller must be an address listed in the archive.
    function onStreamCanceled(
        uint256 streamId,
        address, /* recipient */
        uint128 senderAmount,
        uint128 /* recipientAmount */
    )
        external
        onlyDelegateCall
    {
        // Checks: the caller is an address listed in the archive.
        if (!archive.isListed(msg.sender)) {
            revert Errors.SablierV2ProxyPlugin_UnknownCaller(msg.sender);
        }

        // This invariant should always hold but it's better to be safe than sorry.
        ISablierV2Lockup lockup = ISablierV2Lockup(msg.sender);
        address streamSender = lockup.getSender(streamId);
        assert(streamSender == address(this));

        // Effects: forward the refunded assets to the proxy owner.
        IERC20 asset = lockup.getAsset(streamId);
        address owner = IPRBProxy(address(this)).owner();
        asset.safeTransfer({ to: owner, value: senderAmount });
    }
}

