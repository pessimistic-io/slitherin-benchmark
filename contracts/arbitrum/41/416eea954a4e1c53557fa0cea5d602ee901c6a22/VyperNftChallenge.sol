// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ACyfrinSecurityChallengeContract.sol";

error VyperNftChallenge__CallFailed();
error VyperNftChallenge__UserDoesntHaveNft();

interface IVyperNft {
    function hasNft(address) external view returns (bool);
}

contract VyperNftChallenge is ACyfrinSecurityChallengeContract {
    address public s_helper;

    constructor(
        address vyperHelper,
        address cscNft
    ) ACyfrinSecurityChallengeContract(cscNft) {
        s_helper = vyperHelper;
    }

    /*
     * @param selector - Hehe.
     * @param twitterHandle - Your twitter handle. Can be a blank string.
     */
    function solveChallenge(
        address yourContractAddress,
        bytes4 selector,
        string memory yourTwitterHandle
    ) public requireIsNotSolved {
        (bool success, ) = s_helper.call(
            abi.encodeWithSelector(selector, yourContractAddress, msg.sender)
        );
        if (!success) {
            revert VyperNftChallenge__CallFailed();
        }
        if (!IVyperNft(s_helper).hasNft(msg.sender)) {
            revert VyperNftChallenge__UserDoesntHaveNft();
        }
        _updateAndRewardSolver(yourTwitterHandle);
    }

    function description() external pure override returns (string memory) {
        return unicode"🐍🐍🐍🐍🐍🐍🐍🐍🐍🐍🐍🐍🐍";
    }
}

