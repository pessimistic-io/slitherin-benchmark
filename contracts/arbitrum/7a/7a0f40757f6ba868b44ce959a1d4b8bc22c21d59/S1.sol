// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Challenge} from "./Challenge.sol";

contract S1 is Challenge {
    error S1__WrongSelector();
    error S1__WrongData();
    error S1__ZeroAddress();

    address private immutable i_helperContract;

    constructor(address registry, address helperContract) Challenge(registry) {
        if (helperContract == address(0)) {
            revert S1__ZeroAddress();
        }
        i_helperContract = helperContract;
    }

    /*
     * CALL THIS FUNCTION!
     * 
     * @param the function selector of the first one you need to call
     * @param the abi encoded data... hint! Use chisel to figure out what to use here...
     * @param yourTwitterHandle - Your twitter handle. Can be a blank string.
     */
    function solveChallenge(bytes4 selectorOne, bytes memory inputData, string memory yourTwitterHandle) external {
        (bool successOne, bytes memory responseDataOne) = i_helperContract.call(abi.encodeWithSelector(selectorOne));
        if (!successOne || uint256(bytes32((responseDataOne))) != 1) {
            revert S1__WrongSelector();
        }

        (bool successTwo, bytes memory responseDataTwo) = i_helperContract.call(inputData);
        if (!successTwo || uint256(bytes32((responseDataTwo))) != 1) {
            revert S1__WrongData();
        }
        _updateAndRewardSolver(yourTwitterHandle);
    }

    function getHelperContract() external view returns (address) {
        return i_helperContract;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////// The following are functions needed for the NFT, feel free to ignore. ///////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function attribute() external pure override returns (string memory) {
        return "Fresh";
    }

    function description() external pure override returns (string memory) {
        return "Section 1: Refresher";
    }

    function specialImage() external pure returns (string memory) {
        // This is b1.png
        return "ipfs://QmUXKKH4VrKvkpRgV5HZ3VW9fqtyTQKMvdAhcfBQVYL8HW";
    }
}

