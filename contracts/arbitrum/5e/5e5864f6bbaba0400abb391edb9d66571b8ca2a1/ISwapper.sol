// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

enum MinAmountOutKind {
    Absolute,
    ChainlinkBased
}

struct MinAmountOutData {
    MinAmountOutKind kind;
    uint256 absoluteOrBPSValue; // for type "ChainlinkBased", value must be in BPS
}

interface ISwapper {
    function uniV2SwapPaths(address _from, address _to, address _router, uint256 _index) external returns (address);

    function balSwapPoolIDs(address _from, address _to, address _vault) external returns (bytes32);

    function veloSwapPaths(address _from, address _to, address _router, uint256 _index) external returns (address);

    function uniV3SwapPaths(address _from, address _to, address _router, uint256 _index) external returns (address);

    function uniV3Quoters(address _router) external returns (address);

    function aggregatorData(address _token) external returns (address, uint256);

    function updateUniV2SwapPath(address _tokenIn, address _tokenOut, address _router, address[] calldata _path)
        external;

    function updateBalSwapPoolID(address _tokenIn, address _tokenOut, address _vault, bytes32 _poolID) external;

    function updateVeloSwapPath(address _tokenIn, address _tokenOut, address _router, address[] calldata _path)
        external;

    function updateUniV3SwapPath(address _tokenIn, address _tokenOut, address _router, address[] calldata _path)
        external;

    function updateUniV3Quoter(address _router, address _quoter) external;

    function updateTokenAggregator(address _token, address _aggregator, uint256 _timeout) external;

    function swapUniV2(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _router
    ) external;

    function swapBal(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _vault
    ) external;

    function swapVelo(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _router
    ) external;

    function swapUniV3(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _router
    ) external;
}

