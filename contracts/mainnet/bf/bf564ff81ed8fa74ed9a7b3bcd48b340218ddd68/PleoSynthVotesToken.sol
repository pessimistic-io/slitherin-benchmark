// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IPleoSynthVotesToken.sol";
import "./PleoSynthVotes.sol";

abstract contract PleoSynthVotesToken is IPleoSynthVotesToken,Ownable {

    address private _pleoSynthVotes = address(0);

    constructor(address addr) {
        _pleoSynthVotes = addr;
    }

    function getPleoSynthVotesAddress() public view returns(address) {
        return _pleoSynthVotes;
    }

    function setPleoSynthVotes(address pleoSynthVotes) public onlyOwner {
        _pleoSynthVotes = pleoSynthVotes;
    }

    function transferVotingUnits(
        address from,
        address to,
        uint256 batchSize
    ) internal {
        if(_pleoSynthVotes != address(0)) {
            PleoSynthVotes(_pleoSynthVotes).transferVotingUnits(from, to, batchSize);
        }
    }

    function balanceOf(address owner) external view virtual returns (uint256 balance);
}
