// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {ILockdropPhase2} from "./ILockdropPhase2.sol";
import {ISparta} from "./ISparta.sol";

/**
 * @title IAirdrop.
 * @notice Interface of airdrop event of SPARTA tokens.
 */
interface IAirdrop {
    error ArraysLengthNotSame();
    error BeforeReleaseTimestamp();
    error CannotWithdrawZeroTokens();
    error BalanceTooSmall();
    error OnlyAirdropManagerRole();
    error CannotBurnTokens();
    error ClaimStartNotValid();
    error MaxLengthExceeded();
    error LimitExceeded();
    error WrongTimestamps();

    event Claimed(address indexed user, uint256 amount);
    event WalletAdded(address indexed user, uint256 amount);
    event LockedOnLockdropPhase2(address indexed wallet, uint256 amount);

    /**
     * @notice Allows to set claimable amounts for a list of users.
     * @param users The array of user addresses.
     * @param amounts The corresponding amounts of tokens that users can claim.
     */
    function setClaimableAmounts(
        address[] memory users,
        uint256[] memory amounts
    ) external;

    /**
     * @notice Function allows users to claim their allocated tokens.
     */
    function claimTokens() external payable;

    /**
     * @notice Function returns the timestamp when tokens can start being burned.
     * @return uint256 Timestamp from which the team can burn unclaimed tokens.
     */
    function burningStartTimestamp() external view returns (uint256);

    /**
     * @notice Function allows to burn the tokens that had not been claimed after the claim period has ended.
     */
    function burnTokens() external;

    /**
     * @notice Function locks a certain amount of tokens on the LockdropPhase2 contract.
     * @param _amount The amount of tokens to be locked.
     */
    function lockOnLockdropPhase2(uint256 _amount) external;
}

