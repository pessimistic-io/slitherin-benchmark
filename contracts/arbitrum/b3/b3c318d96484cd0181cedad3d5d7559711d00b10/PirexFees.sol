// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {SafeTransferLib} from "./SafeTransferLib.sol";
import {ERC20} from "./ERC20.sol";

contract PirexFees {
    using SafeTransferLib for ERC20;

    // Denominator used when calculating the fee distribution percent
    // E.g. if the treasuryFeePercent were set to 50, then the treasury's
    // percent share of the fee distribution would be 50% (50 / 100)
    uint8 public constant FEE_PERCENT_DENOMINATOR = 100;

    // Maximum treasury fee percent
    uint8 public constant MAX_TREASURY_FEE_PERCENT = 75;

    // Multisig addresses which have the ability to set the fee recipient addresses
    // The treasuryManager also has the ability to update treasuryFeePercent
    address public immutable treasuryManager;
    address public immutable contributorsManager;

    // Configurable treasury percent share of fees (default is max)
    // Currently, there are only two fee recipients, so we only need to
    // store the percent of one recipient to derive the other
    uint8 public treasuryFeePercent = MAX_TREASURY_FEE_PERCENT;

    // Configurable fee recipient addresses
    address public treasury;
    address public contributors;

    event SetTreasury(address _treasury);
    event SetContributors(address _contributors);
    event SetTreasuryFeePercent(uint8 _treasuryFeePercent);
    event DistributeFees(
        ERC20 indexed token,
        uint256 distribution,
        uint256 treasuryDistribution,
        uint256 contributorsDistribution
    );

    error ZeroAddress();
    error Unauthorized();
    error InvalidFeePercent();

    /**
        @param  _treasury             address  Redacted treasury
        @param  _contributors         address  Pirex contributor distribution contract
        @param  _treasuryManager      address  Redacted treasury manager (multisig)
        @param  _contributorsManager  address  Pirex contributor manager (multisig)
     */
    constructor(
        address _treasury,
        address _contributors,
        address _treasuryManager,
        address _contributorsManager
    ) {
        if (_treasury == address(0)) revert ZeroAddress();
        if (_contributors == address(0)) revert ZeroAddress();
        if (_treasuryManager == address(0)) revert ZeroAddress();
        if (_contributorsManager == address(0)) revert ZeroAddress();

        treasury = _treasury;
        contributors = _contributors;
        treasuryManager = _treasuryManager;
        contributorsManager = _contributorsManager;
    }

    /**
        @notice Update the treasury address
        @param  _treasury  address  Fee recipient address
     */
    function setTreasury(address _treasury) external {
        if (msg.sender != treasuryManager) revert Unauthorized();
        if (_treasury == address(0)) revert ZeroAddress();

        treasury = _treasury;

        emit SetTreasury(_treasury);
    }

    /**
        @notice Update the contributors address
        @param  _contributors  address  Fee recipient address
     */
    function setContributors(address _contributors) external {
        if (msg.sender != contributorsManager) revert Unauthorized();
        if (_contributors == address(0)) revert ZeroAddress();

        contributors = _contributors;

        emit SetContributors(_contributors);
    }

    /**
        @notice Set treasury fee percent
        @param  _treasuryFeePercent  uint8  Treasury fee percent
     */
    function setTreasuryFeePercent(uint8 _treasuryFeePercent) external {
        if (msg.sender != treasuryManager) revert Unauthorized();

        // Treasury fee percent should never exceed the pre-configured max
        if (_treasuryFeePercent > MAX_TREASURY_FEE_PERCENT)
            revert InvalidFeePercent();

        treasuryFeePercent = _treasuryFeePercent;

        emit SetTreasuryFeePercent(_treasuryFeePercent);
    }

    /**
        @notice Distribute fees
        @param  token  address  Fee token
     */
    function distributeFees(ERC20 token) external {
        uint256 distribution = token.balanceOf(address(this));
        uint256 treasuryDistribution = (distribution * treasuryFeePercent) /
            FEE_PERCENT_DENOMINATOR;
        uint256 contributorsDistribution = distribution - treasuryDistribution;

        emit DistributeFees(
            token,
            distribution,
            treasuryDistribution,
            contributorsDistribution
        );

        // Favoring push over pull to reduce accounting complexity for different tokens
        token.safeTransfer(treasury, treasuryDistribution);
        token.safeTransfer(contributors, contributorsDistribution);
    }
}

