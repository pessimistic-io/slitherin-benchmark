// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IRandomiserGen2} from "./IRandomiserGen2.sol";
import {TypeAndVersion} from "./TypeAndVersion.sol";
import {Authorised} from "./Authorised.sol";
import {IWETH9} from "./IWETH9.sol";
import {VRFCoordinatorV2Interface} from "./VRFCoordinatorV2Interface.sol";
import {AggregatorV2V3Interface} from "./AggregatorV2V3Interface.sol";
import {VRFConsumerBaseV2} from "./VRFConsumerBaseV2.sol";
import {LinkTokenInterface} from "./LinkTokenInterface.sol";
import {IRandomiserCallback} from "./IRandomiserCallback.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IERC20} from "./IERC20.sol";
import {L2GasUtil} from "./L2GasUtil.sol";

/// @title LinklessVRF
/// @author kevincharm
/// @notice Make VRF requests using ETH instead of LINK.
/// @dev Contract should charge a multiple of the total request cost. This fee
///     acts as a buffer for volatility in ETH/LINK & gasprice. Whatever is
///     left unused is taken as profit.
/// @dev Preload the subscription past the low watermark!
/// @dev The gaslane is hardcoded.
contract LinklessVRF is
    IRandomiserGen2,
    TypeAndVersion,
    Authorised,
    VRFConsumerBaseV2
{
    /// --- VRF SHIT ---
    /// @notice Max gas used to verify VRF proofs; always 200k according to:
    ///     https://docs.chain.link/vrf/v2/subscription#minimum-subscription-balance
    uint256 public constant MAX_VERIFICATION_GAS = 200_000;
    /// @notice Extra gas overhead for fulfilling randomness
    uint256 public constant FULFILMENT_OVERHEAD_GAS = 30_000;
    /// @notice VRF Coordinator (V2)
    /// @dev https://docs.chain.link/vrf/v2/subscription/supported-networks
    address public immutable vrfCoordinator;
    /// @notice LINK token (make sure it's the ERC-677 one)
    /// @dev PegSwap: https://pegswap.chain.link
    address public immutable linkToken;
    /// @notice LINK token unit
    uint256 public immutable juels;
    /// @dev VRF Coordinator LINK premium per request
    uint256 public immutable linkPremium;
    /// @notice Each gas lane has a different key hash; each gas lane
    ///     determines max gwei that will be used for the callback
    bytes32 public immutable gasLaneKeyHash;
    /// @notice Max gas price for gas lane used in gasLaneKeyHash
    /// @dev This is used purely for gas estimation
    uint256 public immutable gasLaneMaxWei;
    /// @notice Max gas limit supported by the coordinator
    uint256 public immutable absoluteMaxGasLimit;
    /// @notice VRF subscription ID; created during deployment
    uint64 public subId;

    /// --- PRICE FEED SHIT ---
    /// @notice Period until a feed is considered stale
    /// @dev Check heartbeat parameters on data.chain.link
    uint256 public constant MAX_AGE = 60 minutes;
    /// @notice Internal prices shall be scaled according to this constant
    uint256 public constant EXP_SCALE = 10**8;
    /// @notice LINK/USD chainlink price feed
    address public immutable feedLINKUSD;
    /// @notice ETH/USD chainlink price feed
    address public immutable feedETHUSD;

    /// --- UNISWAMP ---
    /// @notice WETH address used in UniV3 pool
    address public immutable weth;
    /// @notice UniV3 swap router (NB: SwapRouter v1!)
    address public immutable swapRouter;
    /// @notice UniV3 LINK/ETH pool fee
    uint24 public immutable uniV3PoolFee;

    /// --- THE PROTOCOL ---
    /// @notice Protocol fee per request.
    /// @dev Protocol fee also acts as a buffer against gas price volatility.
    ///     In volatile conditions, if actual fulfillment tx costs more gas,
    ///     protocol gets less profit (or potentially loses money).
    uint256 public immutable protocolFeeBps;
    /// @notice requestId => contract to callback
    /// @dev contract must implement IRandomiserCallback
    mapping(uint256 => address) public callbackTargets;
    /// @notice Minimum period between rebalances
    uint256 public constant REBALANCE_INTERVAL = 6 hours;
    /// @notice Last recorded rebalance operation
    uint256 public lastRebalancedAt;

    event RandomnessRequested(
        uint256 indexed requestId,
        uint256 fulfilmentCostPaid,
        uint256 protocolFeePaid
    );
    event RandomnessFulfilled(uint256 indexed requestId, uint256[] randomWords);
    event Rebalanced(
        uint64 oldSubId,
        uint64 newSubId,
        int256 linkBalanceDelta,
        int256 ethBalanceDelta
    );
    event SubscriptionRenewed(uint64 oldSubId, uint64 newSubId);
    event Withdrawn(address token, address recipient, uint256 amount);

    error InvalidFeedConfig(address feed, uint8 decimals);
    error InvalidFeedAnswer(
        int256 price,
        uint256 latestRoundId,
        uint256 updatedAt
    );
    error InsufficientFeePayment(
        uint32 callbackGasLimit,
        uint256 amountOffered,
        uint256 amountRequired
    );
    error RebalanceNotAvailable();
    error TransferFailed();
    error AbsoluteMaxGasLimitExceeded(
        uint256 callbackGasLimit,
        uint256 absoluteMaxGasLimit
    );

    struct RandomiserInitOpts {
        address vrfCoordinator;
        address linkToken;
        uint256 linkPremium;
        bytes32 gasLaneKeyHash;
        uint256 gasLaneMaxWei;
        uint256 absoluteMaxGasLimit;
        address feedLINKUSD;
        address feedETHUSD;
        address weth;
        address swapRouter;
        uint24 uniV3PoolFee;
        uint256 protocolFeeBps;
    }

    constructor(RandomiserInitOpts memory opts)
        VRFConsumerBaseV2(opts.vrfCoordinator)
    {
        vrfCoordinator = opts.vrfCoordinator;
        linkToken = opts.linkToken;
        juels = 10**LinkTokenInterface(opts.linkToken).decimals();
        linkPremium = opts.linkPremium;
        gasLaneKeyHash = opts.gasLaneKeyHash;
        gasLaneMaxWei = opts.gasLaneMaxWei;
        absoluteMaxGasLimit = opts.absoluteMaxGasLimit;

        feedLINKUSD = opts.feedLINKUSD;
        feedETHUSD = opts.feedETHUSD;
        weth = opts.weth;
        swapRouter = opts.swapRouter;
        uniV3PoolFee = opts.uniV3PoolFee;

        protocolFeeBps = opts.protocolFeeBps;

        // Create new subscription on the coordinator & add self as consumer
        subId = VRFCoordinatorV2Interface(opts.vrfCoordinator)
            .createSubscription();
        VRFCoordinatorV2Interface(opts.vrfCoordinator).addConsumer(
            subId,
            address(this)
        );
    }

    function typeAndVersion()
        external
        pure
        virtual
        override
        returns (string memory)
    {
        return "LinklessVRF 1.2.0";
    }

    receive() external payable {
        // Do nothing. This contract will be receiving ETH from unwrapping WETH.
    }

    /// @notice Get latest feed price, checking correct configuration and that
    ///     the price is fresh.
    /// @param feed_ Address of AggregatorV2V3Interface price feed
    function getLatestFeedPrice(address feed_)
        internal
        view
        returns (uint256 price, uint8 decimals)
    {
        AggregatorV2V3Interface feed = AggregatorV2V3Interface(feed_);
        decimals = feed.decimals();
        if (decimals == 0) {
            revert InvalidFeedConfig(feedLINKUSD, decimals);
        }
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = feed
            .latestRoundData();
        if (answer <= 0 || ((block.timestamp - updatedAt) > MAX_AGE)) {
            revert InvalidFeedAnswer(answer, roundId, updatedAt);
        }
        return (uint256(answer), decimals);
    }

    /// @notice Get LINK/USD
    function getLINKUSD()
        internal
        view
        returns (uint256 price, uint8 decimals)
    {
        return getLatestFeedPrice(feedLINKUSD);
    }

    /// @notice get ETH/USD
    function getETHUSD() internal view returns (uint256 price, uint8 decimals) {
        return getLatestFeedPrice(feedETHUSD);
    }

    /// @notice Compute ETH/LINK price
    /// @return ETHLINK price upscaled to EXP_SCALE
    function getETHLINK() internal view returns (uint256) {
        (uint256 priceETHUSD, uint8 decETHUSD) = getETHUSD();
        (uint256 priceLINKUSD, uint8 decLINKUSD) = getLINKUSD();

        // Assumptions: price > 0, decimals > 0
        return
            (EXP_SCALE * priceETHUSD * (10**decLINKUSD)) /
            (priceLINKUSD * (10**decETHUSD));
    }

    /// @notice Compute LINK/ETH price
    /// @return LINKETH price upscaled to EXP_SCALE
    function getLINKETH() internal view returns (uint256) {
        (uint256 priceETHUSD, uint8 decETHUSD) = getETHUSD();
        (uint256 priceLINKUSD, uint8 decLINKUSD) = getLINKUSD();

        // Assumptions: price > 0, decimals > 0
        return
            (EXP_SCALE * priceLINKUSD * (10**decETHUSD)) /
            (priceETHUSD * (10**decLINKUSD));
    }

    /// @notice Compute the max request gas cost (in wei) by taking the
    ///     maximums defined in this VRF coordinator's configuration. This
    ///     serves as the *low watermark* level for subscription balance.
    /// @dev See:
    ///     https://docs.chain.link/vrf/v2/subscription#minimum-subscription-balance
    /// @return Maximum gas that could possibly consumed by a request.
    function maxRequestGasCost() public view returns (uint256) {
        return
            gasLaneMaxWei *
            (MAX_VERIFICATION_GAS +
                FULFILMENT_OVERHEAD_GAS +
                absoluteMaxGasLimit);
    }

    /// @notice Estimate how much ETH is necessary to fulfill a request
    /// @param callbackGasLimit Gas limit for callback
    /// @return Amount of wei required for VRF request
    function estimateFulfilmentCostETH(uint32 callbackGasLimit)
        internal
        view
        returns (uint256)
    {
        uint256 linkPremiumETH = (linkPremium * getLINKETH()) / EXP_SCALE;
        uint256 requestGasCostETH = L2GasUtil.getGasPrice() *
            (MAX_VERIFICATION_GAS + FULFILMENT_OVERHEAD_GAS + callbackGasLimit);
        // NB: Hardcoded estimate of 512B of tx calldata (real avg ~260B)
        uint256 l1GasFee = L2GasUtil.estimateTxL1GasFees(512);
        return requestGasCostETH + linkPremiumETH + l1GasFee;
    }

    /// @notice Total request cost including protocol fee, in ETH (wei)
    /// @param callbackGasLimit Gas limit to use for the callback function
    /// @return totalRequestCostETH Amount of wei required to request a random
    ///     number from this protocol.
    /// @return fulfilmentCostETH Amount of estimated wei required to complete
    ///     the VRF call.
    function _computeTotalRequestCostETH(uint32 callbackGasLimit)
        internal
        view
        returns (uint256 totalRequestCostETH, uint256 fulfilmentCostETH)
    {
        fulfilmentCostETH = estimateFulfilmentCostETH(callbackGasLimit);
        uint256 protocolFee = (fulfilmentCostETH * protocolFeeBps) / 10000;
        totalRequestCostETH = fulfilmentCostETH + protocolFee;
    }

    /// @notice Total request cost including protocol fee, in ETH (wei)
    /// @param callbackGasLimit Gas limit to use for the callback function
    /// @return Amount of wei required to request a random number from this
    ///     protocol.
    function computeTotalRequestCostETH(uint32 callbackGasLimit)
        public
        view
        returns (uint256)
    {
        (uint256 totalRequestCostETH, ) = _computeTotalRequestCostETH(
            callbackGasLimit
        );
        return totalRequestCostETH;
    }

    /// @notice Swap LINK to ETH via Uniswap V3, using a Chainlink feed to
    ///     calculate the rate, and asserts a maximum amount of slippage.
    /// @param linkAmount Amount of ETH to swap
    /// @return Amount of ETH received
    function swapLINKToETH(uint256 linkAmount, uint16 maxSlippageBps)
        internal
        returns (uint256)
    {
        // Get rate for ETH->LINK using feed
        uint256 amountETHAtRate = (linkAmount * EXP_SCALE) / getETHLINK();
        uint256 maxSlippageDelta = (amountETHAtRate * maxSlippageBps) / 10000;
        // Minimum ETH output taking into account max allowable slippage
        uint256 amountOutMinimum = amountETHAtRate - maxSlippageDelta;

        // Approve LINK to SwapRouter
        LinkTokenInterface(linkToken).approve(swapRouter, linkAmount);

        // Swap ETH->LINK
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: linkToken,
                tokenOut: weth,
                fee: uniV3PoolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: linkAmount,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });
        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);

        // Unwrap WETH->ETH
        IWETH9(weth).withdraw(amountOut);

        return amountOut;
    }

    /// @notice Swap ETH to LINK via Uniswap V3, using a Chainlink feed to
    ///     calculate the rate, and asserts a maximum amount of slippage.
    /// @param ethAmount Amount of ETH to swap
    /// @return Amount of LINK received
    function swapETHToLINK(uint256 ethAmount, uint16 maxSlippageBps)
        internal
        returns (uint256)
    {
        // Get rate for ETH->LINK using feed
        uint256 amountLINKAtRate = (ethAmount * EXP_SCALE) / getLINKETH();
        uint256 maxSlippageDelta = (amountLINKAtRate * maxSlippageBps) / 10000;
        // Minimum LINK output taking into account max allowable slippage
        uint256 amountOutMinimum = amountLINKAtRate - maxSlippageDelta;

        // Wrap ETH->WETH & approve amount for UniV3 swap router
        IWETH9(weth).deposit{value: ethAmount}();
        IWETH9(weth).approve(swapRouter, ethAmount);

        // Swap ETH->LINK
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: weth,
                tokenOut: linkToken,
                fee: uniV3PoolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: ethAmount,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });
        return ISwapRouter(swapRouter).exactInputSingle(params);
    }

    /// @notice Request a random number
    /// @param callbackContract Target contract to callback
    /// @param callbackGasLimit Maximum amount of gas that can be consumed by
    ///     the callback function
    /// @param minConfirmations Number of block confirmations to wait before
    ///     the VRF request can be fulfilled
    /// @return requestId Request ID from VRF Coordinator
    function getRandomNumber(
        address callbackContract,
        uint32 callbackGasLimit,
        uint16 minConfirmations
    ) public payable override returns (uint256 requestId) {
        if (callbackGasLimit > absoluteMaxGasLimit) {
            revert AbsoluteMaxGasLimitExceeded(
                callbackGasLimit,
                absoluteMaxGasLimit
            );
        }
        // Assert payment is enough
        (
            uint256 totalRequestCostETH,
            uint256 fulfilmentCostETH
        ) = _computeTotalRequestCostETH(callbackGasLimit);
        if (msg.value < totalRequestCostETH) {
            revert InsufficientFeePayment(
                callbackGasLimit,
                msg.value,
                totalRequestCostETH
            );
        }

        // Check if sub balance is below the low watermark
        uint64 subId_ = subId;
        (uint96 balance, , , ) = VRFCoordinatorV2Interface(vrfCoordinator)
            .getSubscription(subId);
        if (balance < maxRequestGasCost()) {
            // Subscription needs to be topped up
            uint256 amountLINKReceived = swapETHToLINK(
                fulfilmentCostETH,
                75 /** NB: Hardcoded -0.75% max slippage */
            );
            // Fund subscription with swapped LINK
            LinkTokenInterface(linkToken).transferAndCall(
                vrfCoordinator,
                amountLINKReceived,
                abi.encode(subId_)
            );
        }

        // Finally, make the VRF request
        requestId = VRFCoordinatorV2Interface(vrfCoordinator)
            .requestRandomWords(
                gasLaneKeyHash,
                subId_,
                minConfirmations,
                callbackGasLimit,
                1
            );
        callbackTargets[requestId] = callbackContract;
        emit RandomnessRequested(
            requestId,
            fulfilmentCostETH,
            totalRequestCostETH - fulfilmentCostETH
        );
    }

    /// @notice Callback function used by VRF Coordinator
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords)
        internal
        override
    {
        address target = callbackTargets[requestId];
        delete callbackTargets[requestId];

        IRandomiserCallback(target).receiveRandomWords(requestId, randomWords);
        emit RandomnessFulfilled(requestId, randomWords);
    }

    /// @notice Get params that determine if a rebalance is possible.
    ///     NB: Does NOT take into account LINK balance on this contract; only
    ///     takes into account the subscription LINK balance.
    /// @dev Keeper function
    function isRebalanceAvailable()
        public
        view
        returns (
            bool isAvailable,
            uint256 subLINKBalance,
            uint256 lowWatermarkLINK,
            uint256 lowWatermarkETH
        )
    {
        (subLINKBalance, , , ) = VRFCoordinatorV2Interface(vrfCoordinator)
            .getSubscription(subId);
        lowWatermarkETH = maxRequestGasCost();
        lowWatermarkLINK = (lowWatermarkETH * EXP_SCALE) / getLINKETH();

        bool hasRebalanceIntervalElapsed = block.timestamp - lastRebalancedAt >=
            REBALANCE_INTERVAL;
        bool needsRebalance = (subLINKBalance > 2 * lowWatermarkLINK) ||
            ((subLINKBalance < lowWatermarkLINK) &&
                (address(this).balance >= lowWatermarkETH));
        isAvailable = hasRebalanceIntervalElapsed && needsRebalance;
    }

    /// @notice Perform upkeep by cancelling the subscription iff sub balance
    ///     is above the low watermark. By cancelling the sub, LINK is
    ///     returned to this contract. This contract will then buy ETH with
    ///     excess LINK. A new subscription is then created to replace the
    ///     existing subscription.
    /// @dev Keeper function
    function rebalance() public {
        (
            bool isAvailable,
            uint256 subLINKBalance,
            uint256 lowWatermarkLINK,
            uint256 lowWatermarkETH
        ) = isRebalanceAvailable();
        if (!isAvailable) {
            revert RebalanceNotAvailable();
        }
        lastRebalancedAt = block.timestamp;

        if (subLINKBalance > 2 * lowWatermarkLINK) {
            // Case 0: Excess LINK can be swapped to ETH.
            uint64 oldSubId = subId;
            VRFCoordinatorV2Interface coord = VRFCoordinatorV2Interface(
                vrfCoordinator
            );
            // Cancel subscription and receive LINK refund to this contract
            coord.cancelSubscription(oldSubId, address(this));
            // Create new subscription
            uint64 newSubId = coord.createSubscription();
            coord.addConsumer(newSubId, address(this));
            subId = newSubId;
            emit SubscriptionRenewed(oldSubId, newSubId);
            // Fund the new subscription upto the low watermark
            LinkTokenInterface(linkToken).transferAndCall(
                vrfCoordinator,
                lowWatermarkLINK,
                abi.encode(newSubId)
            );
            // Dump any LINK that's left in the contract
            uint256 ownLINKBalance = LinkTokenInterface(linkToken).balanceOf(
                address(this)
            );
            uint256 receivedETH = swapLINKToETH(
                ownLINKBalance,
                75 /** NB: Hardcoded -0.75% max slippage */
            );
            emit Rebalanced(
                oldSubId,
                newSubId,
                -int256(ownLINKBalance),
                int256(receivedETH)
            );
        } else if (subLINKBalance < lowWatermarkLINK) {
            // NB: (address(this).balance >= lowWatermarkETH) is true here
            // Case 1: Sub balance is below the watermark, so we need to swap
            // ETH to LINK, if there is ETH balance available.
            // Swap ETH to LINK with available balance
            uint256 receivedLINK = swapETHToLINK(
                lowWatermarkETH,
                75 /** NB: Hardcoded -0.75% max slippage */
            );
            // Fund the subscription with received LINK
            uint64 currentSubId = subId;
            LinkTokenInterface(linkToken).transferAndCall(
                vrfCoordinator,
                receivedLINK,
                abi.encode(currentSubId)
            );
            emit Rebalanced(
                currentSubId,
                currentSubId,
                int256(receivedLINK),
                -int256(lowWatermarkETH)
            );
        } else {
            // This branch should not be reachable
            revert("Logic error");
        }
    }

    /// @notice Cancel a subscription to receive a refund; then create a new
    ///     one and add self as consumer.
    /// @dev This is here in case we need to manually withdraw LINK to TWAP;
    ///     which may be necessary if a `rebalance()` would move the Uniswap
    ///     pool price so much that it becomes impossible to execute with the
    ///     hardcoded max slippage.
    function renewSubscription()
        external
        onlyAuthorised
        returns (uint64 oldSubId, uint64 newSubId)
    {
        VRFCoordinatorV2Interface coord = VRFCoordinatorV2Interface(
            vrfCoordinator
        );
        oldSubId = subId;
        coord.cancelSubscription(oldSubId, address(this));
        newSubId = coord.createSubscription();
        subId = newSubId;
        coord.addConsumer(newSubId, address(this));
        emit SubscriptionRenewed(oldSubId, newSubId);
    }

    /// @notice Fund the subscription managed by this contract. This is not
    ///     actually *needed* since we should be able to arbitrarily fund any
    ///     subscription, but is here for convenience. The required LINK amount
    ///     must be already in this contract's balance.
    /// @param amount Amount of LINK to fund the subscription with. This amount
    ///     of LINK must already be in the contract balance.
    function fundSubscription(uint256 amount) external {
        if (amount == 0) {
            amount = LinkTokenInterface(linkToken).balanceOf(address(this));
        }
        LinkTokenInterface(linkToken).transferAndCall(
            vrfCoordinator,
            amount,
            abi.encode(subId)
        );
    }

    /// @notice Withdraw ERC-20 tokens
    /// @param token Address of ERC-20
    /// @param amount Amount to withdraw, withdraws entire balance if 0
    function withdrawERC20(address token, uint256 amount)
        external
        onlyAuthorised
    {
        if (amount == 0) {
            amount = IERC20(token).balanceOf(address(this));
        }
        IERC20(token).transfer(msg.sender, amount);
        emit Withdrawn(token, msg.sender, amount);
    }

    /// @notice Withdraw ETH
    /// @param amount Amount to withdraw, withdraws entire balance if 0
    function withdrawETH(uint256 amount) external onlyAuthorised {
        if (amount == 0) {
            amount = address(this).balance;
        }
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
        emit Withdrawn(
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            msg.sender,
            amount
        );
    }
}

