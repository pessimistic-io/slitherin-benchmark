// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

interface IReferralPayment {
    function claim(
        address user,
        uint256 totalPNFT,
        uint256 totalETH,
        uint256 deadline,
        bytes memory signature
    ) external;
}

