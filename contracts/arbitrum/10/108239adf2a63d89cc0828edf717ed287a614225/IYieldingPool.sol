// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IPool.sol";

interface IYieldingPool is IPool {
    function push(
        address assetAddress,
        uint256 amount,
        bytes memory options
    ) external returns (uint256 actualTokenAmounts);

    function pull(
        address assetAddress,
        uint256 amount,
        bytes memory options
    ) external returns (uint256 actualTokenAmounts);

    function pullAndTransfer(
        address assetAddress,
        uint256 amount,
        bytes memory options,
        address recipient
    ) external returns (uint256 actualTokenAmounts);

    function claimRewards(
        bytes memory options
    ) external returns (uint256);

    function compound() external;
}
