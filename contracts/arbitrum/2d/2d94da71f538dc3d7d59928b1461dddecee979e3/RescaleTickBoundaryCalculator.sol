// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IController.sol";
import "./IStrategyInfo.sol";
import "./IRescaleTickBoundaryCalculator.sol";
import "./LiquidityNftHelper.sol";
import "./Constants.sol";

/// @dev verified, public contract
contract RescaleTickBoundaryCalculator is IRescaleTickBoundaryCalculator {
    function verifyAndGetNewRescaleTickBoundary(
        bool wasInRange,
        int24 lastRescaleTick,
        address strategyAddress,
        address controllerAddress
    )
        public
        view
        returns (bool allowRescale, int24 newTickUpper, int24 newTickLower)
    {
        // Get Tick Info
        (
            int24 tickSpacing,
            int24 currentTick,
            int24 currentTickLower,
            int24 currentTickUpper
        ) = getTickInfo(strategyAddress);

        // Verify Not In Range (Exclude Exact Boundary)
        if (
            !(currentTick < currentTickLower || currentTick > currentTickUpper)
        ) {
            return (false, 0, 0);
        }

        // Get Rescale Info and Verify
        if (tickSpacing == 1) {
            allowRescale = isRescaleAllowedWithOneTickSpacing(
                strategyAddress,
                controllerAddress,
                currentTick,
                currentTickLower,
                currentTickUpper
            );
        } else {
            allowRescale = isRescaleAllowedWithNonOneTickSpacing(
                wasInRange,
                lastRescaleTick,
                strategyAddress,
                controllerAddress,
                tickSpacing,
                currentTick,
                currentTickLower,
                currentTickUpper
            );
        }

        // Calculate newTickUpper & newTickLower
        if (!allowRescale) {
            return (false, 0, 0);
        } else {
            if (tickSpacing == 1) {
                (
                    newTickLower,
                    newTickUpper
                ) = calculateOneTickSpacingRescaleTickBoundary(
                    strategyAddress,
                    controllerAddress,
                    currentTick,
                    currentTickLower
                );
            } else {
                (
                    newTickLower,
                    newTickUpper
                ) = calculateNonOneTickSpacingRescaleTickBoundary(
                    strategyAddress,
                    controllerAddress,
                    tickSpacing,
                    currentTick,
                    currentTickLower
                );
            }
        }

        // Verify Rescale Result
        if (
            currentTickUpper == newTickUpper && currentTickLower == newTickLower
        ) {
            return (false, newTickUpper, newTickLower);
        } else {
            return (true, newTickUpper, newTickLower);
        }
    }

    function isRescaleAllowedWithOneTickSpacing(
        address strategyAddress,
        address controllerAddress,
        int24 currentTick,
        int24 currentTickLower,
        int24 currentTickUpper
    ) internal view returns (bool allowRescale) {
        // Get Rescale Info
        (
            int24 tickSpreadUpper,
            int24 tickSpreadLower,
            ,
            ,
            int24 tickGapUpper,
            int24 tickGapLower
        ) = getRescaleInfo(strategyAddress, controllerAddress);

        // Verify Rescale Related Variables
        require(tickSpreadUpper > 1, "tickSpreadUpper <= 1");
        require(tickSpreadLower > 1, "tickSpreadLower <= 1");
        require(tickGapUpper > 1, "tickGapUpper <= 1");
        require(tickGapLower > 1, "tickGapLower <= 1");

        // Verify Rescale Condition
        if (
            currentTick < (currentTickLower - tickGapLower) ||
            currentTick > (currentTickUpper + tickGapUpper)
        ) {
            return true;
        }
    }

    function isRescaleAllowedWithNonOneTickSpacing(
        bool wasInRange,
        int24 lastRescaleTick,
        address strategyAddress,
        address controllerAddress,
        int24 tickSpacing,
        int24 currentTick,
        int24 currentTickLower,
        int24 currentTickUpper
    ) internal view returns (bool allowRescale) {
        // Get Rescale Info
        (
            int24 tickSpreadUpper,
            int24 tickSpreadLower,
            int24 tickBoundaryOffset,
            int24 rescaleTickBoundaryOffset,
            ,

        ) = getRescaleInfo(strategyAddress, controllerAddress);

        // Verify Rescale Related Variables
        require(tickSpreadUpper >= 0, "tickSpreadUpper < 0");
        require(tickSpreadLower >= 0, "tickSpreadLower < 0");
        require(tickBoundaryOffset >= 0, "tickBoundaryOffset < 0");
        require(
            rescaleTickBoundaryOffset >= 0,
            "rescaleTickBoundaryOffset < 0"
        );

        // Verify Rescale Parameter
        if (
            (lastRescaleTick > currentTickUpper &&
                currentTick < currentTickLower) ||
            (lastRescaleTick < currentTickLower &&
                currentTick > currentTickUpper)
        ) {
            require(wasInRange, "wasInRange parameter error");
        }

        // Verify Rescale Condition
        if (wasInRange) {
            if (
                currentTick <
                currentTickLower - (tickBoundaryOffset * tickSpacing) ||
                currentTick >
                currentTickUpper + (tickBoundaryOffset * tickSpacing)
            ) {
                return true;
            }
        } else {
            if (
                (currentTick < currentTickLower &&
                    currentTick < lastRescaleTick) ||
                (currentTick > currentTickUpper &&
                    currentTick > lastRescaleTick)
            ) {
                return true;
            }
        }
    }

    function calculateOneTickSpacingRescaleTickBoundary(
        address strategyAddress,
        address controllerAddress,
        int24 currentTick,
        int24 currentTickLower
    ) internal view returns (int24 newTickLower, int24 newTickUpper) {
        (int24 tickSpreadUpper, int24 tickSpreadLower, , , , ) = getRescaleInfo(
            strategyAddress,
            controllerAddress
        );

        if (currentTick < currentTickLower) {
            newTickLower = currentTick + 1;
            newTickUpper = newTickLower + tickSpreadLower;
        } else {
            newTickUpper = currentTick;
            newTickLower = newTickUpper - tickSpreadUpper;
        }
    }

    function calculateNonOneTickSpacingRescaleTickBoundary(
        address strategyAddress,
        address controllerAddress,
        int24 tickSpacing,
        int24 currentTick,
        int24 currentTickLower
    ) internal view returns (int24 newTickLower, int24 newTickUpper) {
        (
            int24 tickSpreadUpper,
            int24 tickSpreadLower,
            ,
            int24 rescaleTickBoundaryOffset,
            ,

        ) = getRescaleInfo(strategyAddress, controllerAddress);

        int24 tickSpread;
        if (currentTick < currentTickLower) {
            tickSpread = tickSpreadLower;
        } else {
            tickSpread = tickSpreadUpper;
        }
        int24 tickDistance = (tickSpread == 0)
            ? tickSpacing
            : (2 * tickSpread * tickSpacing);

        if (currentTick < currentTickLower) {
            newTickLower =
                LiquidityNftHelper.ceilingTick(currentTick, tickSpacing) +
                rescaleTickBoundaryOffset *
                tickSpacing;
            newTickUpper = newTickLower + tickDistance;
        } else {
            newTickUpper =
                LiquidityNftHelper.floorTick(currentTick, tickSpacing) -
                rescaleTickBoundaryOffset *
                tickSpacing;
            newTickLower = newTickUpper - tickDistance;
        }
    }

    function getRescaleInfo(
        address strategyAddress,
        address controllerAddress
    )
        internal
        view
        returns (
            int24 tickSpreadUpper,
            int24 tickSpreadLower,
            int24 tickBoundaryOffset,
            int24 rescaleTickBoundaryOffset,
            int24 tickGapUpper,
            int24 tickGapLower
        )
    {
        tickSpreadUpper = IController(controllerAddress).tickSpreadUpper(
            strategyAddress
        );
        tickSpreadLower = IController(controllerAddress).tickSpreadLower(
            strategyAddress
        );
        tickBoundaryOffset = IController(controllerAddress).tickBoundaryOffset(
            strategyAddress
        );
        rescaleTickBoundaryOffset = IController(controllerAddress)
            .rescaleTickBoundaryOffset(strategyAddress);
        tickGapUpper = IController(controllerAddress).tickGapUpper(
            strategyAddress
        );
        tickGapLower = IController(controllerAddress).tickGapLower(
            strategyAddress
        );
    }

    function getTickInfo(
        address strategyAddress
    )
        internal
        view
        returns (
            int24 tickSpacing,
            int24 currentTick,
            int24 currentTickLower,
            int24 currentTickUpper
        )
    {
        tickSpacing = IStrategyInfo(strategyAddress).tickSpacing();
        (currentTick, currentTickLower, currentTickUpper) = LiquidityNftHelper
            .getTickInfo(
                IStrategyInfo(strategyAddress).liquidityNftId(),
                Constants.UNISWAP_V3_FACTORY_ADDRESS,
                Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
            );
    }
}

