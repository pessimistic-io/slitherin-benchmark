// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Challenge} from "./Challenge.sol";

contract S0 is Challenge {
    constructor(address registry) Challenge(registry) {}

    /*
     * CALL THIS FUNCTION!
     * 
     * @param yourTwitterHandle - Your twitter handle. Can be a blank string.
     */
    function solveChallenge(string memory twitterHandle) external {
        _updateAndRewardSolver(twitterHandle);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////// The following are functions needed for the NFT, feel free to ignore. ///////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function attribute() external pure override returns (string memory) {
        return "Confident";
    }

    function description() external pure override returns (string memory) {
        return "Section 0: Welcome!";
    }

    function specialImage() external pure returns (string memory) {
        // This is course_youtube_thumbnail_1920x1080px.jpg
        return "ipfs://QmV9Q8R3DcH96mCko6mQLVmRxoDZUoiwksB22E9fYFdop7";
    }
}

