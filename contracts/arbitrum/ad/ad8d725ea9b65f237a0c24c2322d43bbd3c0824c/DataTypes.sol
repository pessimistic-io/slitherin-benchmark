//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {IPancakeV3Pool} from "./IPancakeV3Pool.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

library DataTypes {
    struct UserVault {
        bool exists;
        uint256 token0;
        uint256 token1;
    }

    struct UserVaultInfo {
        address user;
        uint256 token0;
        uint256 token1;
    }

    struct State {
        int24 lowerTick;
        int24 upperTick;
        bool inThePosition;
        bool mintStarted;
        int24 tickSpacing;
        IPancakeV3Pool pool;
        IERC20Upgradeable token0;
        IERC20Upgradeable token1;
        address factory;
        uint16 managingFee;
        uint16 performanceFee;
        uint256 managerBalance0;
        uint256 managerBalance1;
        mapping(address => UserVault) userVaults;
        address[] users;
        address WETH9;
        address priceOracle0;
        address priceOracle1;
        uint256 lastRebalanceTimestamp;
        uint256 otherFee;
        uint256 otherBalance0;
        uint256 otherBalance1;
        address otherFeeRecipient;
        // NOTE: Only add more state variable below it and do not change the order of above state variables.
    }
}

