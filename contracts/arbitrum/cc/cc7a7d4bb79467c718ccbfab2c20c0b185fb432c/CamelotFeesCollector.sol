// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ICamelotVault, IAlgebraPool} from "./ICamelotVaultGovernance.sol";

import "./IBaseFeesCollector.sol";

contract CamelotFeesCollector is IBaseFeesCollector {
    function collectFeesData(
        address vault
    ) external view override returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = ICamelotVault(vault).vaultTokens();
        (amounts, ) = ICamelotVault(vault).tvl();

        IAlgebraPool pool = ICamelotVault(vault).pool();
        (uint160 sqrtRatioX96, , , , , , ) = pool.globalState();
        uint256 positionNft = ICamelotVault(vault).positionNft();
        (, , , , , , uint128 liquidity, , , , ) = ICamelotVault(vault).positionManager().positions(positionNft);
        (uint256 baseAmount0, uint256 baseAmount1) = ICamelotVault(vault).helper().liquidityToTokenAmounts(
            positionNft,
            sqrtRatioX96,
            liquidity
        );

        amounts[0] -= baseAmount0;
        amounts[1] -= baseAmount1;
    }
}

