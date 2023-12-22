// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {EnumerableSet} from "./EnumerableSet.sol";

contract DCAconfig {
    /**
     * @notice Event emitted when a new DCA schedule is created.
     * @param dcaScheduleId The ID of the new DCA schedule.
     * @param buyToken The address of the token to buy.
     * @param sellToken The address of the token to sell.
     * @param dcaOwner The owner of the new DCA schedule.
     */
    event NewUserSchedule(
        uint256 indexed dcaScheduleId,
        address buyToken,
        address sellToken,
        address indexed dcaOwner
    );
    /**
     * @notice Event emitted when funds are deposited into the contract.
     * @param sender The address that deposited the funds.
     * @param token The address of the token that was deposited.
     * @param amount The amount of tokens that were deposited.
     */
    event FundsDeposited(address indexed sender, address token, uint256 amount);
    /**
     * @notice Event emitted when funds are withdrawn from the contract.
     * @param receiver The address that withdrew the funds.
     * @param token The address of the token that was withdrawn.
     * @param amount The amount of tokens that were withdrawn.
     */
    event FundsWithdrawn(
        address indexed receiver,
        address token,
        uint256 amount
    );

    /**
     * @notice Event emitted when tokens are bought using a DCA schedule.
     * @param dcaScheduleId The ID of the DCA schedule.
     * @param sellToken The address of the token that was sold.
     * @param buyToken The address of the token that was bought.
     * @param soldAmount The amount of tokens that were sold.
     * @param boughtAmount The amount of tokens that were bought.
     * @param remainingBudget The remaining budget for the DCA schedule.
     * @param scheduleStatus The status of the DCA schedule.
     * @param nextRun The next run date for the DCA schedule.
     * @param dcaOwner The owner of the DCA schedule.
     */
    event BoughtTokens(
        uint256 indexed dcaScheduleId,
        address sellToken,
        address buyToken,
        uint256 soldAmount,
        uint256 boughtAmount,
        uint256 remainingBudget,
        bool scheduleStatus,
        uint256 nextRun,
        address indexed dcaOwner
    );

    using EnumerableSet for EnumerableSet.AddressSet;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public constant MAX_INT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    mapping(address => DcaSchedule[]) public userToDcaSchedules;
    EnumerableSet.AddressSet internal _userAddresses;
    mapping(address => mapping(address => uint256)) public userTokenBalances;
    mapping(address => mapping(uint256 => uint256[])) public userSwapHistory;
    mapping(address => EnumerableSet.AddressSet) internal _userTokens;
    uint256 public platformFee = 5;

    struct DcaSchedule {
        uint256 tradeFrequency;
        uint256 tradeAmount;
        uint256 remainingBudget;
        address buyToken;
        address sellToken;
        bool isActive;
        uint256[4] scheduleDates; //startDate, lastRun, nextRun, endDate
        uint256 soldAmount;
        uint256 boughtAmount;
        uint256 totalGas;
    }

    address public immutable WETH;
    address public immutable chainLinkPriceFeed;
    address public immutable forwarder;
    uint256 public immutable gasOneSwap;

    constructor(
        address _WETH,
        address _chainLinkPriceFeed,
        address _forwarder,
        uint256 _gasOneSwap
    ) {
        WETH = _WETH;
        chainLinkPriceFeed = _chainLinkPriceFeed;
        forwarder = _forwarder;
        gasOneSwap = _gasOneSwap;
    }
}

