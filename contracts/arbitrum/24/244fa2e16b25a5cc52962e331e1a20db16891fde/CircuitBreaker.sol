pragma solidity 0.8.4;

// SPDX-License-Identifier: BUSL-1.1

import "./AccessControl.sol";
import "./Interfaces.sol";

/**
 * @author Heisenberg
 */
contract CircuitBreaker is ICircuitBreaker, AccessControl {
    mapping(address => MarketStats) public marketStats;
    mapping(address => PoolStats) public poolStats;
    mapping(address => int256) public poolAPRs;
    mapping(address => int256) public thresholds;
    bytes32 public constant OPTION_CREATOR = keccak256("OPTION_CREATOR");

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function initialize(
        MarketPoolPair[] calldata marketPoolPair,
        Configs[] calldata _aprs,
        Configs[] calldata _thresholds
    ) external {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Caller is not an admin"
        );
        for (uint256 index = 0; index < marketPoolPair.length; index++) {
            poolStats[marketPoolPair[index].pool].markets.push(
                marketPoolPair[index].market
            );
            marketStats[marketPoolPair[index].market].pool = marketPoolPair[
                index
            ].pool;
        }

        for (uint256 index = 0; index < _aprs.length; index++) {
            poolAPRs[_aprs[index].contractAddress] = _aprs[index].value;
        }
        for (uint256 index = 0; index < _thresholds.length; index++) {
            thresholds[_thresholds[index].contractAddress] = _thresholds[index]
                .value;
        }
    }

    function afterUpdate(address market, address pool) internal {
        OverallStats memory poolStat = getPoolData(pool);

        if (thresholds[pool] > 0 && poolStat.net_loss >= thresholds[pool]) {
            address[] memory markets = poolStats[pool].markets;
            for (uint256 index = 0; index < markets.length; index++) {
                if (!IBufferBinaryOptionPauserV2_5(markets[index]).isPaused()) {
                    IBufferBinaryOptionPauserV2_5(markets[index]).setIsPaused();
                }
            }
            emit PoolPaused(pool);
            return;
        }

        OverallStats memory marketStat = getMarketData(market);

        if (
            thresholds[market] > 0 && marketStat.net_loss >= thresholds[market]
        ) {
            if (!IBufferBinaryOptionPauserV2_5(market).isPaused()) {
                IBufferBinaryOptionPauserV2_5(market).setIsPaused();
                emit MarketPaused(market, pool);
            }
        }
    }

    function update(
        int256 loss,
        int256 sf,
        uint256 option_id
    ) external override {
        require(
            hasRole(OPTION_CREATOR, msg.sender),
            "Caller is not an options contract"
        );
        address pool = marketStats[msg.sender].pool;
        marketStats[msg.sender].loss += loss;
        marketStats[msg.sender].sf += sf;
        poolStats[pool].loss += loss;
        poolStats[pool].sf += sf;
        // emit Update(loss, sf, msg.sender, pool, option_id);
        afterUpdate(msg.sender, pool);
    }

    function getPoolData(
        address pool
    ) public view returns (OverallStats memory) {
        PoolStats memory poolStat = poolStats[pool];
        int256 lp_sf = (poolStat.sf * poolAPRs[pool]) / 1e4;
        return
            OverallStats({
                contractAddress: pool,
                loss: poolStat.loss,
                sf: poolStat.sf,
                lp_sf: lp_sf,
                net_loss: poolStat.loss - lp_sf
            });
    }

    function getMarketData(
        address market
    ) public view returns (OverallStats memory) {
        MarketStats memory marketStat = marketStats[market];
        int256 lp_sf = (marketStat.sf * poolAPRs[marketStat.pool]) / 1e4;
        return
            OverallStats({
                contractAddress: market,
                loss: marketStat.loss,
                sf: marketStat.sf,
                lp_sf: (marketStat.sf * poolAPRs[marketStat.pool]) / 1e4,
                net_loss: marketStat.loss - lp_sf
            });
    }

    function getAllMarketsData(
        address[] memory markets
    ) public view returns (OverallStats[] memory) {
        OverallStats[] memory overallStats = new OverallStats[](markets.length);
        for (uint256 index = 0; index < markets.length; index++) {
            overallStats[index] = getMarketData(markets[index]);
        }
        return overallStats;
    }

    function getAllPoolsData(
        address[] memory pools
    ) public view returns (OverallStats[] memory) {
        OverallStats[] memory overallStats = new OverallStats[](pools.length);
        for (uint256 index = 0; index < pools.length; index++) {
            overallStats[index] = getPoolData(pools[index]);
        }
        return overallStats;
    }
}

