// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./Initializable.sol";
import "./ICoreUtilities.sol";

/**
 * @title CoreUtilities
 * @notice CoreUtilities is a smart contract that provides utility functions for token swapping, fee calculation, and round data validation.
 */
contract CoreUtilities is ICoreUtilities, Ownable, Initializable {
    using SafeERC20 for IERC20Stable;

    uint256 public constant DIVIDER = 1 ether;

    ICoreConfiguration public configuration;

    /**
     * @notice Initializes the contract with the given configuration address.
     * @param configuration_ The address of the configuration contract to use.
     * @return A boolean indicating whether the initialization was successful.
     */
    function initialize(address configuration_) external onlyOwner initializer returns (bool) {
        require(configuration_ != address(0), "CoreUtilities: Configuration is zero address");
        configuration = ICoreConfiguration(configuration_);
        return true;
    }

    /**
     * @notice Swaps stable tokens for another token using the configured swapper connector.
     * @param recipient The address to send the swapped tokens to.
     * @param winnerTotalAmount The total amount of tokens to be won in the current round.
     * @return amountIn The amount of stable tokens used for the swap.
     */
    function swap(address recipient, uint256 winnerTotalAmount) external returns (uint256 amountIn) {
        (ISwapperConnector swapperConnector, bytes memory path) = configuration.swapper();
        (, , , IERC20Stable stable, ) = configuration.immutableConfiguration();
        (, uint256 autoResolveFee_, , ) = configuration.feeConfiguration();
        amountIn = swapperConnector.getAmountIn(path, autoResolveFee_);
        stable.safeTransferFrom(msg.sender, address(this), amountIn);
        if (amountIn > winnerTotalAmount) amountIn = winnerTotalAmount;
        stable.approve(address(swapperConnector), amountIn);
        swapperConnector.swap(path, address(stable), amountIn, recipient);
    }

    /**
     * @notice Calculates the stable fee for a given amount and fee percentage, taking into account the user's affiliation status.
     * @param affiliationUser The address of the user to check for affiliation status.
     * @param amount The amount to calculate the fee for.
     * @param fee The fee percentage to apply.
     * @return affiliationUserData_ A struct containing the user's affiliation data.
     * @return fee_ The calculated stable fee for the given amount and fee percentage.
     */
    function calculateStableFee(
        address affiliationUser,
        uint256 amount,
        uint256 fee
    ) external view returns (AffiliationUserData memory affiliationUserData_, uint256 fee_) {
        (, IFoxifyAffiliation affiliation, , , ) = configuration.immutableConfiguration();
        (uint256 bronze, uint256 silver, uint256 gold) = configuration.discount();
        affiliationUserData_.activeId = affiliation.usersActiveID(affiliationUser);
        affiliationUserData_.team = affiliation.usersTeam(affiliationUser);
        affiliationUserData_.nftData = affiliation.data(affiliationUserData_.activeId);
        IFoxifyAffiliation.Level level = affiliationUserData_.nftData.level;
        if (level == IFoxifyAffiliation.Level.BRONZE) {
            affiliationUserData_.discount = bronze;
        } else if (level == IFoxifyAffiliation.Level.SILVER) {
            affiliationUserData_.discount = silver;
        } else if (level == IFoxifyAffiliation.Level.GOLD) {
            affiliationUserData_.discount = gold;
        }
        fee_ = ((amount * fee * DIVIDER) - (affiliationUserData_.discount * amount * fee)) / (DIVIDER * DIVIDER);
    }

    /**
     * @notice Validates the round data for a given oracle and round ID for AutoResolve execution.
     * @param oracle The address of the oracle to use.
     * @param endTime The position end time.
     * @return price The price of the round if it is valid.
     */
    function getAndValidateRoundForAccept(address oracle, uint256 endTime) external view returns (uint256 price) {
        IOracleConnector oracle_ = IOracleConnector(oracle);
        require(oracle_.validateTimestamp(endTime), "CoreUtilities: Position end time not supported");
        try oracle_.latestRoundData() returns (
            uint256 roundId,
            uint256 answer,
            uint256,
            uint256 updatedAtRound,
            uint256 answeredInRound
        ) {
            _validateRoundData(roundId, answer, updatedAtRound, answeredInRound);
            price = answer;
        } catch {
            revert("CoreUtilities: Acceptance oracle error");
        }
    }

    /**
     * @notice Validates the round data for a given oracle and round ID for AutoResolve execution.
     * @param roundId The round ID to validate.
     * @param endTime The position end time.
     * @param oracle The address of the oracle to use.
     * @return invalidRound A boolean indicating whether the round is invalid.
     * @return price The price of the round if it is valid.
     */
    function getAndValidateRoundForAutoResolve(
        uint256 roundId,
        uint256 endTime,
        address oracle
    ) external view returns (bool invalidRound, uint256 price) {
        IOracleConnector oracle_ = IOracleConnector(oracle);
        require(oracle_.latestRound() >= roundId, "CoreUtilities: Invalid round id");
        invalidRound = oracle_.paused() || !configuration.oraclesContains(oracle);
        if (!invalidRound) {
            try oracle_.getRoundData(roundId) returns (
                uint256 roundID,
                uint256 answer,
                uint256 startedAtCurrentRound,
                uint256 roundTimestamp,
                uint256 answeredInRound
            ) {
                try oracle_.getRoundData(roundId + 1) returns (
                    uint256,
                    uint256,
                    uint256 startedAtNextRound,
                    uint256,
                    uint256
                ) {
                    _validateRoundData(roundID, answer, roundTimestamp, answeredInRound);
                    require(
                        startedAtCurrentRound <= endTime && (startedAtNextRound > endTime || startedAtNextRound == 0),
                        "CoreUtilities: Invalid round id"
                    );
                    price = answer;
                } catch {
                    invalidRound = true;
                }
            } catch {
                invalidRound = true;
            }
        }
    }

    function _validateRoundData(
        uint256 roundId,
        uint256 answer,
        uint256 updatedAtRound,
        uint256 answeredInRound
    ) private pure {
        require(answer > 0, "CoreUtilities: Invalid round price");
        require(answeredInRound >= roundId, "CoreUtilities: Invalid answered round");
        require(updatedAtRound != 0, "CoreUtilities: Invalid round timestamp");
    }
}

