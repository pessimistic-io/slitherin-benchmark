// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title  IGmdVault
/// @author Savvy Defi
interface IGmdVault {
    /// @notice Get pool information by pool id.
    function poolInfo(
        uint256 _pid
    )
        external
        view
        returns (
            address lpToken,
            address GDlptoken,
            uint256 EarnRateSec,
            uint256 totalStaked,
            uint256 lastUpdate,
            uint256 vaultcap,
            uint256 lgpFees,
            uint256 APR,
            bool stakable,
            bool withdrawable,
            bool rewardStart
        );

    function GDpriceToStakedtoken(uint256 _pid) external view returns (uint256);

    /// @notice Deposit baseToken.
    /// @param _amountIn Amount of baseToken to deposit.
    /// @param _pid The pool id.
    function enter(uint256 _amountIn, uint256 _pid) external;

    /// @notice Deposit ETH.
    /// @param _pid The pool id.
    function enterETH(uint256 _pid) external payable;

    /// @notice Withdraw baseToken.
    /// @param _share The share amount for withdrawing.
    /// @param _pid The pool id
    function leave(uint256 _share, uint256 _pid) external;

    /// @notice Withdraw ETH.
    /// @param _share The share amount for withdrawing.
    /// @param _pid The pool id
    function leaveETH(uint256 _share, uint256 _pid) external payable;
}

