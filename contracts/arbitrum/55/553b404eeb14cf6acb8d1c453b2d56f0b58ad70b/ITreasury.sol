// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

interface TreasuryContract {
    function isAdmin(address account) external view returns (bool);

    function isPlatformWallet(address account) external view returns (bool);

    function isVaultCreator(address account) external view returns (bool);

    function isReferralDisburser(address account) external view returns (bool);
}

