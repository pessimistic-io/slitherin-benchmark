//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPancakePair {
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

library PancakeLibrary {

    /// @notice Returns sorted token addresses, used to handle return values from pairs sorted in this order
    /// @param tokenA First token address
    /// @param tokenB Second token address
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'PancakeLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'PancakeLibrary: ZERO_ADDRESS');
    }

    /// @notice Calculates address for a pair without making any external calls
    /// @param tokenA First token address
    /// @param tokenB Second token address
    function pairFor(address tokenA, address tokenB) internal view returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        /// ETH data
        bytes memory factory = hex'5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';
        bytes memory initCodeHash = hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f';
        if (block.chainid == 56) { /// BSC
            factory = hex'cA143Ce32Fe78f1f7019d7d551a6402fC5350c73';
            initCodeHash = hex'00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5';
        }
        if (block.chainid == 97) { /// BSC testnet
            factory = hex'B7926C0430Afb07AA7DEfDE6DA862aE0Bde767bc';
            initCodeHash = hex'ecba335299a6693cb2ebc4782e74669b84290b6378ea3a3873c7231a8d7d1074';
        }
        if (block.chainid == 137 || block.chainid == 42161) { /// Polygon or Arbitrum
            factory = hex'c35DADB65012eC5796536bD9864eD8773aBc74C4';
            initCodeHash = hex'e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303';
        }
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                initCodeHash
            )))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        pairFor(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IPancakePair(pairFor(tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'PancakeLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'PancakeLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA * reserveB / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal view returns (uint amountOut) {
        require(amountIn > 0, 'PancakeLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'PancakeLibrary: INSUFFICIENT_LIQUIDITY');
        uint poolCommission = 9970; /// ETH, Polygon, Arbitrum commission
        if (block.chainid == 56) {
            poolCommission = 9975; /// BSC commission
        }
        if (block.chainid == 97) {
            poolCommission = 9980; /// BSC testnet commission
        }
        uint amountInWithFee = amountIn * poolCommission;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 10000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal view returns (uint amountIn) {
        require(amountOut > 0, 'PancakeLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'PancakeLibrary: INSUFFICIENT_LIQUIDITY');
        uint poolCommission = 9970; /// ETH, Polygon, Arbitrum commission
        if (block.chainid == 56) {
            poolCommission = 9975; /// BSC commission
        }
        if (block.chainid == 97) {
            poolCommission = 9980; /// BSC testnet commission
        }
        uint numerator = reserveIn * amountOut * 10000;
        uint denominator = (reserveOut - amountOut) * poolCommission;
        amountIn = (numerator / denominator) + 1;
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'PancakeLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'PancakeLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
