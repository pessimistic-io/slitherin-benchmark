// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ACyfrinSecurityChallengeContract.sol";
import "./ReenterHelper.sol";

interface IOtherContract {
    function getOwner() external returns (address);
}

contract Reenter is ACyfrinSecurityChallengeContract {
    ReenterHelper private s_helper;

    constructor(
        address helper,
        address cscNft
    ) ACyfrinSecurityChallengeContract(cscNft) {
        s_helper = ReenterHelper(helper);
    }

    /*
     * @param yourAddress - Hehe.
     * @param selector - Hehehe.
     * @param twitterHandle - Your twitter handle. Can be a blank string.
     */
    function solveChallenge(
        address yourAddress,
        bytes4 selector,
        string memory youTwitterHandle
    ) public requireIsNotSolved {
        require(
            IOtherContract(yourAddress).getOwner() == msg.sender,
            "This isn't yours!"
        );
        bool returnedOne = s_helper.callContract(yourAddress);
        bool returnedTwo = s_helper.callContractAgain(yourAddress, selector);
        require(returnedOne && returnedTwo, "One of them failed!");
        _updateAndRewardSolver(youTwitterHandle);
    }

    function description() external pure override returns (string memory) {
        return
            "Nice work getting in-Nice work getting into the contract!to the contract!";
    }
}

