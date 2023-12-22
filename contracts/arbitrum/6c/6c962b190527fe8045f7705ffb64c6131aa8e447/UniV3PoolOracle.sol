// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./EnumerableSet.sol";

import "./IBaseOracle.sol";

import "./OracleLibrary.sol";
import "./TickMath.sol";
import "./FullMath.sol";

import "./DefaultAccessControl.sol";

contract UniV3PoolOracle is IBaseOracle, DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    error PoolNotFound();

    uint256 public constant Q96 = 2 ** 96;

    mapping(address => address) public poolForToken;
    EnumerableSet.AddressSet private _supportedTokens;

    constructor(address admin) DefaultAccessControl(admin) {}

    function setPools(address[] memory tokens, address[] memory pools) external {
        _requireAdmin();
        require(tokens.length == pools.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            poolForToken[tokens[i]] = pools[i];
            if (pools[i] == address(0)) {
                _supportedTokens.remove(tokens[i]);
            } else {
                _supportedTokens.add(tokens[i]);
            }
        }
    }

    function supportedTokens() public view returns (address[] memory) {
        return _supportedTokens.values();
    }

    function checkPoolAndGetPrice(
        address token,
        address pool,
        bytes memory data
    ) public view returns (uint256 priceX96, address tokenOut) {
        uint32 timespan = abi.decode(data, (uint32));
        (int24 averageTick, , bool withFail) = OracleLibrary.consult(pool, timespan);
        require(!withFail);

        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);
        priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        if (IUniswapV3Pool(pool).token1() == token) {
            tokenOut = IUniswapV3Pool(pool).token0();
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        } else {
            tokenOut = IUniswapV3Pool(pool).token1();
        }
    }

    function quote(
        address token,
        uint256 amount,
        IBaseOracle.SecurityParams memory params
    ) public view override returns (address[] memory tokens, uint256[] memory tokenAmounts) {
        address pool = poolForToken[token];
        if (pool == address(0)) {
            revert PoolNotFound();
        }

        tokenAmounts = new uint256[](1);
        tokens = new address[](1);
        (uint256 priceX96, address tokenOut) = checkPoolAndGetPrice(token, pool, params.parameters);
        tokenAmounts[0] = FullMath.mulDiv(amount, priceX96, Q96);
        tokens[0] = tokenOut;
    }
}

