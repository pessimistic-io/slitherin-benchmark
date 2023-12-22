// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { SafeCast } from "./SafeCast.sol";
import { Solarray } from "./Solarray.sol";

/// @title NettingMath
/// @author Umami DAO
/// @notice Contains math for validating a set of netted parameters
contract NettingMath {
    // STORAGE
    // ------------------------------------------------------------------------------------------

    struct NettedParams {
        uint256 vaultCumulativeGlpTvl;
        uint256[5] glpComposition;
        uint256 nettedThreshold;
    }

    struct NettedState {
        uint256[5] glpHeld;
        int256[5] externalPositions;
    }

    uint256 public immutable SCALE = 1e18;
    uint256 public immutable BIPS = 10_000;

    // PUBLIC
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Calculates the GLP exposure and vault ratio for each position
     * @param nettingState The current netted state containing GLP held and external positions
     * @param _vaultCumulativeGlpTvl The vault's cumulative GLP TVL
     * @param _glpComposition The GLP composition as an array of five uint256 values
     * @param externalPositions A 5x5 matrix of external positions
     * @return glpExposure An array of GLP exposure for each position
     * @return vaultRatio An array of vault ratios for each position
     */
    function vaultDeltaAdjustment(
        NettedState memory nettingState,
        uint256 _vaultCumulativeGlpTvl,
        uint256[5] memory _glpComposition,
        int256[5][5] memory externalPositions,
        uint256 _threshold
    ) public pure returns (uint256[5] memory glpExposure, uint256[5] memory vaultRatio) {
        int256 rowHedgeSum;
        uint256 zeroDivisor;
        for (uint256 i = 0; i < nettingState.glpHeld.length; i++) {
            glpExposure[i] = _vaultCumulativeGlpTvl * _glpComposition[i] / SCALE;

            if (nettingState.externalPositions[i] < 0) {
                glpExposure[i] += uint256(-nettingState.externalPositions[i]);
            } else {
                // CASE: glp allocation close to 0
                if (glpExposure[i] < uint256(nettingState.externalPositions[i])) {
                    glpExposure[i] = uint256(nettingState.externalPositions[i]) - glpExposure[i];
                } else {
                    glpExposure[i] -= uint256(nettingState.externalPositions[i]);
                }
            }

            // subtract/add vault over/under allocation amount
            rowHedgeSum = Solarray.arraySum(externalPositions[i]);
            if (rowHedgeSum < 0) {
                glpExposure[i] -= uint256(-rowHedgeSum);
            } else {
                glpExposure[i] += uint256(rowHedgeSum);
            }

            if (nettingState.glpHeld[i] == 0) {
                if (_vaultCumulativeGlpTvl == 0 && glpExposure[i] == 0) {
                    vaultRatio[i] = SCALE;
                } else {
                    zeroDivisor = _vaultCumulativeGlpTvl != 0 ? _vaultCumulativeGlpTvl : glpExposure[i];
                    vaultRatio[i] = SCALE + (glpExposure[i] * SCALE / zeroDivisor);
                }
            } else {
                vaultRatio[i] = glpExposure[i] * SCALE / nettingState.glpHeld[i];
            }
        }
    }

    /**
     * @notice Calculates the netted and exposure matrices for the given positions and GLP composition
     * @param externalPositions A 5x5 matrix of external positions
     * @param glpComposition The GLP composition as an array of five uint256 values
     * @param glpHeldDollars The GLP held as an array of five uint256 values
     * @return nettedMatrix A 5x5 matrix of netted positions
     * @return exposureMatrix A 5x5 matrix of exposures
     */
    function calculateNettedPositions(
        int256[5][5] memory externalPositions,
        uint256[5] memory glpComposition,
        uint256[5] memory glpHeldDollars
    ) public pure returns (int256[5][5] memory nettedMatrix, int256[5][5] memory exposureMatrix) {
        int256[5] memory vaultGlpExposure;
        for (uint256 idx = 0; idx < externalPositions.length; idx++) {
            vaultGlpExposure = _vaultExposureInt(glpHeldDollars[idx], glpComposition);
            exposureMatrix[idx] = vaultGlpExposure;
            nettedMatrix[idx] = _nettedPositionRow(externalPositions[idx], vaultGlpExposure, idx);
        }
    }

    /**
     * @notice Determines whether the given netted state is within the netted threshold
     * @param nettingState The current netted state containing GLP held and external positions
     * @param params The netted parameters containing vault cumulative GLP TVL, GLP composition, and netted threshold
     * @param externalPositions A 5x5 matrix of external positions
     * @return netted A boolean indicating whether the given netted state is within the netted threshold
     */
    function isNetted(
        NettedState memory nettingState,
        NettedParams memory params,
        int256[5][5] memory externalPositions
    ) public pure returns (bool netted) {
        uint256[5] memory glpExposure;
        uint256[5] memory vaultRatio;
        // if the vault is 0'd out
        if (params.vaultCumulativeGlpTvl < 1e18) return true;
        // note positions are NOT scaled up by a factor x to account for counterparty affect when using gmx.
        // here we take the unscaled externalPositions as input
        (glpExposure, vaultRatio) = vaultDeltaAdjustment(
            nettingState, params.vaultCumulativeGlpTvl, params.glpComposition, externalPositions, params.nettedThreshold
        );

        uint256 upper = SCALE * (BIPS + params.nettedThreshold) / BIPS;
        uint256 lower = SCALE * (BIPS - params.nettedThreshold) / BIPS;
        netted = true;
        for (uint256 i = 0; i < vaultRatio.length; i++) {
            if (vaultRatio[i] > upper || vaultRatio[i] < lower) {
                netted = false;
            }
        }
    }

    // INTERNAL
    // ------------------------------------------------------------------------------------------

    function _nettedPositionRow(int256[5] memory _hedgeAllocation, int256[5] memory _glpAllocation, uint256 _vaultIdx)
        internal
        pure
        returns (int256[5] memory nettedPositions)
    {
        for (uint256 i = 0; i < _hedgeAllocation.length; i++) {
            if (i == _vaultIdx) {
                nettedPositions[i] = _glpAllocation[i];
            } else {
                nettedPositions[i] = _glpAllocation[i] - _hedgeAllocation[i];
            }
        }
    }

    function _vaultExposureInt(uint256 glpHeldDollars, uint256[5] memory glpComposition)
        internal
        pure
        returns (int256[5] memory exposure)
    {
        for (uint256 i = 0; i < glpComposition.length; i++) {
            exposure[i] = SafeCast.toInt256((glpHeldDollars * glpComposition[i]) / 1e18);
        }
    }
}

