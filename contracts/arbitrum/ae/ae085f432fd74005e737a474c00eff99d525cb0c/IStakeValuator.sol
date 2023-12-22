// SPDX-License-Identifier: MIT

import { IERC20 } from "./IERC20.sol";
import { ISnapshottable } from "./ISnapshottable.sol";

pragma solidity ^0.8.0;


interface IOracle {
    // returns (price, lastUpdated)
    function getPrice(IERC20 token) external view returns (uint256, uint256);
}


struct PriceOracle {
    // snapshots need to know if this datum exists or is a default
    bool exists;
    bool isOracle;
    // if not isOracle, this can be cast to a uint160 to get the price
    IOracle oracle;
}


interface IStakeValuator is ISnapshottable {
    function token() external view returns (IERC20);
    function stakeFor(address _account, uint256 _amount) external;
    function getStakers(uint256 idx) external view returns (address);
    function getStakersCount() external view returns (uint256);
    function getVestedTokens(address user) external view returns (uint256);
    function getVestedTokensAtSnapshot(address user, uint256 blockNumber) external view returns (uint256);

    function getValueAtSnapshot(IERC20 _token, uint256 _blockNumber) external view returns (uint256);
}
