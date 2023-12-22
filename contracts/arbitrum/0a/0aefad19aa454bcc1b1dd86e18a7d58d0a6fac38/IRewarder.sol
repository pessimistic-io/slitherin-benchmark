// File contracts/interfaces/IRewarder.sol

pragma solidity 0.8.20;

import {IERC20} from "./IERC20.sol";

interface IRewarder {
    function onSushiReward(uint256 pid, address user, address recipient, uint256 sushiAmount, uint256 newLpAmount)
        external;
    function pendingTokens(uint256 pid, address user, uint256 sushiAmount)
        external
        view
        returns (IERC20[] memory, uint256[] memory);
}

