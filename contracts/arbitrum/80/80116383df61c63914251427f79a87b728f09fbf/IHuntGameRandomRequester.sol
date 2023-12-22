// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**huntnft
 * @title interface of IHuntGameRandomRequester
 * @dev this specify the action of random oracle feed the request of hunt game
 */

interface IHuntGameRandomRequester {
    /**
     * @dev ChainLink VRF fill random word to hunt game
     * @param _randomNum random word filled from ChainLink
     * @notice only invoked by factory
     */
    function fillRandom(uint256 _randomNum) external;
}

