// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPool {
    function implementation() external view returns (address);

    function protocolFeeCollector() external view returns (address);

    function liquidity() external view returns (int256);

    function lpsPnl() external view returns (int256);

    function cumulativePnlPerLiquidity() external view returns (int256);

    function protocolFeeAccrued() external view returns (int256);

    function setImplementation(address newImplementation) external;

    function addMarket(address market) external;

    function approveSwapper(address underlying) external;

    function collectProtocolFee() external;

    function claimVenusLp(address account) external;

    function claimVenusTrader(address account) external;

    struct OracleSignature {
        bytes32 oracleSymbolId;
        uint256 timestamp;
        uint256 value;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct PythData {
        bytes[] vaas;
        bytes32[] ids;
    }

    function addLiquidity(
        address underlying,
        uint256 amount,
        PythData calldata pythData
    ) external payable;

    function removeLiquidity(
        address underlying,
        uint256 amount,
        PythData calldata pythData
    ) external;

    function addMargin(
        address underlying,
        uint256 amount,
        PythData calldata pythData
    ) external payable;

    function removeMargin(
        address underlying,
        uint256 amount,
        PythData calldata pythData
    ) external;

    function trade(
        string memory symbolName,
        int256 tradeVolume,
        int256 priceLimit
    ) external;

    function liquidate(uint256 pTokenId, PythData calldata pythData) external;

    struct LpInfo {
        address vault;
        int256 amountB0;
        int256 liquidity;
        int256 cumulativePnlPerLiquidity;
    }

    function lpInfos(uint256) external view returns (LpInfo memory);
}

