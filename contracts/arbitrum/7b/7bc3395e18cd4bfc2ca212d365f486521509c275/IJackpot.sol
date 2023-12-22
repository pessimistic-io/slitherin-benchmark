// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;
pragma experimental ABIEncoderV2;

interface IJackpot {
    function newTicket(address) external;
    function claim(uint256, address, address) external;
    function claimAll(uint256, address) external;
    function currentPrize() external returns(address[] memory, uint256[] memory);
}
