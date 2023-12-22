// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./IUniswapV2ERC721.sol";

interface IArkenPairLongTerm is IUniswapV2ERC721 {
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function MINIMUM_LOCK_TIME() external pure returns (uint256);

    function mintedAt(uint256 tokenId) external view returns (uint256);

    function unlockedAt(uint256 tokenId) external view returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(
        address to,
        uint256 lockTime
    ) external returns (uint256 liquidity, uint256 tokenId);

    function burn(
        address to,
        uint256 tokenId
    ) external returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;

    function getLiquidity(
        uint256 tokenId
    )
        external
        view
        returns (uint256 amount0, uint256 amount1, uint256 liquidity);
}

