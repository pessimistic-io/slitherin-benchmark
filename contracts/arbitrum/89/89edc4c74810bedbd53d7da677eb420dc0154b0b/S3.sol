// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Challenge} from "./Challenge.sol";

contract S3 is Challenge {
    error S3__WrongValue();

    uint256 private constant STARTING_NUMBER = 123;
    uint256 private constant STORAGE_LOCATION = 777;

    constructor(address registry) Challenge(registry) {
        assembly {
            sstore(STORAGE_LOCATION, STARTING_NUMBER)
        }
    }

    /*
     * CALL THIS FUNCTION!
     * 
     * @param valueAtStorageLocationSevenSevenSeven - The value at storage location 777.
     * @param yourTwitterHandle - Your twitter handle. Can be a blank string.
     */
    function solveChallenge(uint256 valueAtStorageLocationSevenSevenSeven, string memory yourTwitterHandle) external {
        uint256 value;
        assembly {
            value := sload(STORAGE_LOCATION)
        }
        if (value != valueAtStorageLocationSevenSevenSeven) {
            revert S3__WrongValue();
        }
        // slither-disable-next-line weak-prng
        uint256 newValue =
            uint256(keccak256(abi.encodePacked(msg.sender, block.prevrandao, block.timestamp))) % 1_000_000;
        assembly {
            sstore(STORAGE_LOCATION, newValue)
        }
        _updateAndRewardSolver(yourTwitterHandle);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////// The following are functions needed for the NFT, feel free to ignore. ///////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function attribute() external pure override returns (string memory) {
        return "Repeater";
    }

    function description() external pure override returns (string memory) {
        return "Section 3: PasswordStore";
    }

    function specialImage() external pure returns (string memory) {
        // This is b3.png
        return "ipfs://QmPdeDyfHnYn1LbLVg9wqjNnXRPcZSAmEZjjEFuyzAej8e";
    }
}

