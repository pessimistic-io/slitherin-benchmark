// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "./IERC20.sol";

interface IFurionSwapPair is IERC20 {
    function initialize(address _token0, address _token1) external;

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function feeRate() external view returns (uint256);

    function deadline() external view returns (uint256);

    function getReserves()
        external
        view
        returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function swap(
        uint256,
        uint256,
        address,
        bytes calldata
    ) external;

    function burn(address) external returns (uint256, uint256);

    function mint(address) external returns (uint256);

    function sync() external;
}

