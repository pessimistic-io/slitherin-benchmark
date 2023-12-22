// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library HookChecker {
    uint256 internal constant BEFORE_DEPLOY_FLAG = 1; // 0000 0001
    uint256 internal constant AFTER_CLOSE_FLAG = 2; // 0000 0010
    uint256 internal constant AFTER_DEPOSIT_FLAG = 4; // 0000 0100
    uint256 internal constant BEFORE_WITHDRAW_FLAG = 8; // 0000 1000
    uint256 internal constant TOTAL_ASSETS_FLAG = 16; // 0001 0000
    uint256 internal constant AVAILABLE_AMOUNT_FLAG = 32; // 0010 0000
    uint256 internal constant TRANSFER_AFTER_CLOSE_FLAG = 64; // 0100 0000
    uint256 internal constant AFTER_DEPLOY_FLAG = 128; // 1000 0000
    uint256 internal constant BEFORE_CLOSE_FLAG = 256; // 0001 0000 0000

    /**
        @notice Checks if the beforeDeploy hook function should be called
        @param hookCommand the byte command
        @return boolean value for Y/N
     */
    function shouldCallBeforeDeploy(
        uint16 hookCommand
    ) internal pure returns (bool) {
        return hookCommand & BEFORE_DEPLOY_FLAG != 0;
    }

    /**
        @notice Checks if the afterClose hook function should be called
        @param hookCommand the byte command
        @return boolean value for Y/N
     */
    function shouldCallAfterClose(
        uint16 hookCommand
    ) internal pure returns (bool) {
        return hookCommand & AFTER_CLOSE_FLAG != 0;
    }

    /**
        @notice Checks if the afterDeposit hook function should be called
        @param hookCommand the byte command
        @return boolean value for Y/N
     */
    function shouldCallAfterDeposit(
        uint16 hookCommand
    ) internal pure returns (bool) {
        return hookCommand & AFTER_DEPOSIT_FLAG != 0;
    }

    /**
        @notice Checks if the beforeWithdraw hook function should be called
        @param hookCommand the byte command
        @return boolean value for Y/N
     */
    function shouldCallBeforeWithdraw(
        uint16 hookCommand
    ) internal pure returns (bool) {
        return hookCommand & BEFORE_WITHDRAW_FLAG != 0;
    }

    /**
        @notice Checks if the totalAssets hook function should be called
        @param hookCommand the byte command
        @return boolean value for Y/N
     */
    function shouldCallForTotalAssets(
        uint16 hookCommand
    ) internal pure returns (bool) {
        return hookCommand & TOTAL_ASSETS_FLAG != 0;
    }

    /**
        @notice Checks if the availableAmount hook function should be called
        @param hookCommand the byte command
        @return boolean value for Y/N
     */
    function shouldCallForAvailableAmounts(
        uint16 hookCommand
    ) internal pure returns (bool) {
        return hookCommand & AVAILABLE_AMOUNT_FLAG != 0;
    }

    /**
        @notice Checks if assets should be transferred afterClose
        @param hookCommand the byte command
        @return boolean value for Y/N
     */
    function shouldTransferAfterClose(
        uint16 hookCommand
    ) internal pure returns (bool) {
        return hookCommand & TRANSFER_AFTER_CLOSE_FLAG != 0;
    }

    /**
        @notice Checks if assets should be transferred beforeDeploy
        @param hookCommand the byte command
        @return boolean value for Y/N
     */
    function shouldCallAfterDeploy(
        uint16 hookCommand
    ) internal pure returns (bool) {
        return hookCommand & AFTER_DEPLOY_FLAG != 0;
    }

    /**
        @notice Checks if assets should be transferred beforeDeploy
        @param hookCommand the byte command
        @return boolean value for Y/N
     */
    function shouldCallBeforeClose(
        uint16 hookCommand
    ) internal pure returns (bool) {
        return hookCommand & BEFORE_CLOSE_FLAG != 0;
    }
}

