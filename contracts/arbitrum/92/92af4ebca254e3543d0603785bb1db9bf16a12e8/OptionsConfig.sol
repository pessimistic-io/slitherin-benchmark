pragma solidity ^0.8.4;

// SPDX-License-Identifier: BUSL-1.1

import "./Ownable.sol";
import "./Interfaces.sol";

/**
 * @author Heisenberg
 * @title Buffer Options Config
 * @notice Maintains all the configurations for the options contracts
 */
contract OptionsConfig is Ownable, IOptionsConfig {
    ILiquidityPool public pool;

    address public override settlementFeeDisbursalContract;
    address public override traderNFTContract;
    uint16 public override assetUtilizationLimit = 10e2;
    uint16 public override overallPoolUtilizationLimit = 64e2;
    uint32 public override maxPeriod = 24 hours;
    uint32 public override minPeriod = 5 minutes;

    uint16 public override optionFeePerTxnLimitPercent = 5e2;
    uint256 public override minFee = 1e6;

    mapping(uint8 => Window) public override marketTimes;

    constructor(ILiquidityPool _pool) {
        pool = _pool;
    }

    function settraderNFTContract(address value) external onlyOwner {
        traderNFTContract = value;
        emit UpdatetraderNFTContract(value);
    }

    function setMinFee(uint256 value) external onlyOwner {
        minFee = value;
        emit UpdateMinFee(value);
    }

    function setSettlementFeeDisbursalContract(
        address value
    ) external onlyOwner {
        settlementFeeDisbursalContract = value;
        emit UpdateSettlementFeeDisbursalContract(value);
    }

    function setOptionFeePerTxnLimitPercent(uint16 value) external onlyOwner {
        optionFeePerTxnLimitPercent = value;
        emit UpdateOptionFeePerTxnLimitPercent(value);
    }

    function setOverallPoolUtilizationLimit(uint16 value) external onlyOwner {
        require(value <= 100e2 && value > 0, "Wrong utilization value");
        overallPoolUtilizationLimit = value;
        emit UpdateOverallPoolUtilizationLimit(value);
    }

    function setAssetUtilizationLimit(uint16 value) external onlyOwner {
        require(value <= 100e2 && value > 0, "Wrong utilization value");
        assetUtilizationLimit = value;
        emit UpdateAssetUtilizationLimit(value);
    }

    function setMaxPeriod(uint32 value) external onlyOwner {
        require(
            value <= 1 days,
            "MaxPeriod should be less than or equal to 1 day"
        );
        require(
            value >= minPeriod,
            "MaxPeriod needs to be greater than or equal the min period"
        );
        maxPeriod = value;
        emit UpdateMaxPeriod(value);
    }

    function setMinPeriod(uint32 value) external onlyOwner {
        require(
            value >= 1 minutes,
            "MinPeriod needs to be greater than 1 minute"
        );
        minPeriod = value;
        emit UpdateMinPeriod(value);
    }

    function setMarketTime(Window[] memory windows) external onlyOwner {
        for (uint8 index = 0; index < windows.length; index++) {
            marketTimes[index] = windows[index];
        }
        emit UpdateMarketTime();
    }
}

