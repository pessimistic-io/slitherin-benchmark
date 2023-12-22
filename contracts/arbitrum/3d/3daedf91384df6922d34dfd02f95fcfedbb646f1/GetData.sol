// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "./IERC20.sol";
import "./DCAconfig.sol";
import "./ERC2771Context.sol";

contract GetData is DCAconfig, ERC2771Context {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(
        address _WETH,
        address _chainLinkPriceFeed,
        address _forwarder,
        uint256 _gasOneSwap
    )
        DCAconfig(_WETH, _chainLinkPriceFeed, _forwarder, _gasOneSwap)
        ERC2771Context(_forwarder)
    {}

    /**
     * @dev Checks if a given token is ETH (Ethereum).
     * @param token The token to check.
     * @return A boolean indicating whether the token is ETH.
     */
    function isETH(IERC20 token) internal pure returns (bool) {
        return (token == IERC20(ETH));
    }

    /**
     * @dev Retrieves the schedules of all users.
     * @return retrieveUsers An array of user addresses.
     * @return totalSchedules An array of total schedules per user.
     */
    function getAllUsersSchedules()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256 length = _userAddresses.length();
        address[] memory retrieveUsers = new address[](length);
        uint256[] memory totalSchedules = new uint256[](length);

        for (uint256 i; i < length; i++) {
            retrieveUsers[i] = _userAddresses.at(i);
            totalSchedules[i] = userToDcaSchedules[retrieveUsers[i]].length;
        }
        return (retrieveUsers, totalSchedules);
    }

    /**
     * @dev Calculates the number of trade executions between two dates.
     * @param _tradeFrequency The frequency of trades in seconds.
     * @param _startDate The start date of the calculation.
     * @param _endDate The end date of the calculation.
     * @return The calculated number of trade executions.
     * @notice This function assumes valid input and does not perform validation checks.
     */
    function calculateExecutions(
        uint256 _tradeFrequency,
        uint256 _startDate,
        uint256 _endDate
    ) public pure returns (uint256) {
        require(_endDate > _startDate, "Invalid dates!");
        require((_endDate - _startDate) >= _tradeFrequency, "Invalid exec!");

        return ((_endDate - _startDate) / (_tradeFrequency));
    }

    /**
     * @dev Retrieves the dollar-cost averaging schedules associated with a user.
     * @param user The user's address.
     * @return An array of DcaSchedule objects.
     */
    function getUserSchedules(
        address user
    ) public view returns (DcaSchedule[] memory) {
        return userToDcaSchedules[user];
    }

    /**
     * @dev Calculates the available free token balance for the caller.
     * @param _tokenAddress The address of the token.
     * @return The available free token balance.
     */
    function getFreeTokenBalance(
        address _tokenAddress
    ) public view returns (int256) {
        DcaSchedule[] memory allUserSchedules = getUserSchedules(_msgSender());

        int256 totalUserDeposit = int256(
            userTokenBalances[_msgSender()][_tokenAddress]
        );
        int256 freeDepositBal = 0;

        if (allUserSchedules.length == 0) {
            freeDepositBal = totalUserDeposit;
        } else {
            int256 committedBal = 0;

            for (uint256 i; i < allUserSchedules.length; i++) {
                if (
                    allUserSchedules[i].sellToken == _tokenAddress &&
                    allUserSchedules[i].isActive == true
                ) {
                    committedBal += int256(allUserSchedules[i].remainingBudget);
                }
            }

            freeDepositBal = totalUserDeposit - committedBal;
        }

        return freeDepositBal;
    }

    /**
     * @dev Retrieves all token balances of the calling user, along with their free balances.
     * @return retrieveUserTokens An array of token addresses.
     * @return retrieveUserBalances An array of token balances of the user.
     * @return retrieveFreeBalances An array of free token balances of the user.
     */
    function getUserAllTokenBalances()
        external
        view
        returns (address[] memory, uint256[] memory, int256[] memory)
    {
        uint256 length = getUserTokensLength();
        address[] memory retrieveUserTokens = new address[](length);
        uint256[] memory retrieveUserBalances = new uint256[](length);
        int256[] memory retrieveFreeBalances = new int256[](length);

        for (uint256 i; i < length; i++) {
            retrieveUserTokens[i] = getUserTokenAddressAt(i);
            retrieveUserBalances[i] = userTokenBalances[_msgSender()][
                retrieveUserTokens[i]
            ];
            retrieveFreeBalances[i] = getFreeTokenBalance(
                retrieveUserTokens[i]
            );
        }
        return (retrieveUserTokens, retrieveUserBalances, retrieveFreeBalances);
    }

    /**
     * @dev Calculates the required deposit amount for a given trade setup.
     * @param _tradeAmount The trade amount.
     * @param _tradeFrequency The trade frequency in seconds.
     * @param _startDate The start date of the trade.
     * @param _endDate The end date of the trade.
     * @param _sellToken The address of the token being sold.
     * @return neededDeposit The calculated needed deposit amount.
     */
    function calculateDeposit(
        uint256 _tradeAmount,
        uint256 _tradeFrequency,
        uint256 _startDate,
        uint256 _endDate,
        address _sellToken
    ) public view returns (uint256) {
        uint256 totalExecutions = calculateExecutions(
            _tradeFrequency,
            _startDate,
            _endDate
        );

        require(totalExecutions > 0, "Invalid!");
        require(_tradeAmount > 0, "Not 0!");

        int256 totalBudget = int256(_tradeAmount * totalExecutions);
        int256 gotFreeTokenBalance = getFreeTokenBalance(_sellToken);

        uint256 neededDeposit = 0;

        if (totalBudget - gotFreeTokenBalance > 0) {
            neededDeposit = uint256(totalBudget - gotFreeTokenBalance);
        }

        return neededDeposit;
    }

    /**
     * @dev Retrieves the number of token addresses associated with the calling user.
     * @return The number of token addresses.
     */
    function getUserTokensLength() internal view returns (uint256) {
        return _userTokens[_msgSender()].length();
    }

    /**
     * @dev Retrieves the token address associated with the calling user at a specific index.
     * @param index The index of the token address.
     * @return token The token address at the given index.
     */
    function getUserTokenAddressAt(
        uint256 index
    ) internal view returns (address token) {
        return _userTokens[msg.sender].at(index);
    }

    function gasUsedForTransaction() public view returns (uint256) {
        return gasOneSwap;
    }
}

