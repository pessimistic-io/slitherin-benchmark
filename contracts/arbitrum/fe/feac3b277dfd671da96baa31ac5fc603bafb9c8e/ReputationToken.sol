// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";

contract ReputationToken is Ownable{

    string topic;
    string symbol;
    address deployer;

    mapping(address => uint256) private ratings;

    event Rating(address _rated, uint256 _rating);

    constructor(
        string memory _topic,
        string memory _symbol
    ) Ownable() {
        topic = _topic;
        symbol = _symbol;
        deployer = msg.sender;
        transferOwnership(tx.origin);
    }

    /// @notice Rate an address.
    ///  MUST emit a Rating event with each successful call.
    /// @param _rated Address to be rated.
    /// @param _rating Total EXP tokens to reallocate.
    function rate(address _rated, uint256 _rating) external {
        require(
            (owner() == msg.sender) || (msg.sender == deployer),
            "sender must be factor of owner"
        );
        ratings[_rated] += _rating;
        emit Rating(_rated, _rating);
    }

    /// @notice Return a rated address' rating.
    /// @dev MUST register each time `Rating` emits.
    ///  SHOULD throw for queries about the zero address.
    /// @param _rated An address for whom to query rating.
    /// @return int8 The rating assigned.
    function ratingOf(address _rated) external view returns (uint256){
        return ratings[_rated];
    }
}
