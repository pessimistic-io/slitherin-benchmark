// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "./IDexSwapERC20.sol";

interface IDexSwapPair is IDexSwapERC20 {
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event FeeUpdated(uint256 fee);
    event ProtocolShareUpdated(uint256 share);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external view returns (uint256);

    function MAX_FEE() external view returns (uint256);

    function MAX_PROTOCOL_SHARE() external view returns (uint256);

    function factory() external view returns (address);

    function fee() external view returns (uint256);

    function protocolShare() external view returns (uint256);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getAmountOut(uint256 amountIn, address tokenIn, address caller) external view returns (uint256 amountOut);

    function getAmountIn(uint256 amountOut, address tokenIn, address caller) external view returns (uint256 amountIn);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint256 blockTimestampLast);

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

    function swapFromPeriphery(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        address caller,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;

    function updateFee(uint256 fee_) external returns (bool);

    function updateProtocolShare(uint256 share) external returns (bool);
}

