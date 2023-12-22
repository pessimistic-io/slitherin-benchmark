// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

interface IRebateHandler {
    struct Rebate {
        address receiver;
        uint256 amount;
        address token;
    }

    /**
     * @dev calculates zero or more rebates given arbitrary parameters
     * @param params the abi encoded parameters for this handler
     */
    function executeRebates(bytes32 action, bytes calldata params) external;
}

