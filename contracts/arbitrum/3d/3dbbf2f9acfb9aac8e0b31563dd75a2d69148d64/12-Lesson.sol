// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AFoundryCourseChallenge} from "./AFoundryCourseChallenge.sol";
import {LessonTwelveHelper} from "./12-LessonHelper.sol";

contract LessonTwelve is AFoundryCourseChallenge {
    error LessonTwelve__AHAHAHAHAHA();

    string private constant LESSON_IMAGE = "ipfs://QmcSKN5FWehTrsmfpv5uiKHnoPM1L2uL8QekPSMuThHHkb";

    LessonTwelveHelper private immutable i_hellContract;

    constructor(address fcn) AFoundryCourseChallenge(fcn) {
        i_hellContract = new LessonTwelveHelper();
    }

    /*
     * CALL THIS FUNCTION!
     * 
     * Hint: Can you write a fuzz test that finds the solution for you? 
     * 
     * @param exploitContract - A contract that you're going to use to try to break this thing
     * @param yourTwitterHandle - Your twitter handle. Can be a blank string.
     */
    function solveChallenge(address exploitContract, string memory yourTwitterHandle) external {
        (bool successOne, bytes memory numberrBytes) = exploitContract.call(abi.encodeWithSignature("getNumberr()"));
        (bool successTwo, bytes memory ownerBytes) = exploitContract.call(abi.encodeWithSignature("getOwner()"));

        if (!successOne || !successTwo) {
            revert LessonTwelve__AHAHAHAHAHA();
        }

        uint128 numberr = abi.decode(numberrBytes, (uint128));
        address exploitOwner = abi.decode(ownerBytes, (address));

        if (msg.sender != exploitOwner) {
            revert LessonTwelve__AHAHAHAHAHA();
        }

        try i_hellContract.hellFunc(numberr) returns (uint256) {
            revert LessonTwelve__AHAHAHAHAHA();
        } catch {
            _updateAndRewardSolver(yourTwitterHandle);
        }
    }

    function getHellContract() public view returns (address) {
        return address(i_hellContract);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////// The following are functions needed for the NFT, feel free to ignore. ///////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function description() external pure override returns (string memory) {
        return "Cyfrin Foundry Full Course: YOOOOO YOU GOT IT????? WELL DONE!!! THIS ONE IS HARD!!";
    }

    function attribute() external pure override returns (string memory) {
        return "Fuzz or brute force code analysis skills";
    }

    function specialImage() external pure override returns (string memory) {
        return LESSON_IMAGE;
    }
}

