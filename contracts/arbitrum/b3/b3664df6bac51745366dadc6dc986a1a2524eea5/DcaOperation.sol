// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AccessControl} from "./AccessControl.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Context} from "./Context.sol";
import {IWETH} from "./IWETH.sol";
import "./GetData.sol";
import "./Error.sol";
import "./ChainLinkFeed.sol";
import "./AllowedToken.sol";
import "./console.sol";

contract DcaOperation is
    ReentrancyGuard,
    AccessControl,
    GetData,
    DataConsumerV3,
    AllowedToken
{
    bytes32 public constant RUNNER_ROLE = keccak256("RUNNER_ROLE");

    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(
        address _WETH,
        address _chainLinkPriceFeed,
        address _forwarder,
        uint256 _gasOneSwap
    )
        GetData(_WETH, _chainLinkPriceFeed, _forwarder, _gasOneSwap)
        DataConsumerV3(_chainLinkPriceFeed)
    {
        _grantRole(RUNNER_ROLE, _msgSender());
    }

    function setPlatformFee(uint16 fee) public onlyRole(RUNNER_ROLE) {
        platformFee = fee;
    }

    function _msgSender()
        internal
        view
        override(Context, ERC2771Context)
        returns (address sender)
    {
        sender = ERC2771Context._msgSender();
    }

    function _msgData()
        internal
        view
        override(Context, ERC2771Context)
        returns (bytes calldata)
    {
        return ERC2771Context._msgData();
    }

    /**
     * @dev Deletes a specific dollar-cost averaging schedule of the calling user.
     * @param _dcaScheduleId The ID of the schedule to be deleted.
     */
    function deleteSchedule(uint256 _dcaScheduleId) external {
        withdrawFunds(
            userToDcaSchedules[_msgSender()][_dcaScheduleId].sellToken,
            userToDcaSchedules[_msgSender()][_dcaScheduleId].remainingBudget
        );
        delete userToDcaSchedules[_msgSender()][_dcaScheduleId];
        userToDcaSchedules[_msgSender()][_dcaScheduleId] = userToDcaSchedules[
            _msgSender()
        ][userToDcaSchedules[_msgSender()].length - 1];
        userToDcaSchedules[_msgSender()].pop();

        removeUserFromSet();

        delete userSwapHistory[_msgSender()][_dcaScheduleId];
    }

    /**
     * @dev Adds the calling user to the set of users.
     */
    function addUser() private {
        _userAddresses.add(_msgSender());
    }

    /**
     * @dev Removes the calling user from the set of users if they have no more schedules.
     */
    function removeUserFromSet() internal {
        if (userToDcaSchedules[_msgSender()].length == 0) {
            _userAddresses.remove(_msgSender());
        }
    }

    /**
     * @dev Adds a token to the set of tokens for a specific user.
     * @param _user The user's address.
     * @param _token The token's address.
     */
    function addUserToken(address _user, address _token) internal {
        if (!_userTokens[_user].contains(_token)) {
            _userTokens[_user].add(_token);
        }
    }

    receive() external payable {}

    fallback() external payable {}

    /**
     * @dev Deposits funds (either ETH or ERC20 tokens) into the user's balance.
     * @param _tokenAmount The amount of tokens to deposit.
     * @notice This function can only be called by the user and reentrancy is guarded against.
     */
    function depositFunds(
        uint256 _tokenAmount,
        uint256 _tradeFrequency,
        address _buyToken,
        address _sellToken,
        uint256 _startDate,
        uint256 _endDate
    ) internal {
        if (!tokenCheck(_sellToken)) revert Token_Not_Allowed();
        uint256 depositAmount;
        IERC20 token = IERC20(_sellToken);
        uint256 preBalance = token.balanceOf(address(this));
        token.transferFrom(_msgSender(), address(this), _tokenAmount);
        uint256 postBalance = token.balanceOf(address(this));
        depositAmount =
            ((postBalance - preBalance) * (1000 - platformFee)) /
            1000;
        token.transfer(owner(), ((postBalance - preBalance) - depositAmount));

        userTokenBalances[_msgSender()][_sellToken] =
            userTokenBalances[_msgSender()][_sellToken] +
            depositAmount;

        addUserToken(_msgSender(), _sellToken);

        uint256 totalExec = calculateExecutions(
            _tradeFrequency,
            _startDate,
            _endDate
        );
        uint256 tradeAmount = depositAmount / totalExec;

        createDcaSchedule(
            _tradeFrequency,
            tradeAmount,
            _buyToken,
            _sellToken,
            _startDate,
            _endDate
        );

        emit FundsDeposited(_msgSender(), _sellToken, depositAmount);
    }

    function depositMultipleFunds(
        uint256[] memory _tokenAmounts,
        uint256 _tradeFrequency,
        address[] memory _buyTokens,
        address _sellToken,
        uint256 _startDate,
        uint256 _endDate
    ) public nonReentrant {
        if (_tokenAmounts.length != _buyTokens.length) revert not_equal();
        for (uint i = 0; i < _tokenAmounts.length; ++i) {
            depositFunds(
                _tokenAmounts[i],
                _tradeFrequency,
                _buyTokens[i],
                _sellToken,
                _startDate,
                _endDate
            );
        }
    }

    /**
     * @dev Withdraws funds (either ETH or ERC20 tokens) from the user's balance.
     * @param _tokenAddress The address of the token to withdraw.
     * @param _tokenAmount The amount of tokens to withdraw.
     * @notice This function can only be called by the user and reentrancy is guarded against.
     */
    function withdrawFunds(
        address _tokenAddress,
        uint256 _tokenAmount
    ) internal nonReentrant {
        uint256 userBalance = userTokenBalances[_msgSender()][_tokenAddress];

        if (userBalance < _tokenAmount) revert more_than_deposited();

        userTokenBalances[_msgSender()][_tokenAddress] -= _tokenAmount;

        IERC20(_tokenAddress).transfer(_msgSender(), _tokenAmount);

        emit FundsWithdrawn(_msgSender(), _tokenAddress, _tokenAmount);
    }

    /**
     * @dev Validates the parameters of a dollar-cost averaging schedule.
     * @param _sellToken The address of the token being sold.
     * @param _tradeAmount The trade amount.
     * @param _tradeFrequency The trade frequency in seconds.
     * @param _startDate The start date of the schedule.
     * @param _endDate The end date of the schedule.
     * @notice This function performs validation checks on the schedule parameters.
     */
    function validateDcaSchedule(
        address _sellToken,
        uint256 _tradeAmount,
        uint256 _tradeFrequency,
        uint256 _startDate,
        uint256 _endDate
    ) public view {
        // require(_sellToken != ETH, "Not supported!");

        uint256 needAmount = calculateDeposit(
            _tradeAmount,
            _tradeFrequency,
            _startDate,
            _endDate,
            _sellToken
        );
        if (needAmount != 0) revert low_balance();
    }

    /**
     * @dev Creates a new dollar-cost averaging schedule.
     * @param _tradeFrequency The frequency of trades in seconds.
     * @param _tradeAmount The amount of tokens to trade in each iteration.
     * @param _buyToken The token to buy.
     * @param _sellToken The token to sell.
     * @param _startDate The start date of the schedule.
     * @param _endDate The end date of the schedule.
     * @notice This function creates a new DCA schedule for the user.
     */
    function createDcaSchedule(
        uint256 _tradeFrequency,
        uint256 _tradeAmount,
        address _buyToken,
        address _sellToken,
        uint256 _startDate,
        uint256 _endDate
    ) internal {
        uint256 totalExec = calculateExecutions(
            _tradeFrequency,
            _startDate,
            _endDate
        );
        uint256 totalBudget = _tradeAmount * totalExec;

        validateDcaSchedule(
            _sellToken,
            _tradeAmount,
            _tradeFrequency,
            _startDate,
            _endDate
        );

        addUser();

        userToDcaSchedules[_msgSender()].push(
            DcaSchedule(
                _tradeFrequency,
                _tradeAmount,
                totalBudget,
                _buyToken,
                _sellToken,
                true,
                [_startDate, 0, _startDate, _endDate],
                0,
                0,
                0
            )
        );

        emit NewUserSchedule(
            userToDcaSchedules[_msgSender()].length - 1,
            _buyToken,
            _sellToken,
            _msgSender()
        );
    }

    /**
     * @dev Updates the user's DCA schedule after a successful trade execution.
     * @param dcaOwner The owner of the DCA schedule.
     * @param scheduleId The ID of the schedule being updated.
     * @param tradeAmounts An array containing sold and bought amounts.
     * @param gasUsed The gas used during the execution.
     * @param currentDateTime The current date and time.
     * @notice This function updates the DCA schedule parameters based on the trade execution.
     */
    function updateUserDCA(
        address dcaOwner,
        uint256 scheduleId,
        uint256[2] memory tradeAmounts,
        uint256 gasUsed,
        uint256 currentDateTime
    ) internal onlyRole(RUNNER_ROLE) {
        uint256 soldAmount = tradeAmounts[0];
        uint256 boughtAmount = tradeAmounts[1];

        userToDcaSchedules[dcaOwner][scheduleId].remainingBudget =
            userToDcaSchedules[dcaOwner][scheduleId].remainingBudget -
            userToDcaSchedules[dcaOwner][scheduleId].tradeAmount;
        userTokenBalances[dcaOwner][
            userToDcaSchedules[dcaOwner][scheduleId].sellToken
        ] =
            userTokenBalances[dcaOwner][
                userToDcaSchedules[dcaOwner][scheduleId].sellToken
            ] -
            userToDcaSchedules[dcaOwner][scheduleId].tradeAmount;

        userToDcaSchedules[dcaOwner][scheduleId].scheduleDates[
                1
            ] = currentDateTime;

        if (userToDcaSchedules[dcaOwner][scheduleId].remainingBudget == 0) {
            userToDcaSchedules[dcaOwner][scheduleId].isActive = false;
        } else {
            uint256 numExec = calculateExecutions(
                userToDcaSchedules[dcaOwner][scheduleId].tradeFrequency,
                userToDcaSchedules[dcaOwner][scheduleId].scheduleDates[2], //nextRun
                userToDcaSchedules[dcaOwner][scheduleId].scheduleDates[3] //endDate
            );

            //next run
            userToDcaSchedules[dcaOwner][scheduleId].scheduleDates[2] =
                currentDateTime +
                userToDcaSchedules[dcaOwner][scheduleId].tradeFrequency;

            //end date
            userToDcaSchedules[dcaOwner][scheduleId].scheduleDates[3] =
                currentDateTime +
                (userToDcaSchedules[dcaOwner][scheduleId].tradeFrequency *
                    numExec);
        }

        userTokenBalances[dcaOwner][
            userToDcaSchedules[dcaOwner][scheduleId].buyToken
        ] =
            userTokenBalances[dcaOwner][
                userToDcaSchedules[dcaOwner][scheduleId].buyToken
            ] +
            boughtAmount;

        userToDcaSchedules[dcaOwner][scheduleId]
            .soldAmount += userToDcaSchedules[dcaOwner][scheduleId].tradeAmount;
        userToDcaSchedules[dcaOwner][scheduleId].boughtAmount += boughtAmount;
        userToDcaSchedules[dcaOwner][scheduleId].totalGas += gasUsed;

        DcaSchedule memory u = userToDcaSchedules[dcaOwner][scheduleId];
        {
            emit BoughtTokens(
                scheduleId,
                u.sellToken,
                u.buyToken,
                soldAmount,
                boughtAmount,
                u.remainingBudget,
                u.isActive,
                u.scheduleDates[2], //startDate, lastRun, nextRun, endDate
                dcaOwner
            );
        }
    }

    /**
     * @dev Executes a DCA run for the specified schedule.
     * @param dcaOwner The owner of the DCA schedule.
     * @param scheduleId The ID of the schedule to execute.
     * @param spender The address that is allowed to spend the tokens.
     * @param swapTarget The address of the contract to perform the swap.
     * @param swapCallData The data for the swap call.
     * @notice This function executes a DCA run based on the schedule's parameters and swaps tokens.
     */
    function runUserDCA(
        address dcaOwner,
        uint256 scheduleId,
        address spender,
        address payable swapTarget,
        bytes calldata swapCallData
    ) external payable nonReentrant onlyRole(RUNNER_ROLE) {
        uint256 currentDateTime = block.timestamp;

        DcaSchedule memory currSchedule = userToDcaSchedules[dcaOwner][
            scheduleId
        ];

        if (currentDateTime < currSchedule.scheduleDates[2]) {
            //startDate, lastRun, nextRun, endDate
            revert time_not_match();
        }

        if (currSchedule.isActive == false) revert not_active();

        if (!(currSchedule.remainingBudget > 0)) revert Schedule_complete();

        if (
            !(userTokenBalances[dcaOwner][currSchedule.sellToken] >=
                currSchedule.tradeAmount)
        ) revert low_balance();

        IWETH sellToken = IWETH(currSchedule.sellToken);
        IERC20 buyToken = IERC20(currSchedule.buyToken);

        uint256 gasUsed = gasUsedForTransaction();

        if (!(currSchedule.sellToken == (WETH))) {
            gasUsed =
                (uint256(getLatestData()) *
                    gasUsed *
                    (10 ** (sellToken.decimals()))) /
                (1e18 * 1e8);
        }
        uint256[2] memory tradeAmounts = swap(
            dcaOwner,
            currSchedule,
            sellToken,
            buyToken,
            spender,
            swapTarget,
            swapCallData,
            gasUsed
        );

        updateUserDCA(
            dcaOwner,
            scheduleId,
            tradeAmounts,
            gasUsed,
            currentDateTime
        );
        userSwapHistory[dcaOwner][scheduleId].push(currentDateTime);
    }

    /**
     * @dev Performs the token swap for the DCA run.
     * @param dcaOwner The owner of the DCA schedule.
     * @param currSchedule The current DCA schedule being executed.
     * @param sellToken The token to sell.
     * @param buyToken The token to buy.
     * @param spender The address that is allowed to spend the tokens.
     * @param swapTarget The address of the contract to perform the swap.
     * @param swapCallData The data for the swap call.
     * @return An array containing the sold and bought amounts.
     * @notice This function performs the actual token swap and calculates the amounts bought and sold.
     */
    function swap(
        address dcaOwner,
        DcaSchedule memory currSchedule,
        IWETH sellToken,
        IERC20 buyToken,
        address spender,
        address payable swapTarget,
        bytes calldata swapCallData,
        uint256 gasUsed
    ) internal onlyRole(RUNNER_ROLE) returns (uint256[2] memory) {
        if (
            sellToken.allowance(address(this), spender) <
            currSchedule.tradeAmount
        ) {
            sellToken.approve(spender, MAX_INT);
        }

        uint256 boughtAmount;
        uint256 soldAmount;
        if (!isETH(buyToken)) {
            boughtAmount = buyToken.balanceOf(address(this));
        } else {
            boughtAmount = address(this).balance;
        }
        soldAmount = sellToken.balanceOf(address(this));

        (bool success, ) = swapTarget.call{value: 0}(swapCallData);
        if (!success) revert SWAP_CALL_FAILED();

        if (!isETH(buyToken)) {
            boughtAmount = buyToken.balanceOf(address(this)) - boughtAmount;
            buyToken.transfer(dcaOwner, boughtAmount);
        } else {
            boughtAmount = address(this).balance - boughtAmount;
            (bool s, ) = dcaOwner.call{value: boughtAmount}("");
            if (!s) revert ETH_not_transfer();
        }
        sellToken.transfer(owner(), gasUsed);
        soldAmount = soldAmount - sellToken.balanceOf(address(this));

        return [soldAmount, boughtAmount];
    }
}

