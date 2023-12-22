// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IMellowBaseOracle.sol";
import "./UniV3TokenRegistry.sol";

contract UniV3Oracle is IMellowBaseOracle {
    error InvalidAddress();
    error InvalidNft();
    error PoolNotFound();

    UniV3TokenRegistry public immutable registry;

    constructor(UniV3TokenRegistry registry_) {
        registry = registry_;
    }

    function isTokenSupported(address token) external view override returns (bool) {
        return registry.ids(token) != 0;
    }

    struct UniV3TokenSecurityParams {
        uint32[] secondsAgo;
        int24 maxDeviation;
    }

    function _checkPoolState(address token, bytes memory data) private view {
        UniV3TokenSecurityParams memory params = abi.decode(data, (UniV3TokenSecurityParams));
        (int24[] memory averageTicks, bool withFail) = OracleLibrary.consultMultiple(
            address(UniV3Token(token).pool()),
            params.secondsAgo
        );
        require(!withFail);
        int24 minTick = averageTicks[0];
        int24 maxTick = minTick;
        for (uint256 i = 1; i < averageTicks.length; i++) {
            if (minTick > averageTicks[i]) {
                minTick = averageTicks[i];
            } else if (maxTick < averageTicks[i]) {
                maxTick = averageTicks[i];
            }
        }
        require(maxTick - minTick <= params.maxDeviation);
    }

    function quote(
        address token,
        uint256 amount,
        IBaseOracle.SecurityParams memory params
    ) public view override returns (address[] memory tokens, uint256[] memory tokenAmounts) {
        _checkPoolState(token, params.parameters);
        tokens = new address[](2);
        tokens[0] = UniV3Token(token).token0();
        tokens[1] = UniV3Token(token).token1();
        uint256 liquidity = UniV3Token(token).convertSupplyToLiquidity(amount);
        tokenAmounts = new uint256[](2);
        (tokenAmounts[0], tokenAmounts[1]) = UniV3Token(token).getAmountsForLiquidity(uint128(liquidity));
        {
            (uint256 fees0, uint256 fees1) = PositionValue.fees(
                UniV3Token(token).positionManager(),
                UniV3Token(token).uniV3Nft(),
                UniV3Token(token).pool()
            );
            if (fees0 + fees1 > 0) {
                uint256 totalSupply = UniV3Token(token).totalSupply();
                tokenAmounts[0] += FullMath.mulDiv(fees0, amount, totalSupply);
                tokenAmounts[1] += FullMath.mulDiv(fees1, amount, totalSupply);
            }
        }
    }
}

