// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./Ownable.sol";

import "./IBinaryMarketManager.sol";

/// @notice One place to get current used markets on Ryze platform
/// @author https://balance.capital
contract BinaryMarketManager is Ownable, IBinaryMarketManager {
    struct MarketData {
        address market;
        string pairName;
    }

    MarketData[] public allMarkets;

    event MarketAdded(
        address indexed market,
        string pairName,
        string marketName
    );

    /// @notice register market with given address
    /// @param market address of market
    function registerMarket(IBinaryMarket market) external onlyOwner {
        string memory pairName = market.oracle().pairName();
        string memory name = market.marketName();
        allMarkets.push(MarketData(address(market), pairName));

        emit MarketAdded(address(market), pairName, name);
    }

    /// @notice Retrieve market by market pair name
    /// @param pairName name of pair
    /// @return address of given market
    function getMarketByPairName(string memory pairName)
        external
        view
        returns (address)
    {
        for (uint256 i = 0; i < allMarkets.length; i = i + 1) {
            MarketData memory d = allMarkets[i];
            if (
                keccak256(abi.encodePacked(d.pairName)) ==
                keccak256(abi.encodePacked(pairName))
            ) {
                return d.market;
            }
        }
        return address(0);
    }

    /// @notice Retrieve market pair name by market address
    /// @param market address of market
    /// @return pair name of given market
    function getPairNameByMarket(address market)
        external
        view
        returns (string memory)
    {
        for (uint256 i = 0; i < allMarkets.length; i = i + 1) {
            MarketData memory d = allMarkets[i];
            if (d.market == market) {
                return d.pairName;
            }
        }
        revert("None exists");
    }
}

