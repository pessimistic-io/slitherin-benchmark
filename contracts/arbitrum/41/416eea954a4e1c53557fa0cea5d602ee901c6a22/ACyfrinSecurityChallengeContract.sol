// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ICyfrinSecurityChallengeContract} from "./ICyfrinSecurityChallengeContract.sol";
import {ICyfrinSecurityChallenges} from "./ICyfrinSecurityChallenges.sol";

error ACyfrinSecurityChallengeContract__AlreadySolved();
error ACyfrinSecurityChallengeContract__TransferFailed();

abstract contract ACyfrinSecurityChallengeContract is
    ICyfrinSecurityChallengeContract
{
    string private constant BLANK_TWITTER_HANLE = "";
    string private constant BLANK_SPECIAL_DESCRIPTION = "";
    ICyfrinSecurityChallenges internal immutable i_cyfrinSecurityChallenges;
    bool internal s_solved;
    string private s_twitterHandleOfSolver;

    modifier requireIsNotSolved() {
        if (s_solved) {
            revert ACyfrinSecurityChallengeContract__AlreadySolved();
        }
        _;
    }

    constructor(address cyfrinSecurityChallengesNft) {
        i_cyfrinSecurityChallenges = ICyfrinSecurityChallenges(
            cyfrinSecurityChallengesNft
        );
        s_solved = false;
    }

    /*
     * @param twitterHandleOfSolver - The twitter handle of the solver.
     * It can be left blank.
     */
    function _updateAndRewardSolver(
        string memory twitterHandleOfSolver
    ) internal requireIsNotSolved {
        s_solved = true;
        s_twitterHandleOfSolver = twitterHandleOfSolver;
        ICyfrinSecurityChallenges(i_cyfrinSecurityChallenges).mintNft(
            msg.sender
        );
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        if (!success) {
            revert ACyfrinSecurityChallengeContract__TransferFailed();
        }
    }

    function _updateAndRewardSolver() internal {
        _updateAndRewardSolver(BLANK_TWITTER_HANLE);
    }

    function description() external view virtual returns (string memory);

    function specialImage() external view virtual returns (string memory) {
        return BLANK_SPECIAL_DESCRIPTION;
    }

    function isSolved() external view returns (bool) {
        return s_solved;
    }

    function getTwitterHandleOfSolver() external view returns (string memory) {
        return s_twitterHandleOfSolver;
    }

    // Gonna see if people MEV this shit...
    receive() external payable {}
}

