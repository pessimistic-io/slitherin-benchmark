// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Challenge} from "./Challenge.sol";

contract S4 is Challenge {
    error S4__BadReturn();
    error S4__BadOwner();
    error S4__BadGuess();

    uint256 myVal = 0;

    constructor(address registry) Challenge(registry) {}

    /*
     * CALL THIS FUNCTION!
     * 
     * @param guess - your guess to solve the challenge. 
     * @param yourTwitterHandle - Your twitter handle. Can be a blank string.
     */
    function solveChallenge(uint256 guess, string memory yourTwitterHandle) external {
        (bool success, bytes memory returnData) = msg.sender.staticcall(abi.encodeWithSignature("owner()"));
        address ownerAddress;
        assembly {
            ownerAddress := mload(add(returnData, 32))
        }
        if (!success || ownerAddress != msg.sender) {
            revert S4__BadOwner();
        }
        if (myVal == 1) {
            // slither-disable-next-line weak-prng
            uint256 rng =
                uint256(keccak256(abi.encodePacked(msg.sender, block.prevrandao, block.timestamp))) % 1_000_000;
            if (rng != guess) {
                revert S4__BadGuess();
            }
            _updateAndRewardSolver(yourTwitterHandle);
        } else {
            myVal = 1;
            (bool succ,) = msg.sender.call(abi.encodeWithSignature("go()"));
            if (!succ) {
                revert S4__BadReturn();
            }
        }
        myVal = 0;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////// The following are functions needed for the NFT, feel free to ignore. ///////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function attribute() external pure override returns (string memory) {
        return "Puppy Master";
    }

    function description() external pure override returns (string memory) {
        return "Section 4: Puppy Raffle Audit";
    }

    function specialImage() external pure returns (string memory) {
        // This is b4.png
        return "ipfs://QmaidDd7rwStAvjouzzcu7quzvkXaV83ZE4R5r6E88zRi2";
    }
}

