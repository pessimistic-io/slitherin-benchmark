// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

/// @notice Minimal interface for Bank.
/// @author Romuald Hog.
interface IBank {
    /// @notice Payouts a winning bet, and allocate the house edge fee.
    /// @param user Address of the gamer.
    /// @param token Address of the token.
    /// @param profit Number of tokens to be sent to the gamer.
    /// @param fees Bet amount and bet profit fees amount.
    function payout(
        address user,
        address token,
        uint256 profit,
        uint256 fees
    ) external payable;

    /// @notice Accounts a loss bet.
    /// @dev In case of an ERC20, the bet amount should be transfered prior to this tx.
    /// @dev In case of the gas token, the bet amount is sent along with this tx.
    /// @param tokenAddress Address of the token.
    /// @param amount Loss bet amount.
    /// @param fees Bet amount and bet profit fees amount.
    function cashIn(
        address tokenAddress,
        uint256 amount,
        uint256 fees
    ) external payable;

    function getTokenOwner(address token) external view returns (address);

    function getBetRequirements(address token, uint256 multiplier)
        external
        view
        returns (
            bool,
            uint64,
            uint256,
            uint256
        );
}

