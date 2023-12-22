// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ACyfrinSecurityChallengeContract.sol";

contract HuffChallenge is ACyfrinSecurityChallengeContract {
    // This helper was written in Huff... Lmao good luck
    address private s_helper;

    constructor(
        address huffHelper,
        address cscNft
    ) ACyfrinSecurityChallengeContract(cscNft) {
        s_helper = huffHelper;
    }

    /*
     * @param selector - Hehe.
     * @param twitterHandle - Your twitter handle. Can be a blank string.
     */
    function solveChallenge(
        bytes4 selector,
        string memory yourTwitterHandle
    ) public requireIsNotSolved {
        (bool success, bytes memory returnData) = s_helper.call(
            abi.encodeWithSelector(selector)
        );
        require(success, "Call failed!");
        require(uint256(bytes32(returnData)) == 7, "Call failed!");
        _updateAndRewardSolver(yourTwitterHandle);
    }

    function description() external pure override returns (string memory) {
        return unicode"♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞♘♞";
    }
}

