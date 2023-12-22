// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Challenge} from "./Challenge.sol";

contract S2 is Challenge {
    error S2__WrongValue();

    constructor(address registry) Challenge(registry) {}

    /*
     * CALL THIS FUNCTION!
     * 
     * @param weCallItSecurityReview - Set "true" if you'll call it "security review" instead of "security audit".
     * @param yourTwitterHandle - Your twitter handle. Can be a blank string.
     */
    function solveChallenge(bool weCallItSecurityReview, string memory yourTwitterHandle) external {
        if (!weCallItSecurityReview) {
            revert S2__WrongValue();
        }
        _updateAndRewardSolver(yourTwitterHandle);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////// The following are functions needed for the NFT, feel free to ignore. ///////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function attribute() external pure override returns (string memory) {
        return "Good at function calling";
    }

    function description() external pure override returns (string memory) {
        return "Section 2: What is a smart contract security review?";
    }

    function specialImage() external pure returns (string memory) {
        // This is b2.png
        return "ipfs://QmQG94rge28BJaQAvLV5MkMNNbq8T3r4n9n5Qqxmridanm";
    }
}

