// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import "./SafeERC20Upgradeable.sol";

struct SwapDescriptionV2 {
    IERC20Upgradeable srcToken;
    IERC20Upgradeable dstToken;
    address[] srcReceivers; // transfer src token to these addresses, default
    uint256[] srcAmounts;
    address[] feeReceivers;
    uint256[] feeAmounts;
    address dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
    bytes permit;
}

struct SwapExecutionParams {
    address callTarget; // call this address
    address approveTarget; // approve this address if _APPROVE_FUND set
    bytes targetData;
    SwapDescriptionV2 generic;
    bytes clientData;
}

