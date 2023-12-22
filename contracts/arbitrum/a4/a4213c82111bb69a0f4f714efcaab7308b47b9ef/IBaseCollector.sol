// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBaseCollector {
    struct Request {
        address vault;
        address user;
    }

    struct Response {
        string name;
        uint256[] tvl;
        uint256[][] subvaultsTvl;
        uint256[] unclaimedFees;
        uint256[] pricesToUSDC;
        address[] tokens;
        uint256[] decimals;
        uint256 totalSupply;
        uint256 userBalance;
        uint256 blockNumber;
        uint256 blockTimestamp;
    }

    function collect(
        address vault,
        address user
    ) external view returns (Response memory response, address[] memory underlyingTokens);
}

