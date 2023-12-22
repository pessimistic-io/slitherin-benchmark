// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;
import "./IAggregator.sol";
import "./IYearnVault.sol";

// Chainlink Aggregator

interface ILPOracle {
    function lp_price() external view returns (uint256 price);
}

contract ThreeCryptoOracle is IAggregator {
    ILPOracle public immutable LP_ORACLE;
    IYearnVault public immutable vault;

    constructor (address lpOracle, address vault_) {
        LP_ORACLE = ILPOracle(lpOracle);
        vault = IYearnVault(vault_);
    } 

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function latestAnswer() public view override returns (int256 answer) {
        return int256(LP_ORACLE.lp_price() * vault.pricePerShare() / 1e18);
    }

    function latestRoundData()
        public
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, latestAnswer(), 0, 0, 0);
    }
}
