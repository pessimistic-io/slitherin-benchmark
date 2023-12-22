// SPDX-License-Identifier: BUSL-1.1
import "./ERC20.sol";

pragma solidity ^0.8.4;

interface IAccountRegistrar {
    struct AccountMapping {
        address oneCT;
        uint256 nonce;
    }
    event RegisterAccount(
        address indexed user,
        address indexed oneCT,
        uint256 nonce
    );
    event DeregisterAccount(address indexed account, uint256 nonce);

    function accountMapping(
        address
    ) external view returns (address oneCT, uint256 nonce);

    function registerAccount(
        address oneCT,
        address user,
        bytes memory signature
    ) external;
}

interface IRouterWrapper {
    enum Game {
        SLOTS,
        DICE
    }

    struct BetParams {
        uint256 queueId;
        address tokenAddress;
        uint32 numBets;
        uint256 stopGain;
        uint256 stopLoss;
        address player;
        bytes signature;
        uint256 signatureTimestamp;
        uint256 wager;
        address targetContract;
        uint32 multiplier;
        bool isOver;
        Game game;
    }

    struct RefundParams {
        address user;
        address targetContract;
    }

    event ApproveRouter(
        address user,
        uint256 nonce,
        uint256 value,
        uint256 deadline,
        address tokenX
    );

    struct AccountMapping {
        address oneCT;
        uint256 nonce;
    }
    struct Register {
        address oneCT;
        bytes signature;
        bool shouldRegister;
    }

    struct Permit {
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
        bool shouldApprove;
    }

    struct RevokeParams {
        address tokenX;
        address user;
        Permit permit;
    }

    struct OpenTxn {
        BetParams betParams;
        Register register;
        Permit permit;
        address user;
    }


    struct QueuedBet {
        uint256 queueId;
        address tokenAddress;
        uint256 numBets;
        uint256 stopGain;
        uint256 stopLoss;
        address player;
        bytes signature;
        uint256 signatureTimestamp;
        uint256 wager;
        address targetContract;
        uint256 payout;
        bool isProcessed;
    }

    function updatePayout(uint256 queueId, uint256 payout) external;

    event RegisterAccount(address indexed account, address indexed oneCT);
    event ContractRegistryUpdated(address targetContract, bool register);
    event FailResolve(uint256 queueId, string reason);
    event OpenBet(
        address indexed account,
        uint256 queueId,
        address targetContract
    );
    event FailRevoke(address indexed user, address tokenX, string reason);
    event FailRefund(address user, address targetContract, string reason);
    event Refund(address user, address targetContract);
    event RevokeRouter(
        address user,
        uint256 nonce,
        uint256 value,
        uint256 deadline,
        address tokenX
    );
    event UpdatePlatformFee(uint256 platformFee);
}

interface IRouter {
    enum Game {
        SLOTS,
        DICE
    }

    function runParameterChecks(IRouterWrapper.BetParams calldata params, address signer) external;
    function initiatePlay(IRouterWrapper.BetParams calldata params) external payable;
    function refund(address user, address targetContract) external;

}

interface VRFCoordinatorV2Interface {
    /**
     * @notice Get configuration relevant for making requests
     * @return minimumRequestConfirmations global min for request confirmations
     * @return maxGasLimit global max for request gas limit
     * @return s_provingKeyHashes list of registered key hashes
     */
    function getRequestConfig()
        external
        view
        returns (uint16, uint32, bytes32[] memory);

    /**
     * @notice Request a set of random words.
     * @param keyHash - Corresponds to a particular oracle job which uses
     * that key for generating the VRF proof. Different keyHash's have different gas price
     * ceilings, so you can select a specific one to bound your maximum per request cost.
     * @param subId  - The ID of the VRF subscription. Must be funded
     * with the minimum subscription balance required for the selected keyHash.
     * @param minimumRequestConfirmations - How many blocks you'd like the
     * oracle to wait before responding to the request. See SECURITY CONSIDERATIONS
     * for why you may want to request more. The acceptable range is
     * [minimumRequestBlockConfirmations, 200].
     * @param callbackGasLimit - How much gas you'd like to receive in your
     * fulfillRandomWords callback. Note that gasleft() inside fulfillRandomWords
     * may be slightly less than this amount because of gas used calling the function
     * (argument decoding etc.), so you may need to request slightly more than you expect
     * to have inside fulfillRandomWords. The acceptable range is
     * [0, maxGasLimit]
     * @param numWords - The number of uint256 random values you'd like to receive
     * in your fulfillRandomWords callback. Note these numbers are expanded in a
     * secure way by the VRFCoordinator from a single random value supplied by the oracle.
     * @return requestId - A unique identifier of the request. Can be used to match
     * a request to a response in fulfillRandomWords.
     */
    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId);

    /**
     * @notice Create a VRF subscription.
     * @return subId - A unique subscription id.
     * @dev You can manage the consumer set dynamically with addConsumer/removeConsumer.
     * @dev Note to fund the subscription, use transferAndCall. For example
     * @dev  LINKTOKEN.transferAndCall(
     * @dev    address(COORDINATOR),
     * @dev    amount,
     * @dev    abi.encode(subId));
     */
    function createSubscription() external returns (uint64 subId);

    /**
     * @notice Get a VRF subscription.
     * @param subId - ID of the subscription
     * @return balance - LINK balance of the subscription in juels.
     * @return reqCount - number of requests for this subscription, determines fee tier.
     * @return owner - owner of the subscription.
     * @return consumers - list of consumer address which are able to use this subscription.
     */
    function getSubscription(
        uint64 subId
    )
        external
        view
        returns (
            uint96 balance,
            uint64 reqCount,
            address owner,
            address[] memory consumers
        );

    /**
     * @notice Request subscription owner transfer.
     * @param subId - ID of the subscription
     * @param newOwner - proposed new owner of the subscription
     */
    function requestSubscriptionOwnerTransfer(
        uint64 subId,
        address newOwner
    ) external;

    /**
     * @notice Request subscription owner transfer.
     * @param subId - ID of the subscription
     * @dev will revert if original owner of subId has
     * not requested that msg.sender become the new owner.
     */
    function acceptSubscriptionOwnerTransfer(uint64 subId) external;

    /**
     * @notice Add a consumer to a VRF subscription.
     * @param subId - ID of the subscription
     * @param consumer - New consumer which can use the subscription
     */
    function addConsumer(uint64 subId, address consumer) external;

    /**
     * @notice Remove a consumer from a VRF subscription.
     * @param subId - ID of the subscription
     * @param consumer - Consumer to remove from the subscription
     */
    function removeConsumer(uint64 subId, address consumer) external;

    /**
     * @notice Cancel a subscription
     * @param subId - ID of the subscription
     * @param to - Where to send the remaining LINK to
     */
    function cancelSubscription(uint64 subId, address to) external;

    /*
     * @notice Check to see if there exists a request commitment consumers
     * for all consumers and keyhashes for a given sub.
     * @param subId - ID of the subscription
     * @return true if there exists at least one unfulfilled request for the subscription, false
     * otherwise.
     */
    function pendingRequestExists(uint64 subId) external view returns (bool);

    function getFeeConfig()
        external
        view
        returns (
            uint32,
            uint32,
            uint32,
            uint32,
            uint32,
            uint24,
            uint24,
            uint24,
            uint24
        );
}

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface ISlotsGame {
    struct SlotsGame {
        uint256 wager;
        uint256 stopGain;
        uint256 stopLoss;
        uint256 requestID;
        address tokenAddress;
        uint64 blockNumber;
        uint32 numBets;
        uint256 betId;
    }

    /**
     * @dev event emitted at the start of the game
     * @param playerAddress address of the player that made the bet
     * @param wager wagered amount
     * @param tokenAddress address of token the wager was made, 0 address is considered the native coin
     * @param numBets number of bets the player intends to make
     * @param stopGain gain value at which the betting stop if a gain is reached
     * @param stopLoss loss value at which the betting stop if a loss is reached
     */
    event Slots_Play_Event(
        address indexed playerAddress,
        uint256 wager,
        address tokenAddress,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss,
        uint256 betId
    );

    /**
     * @dev event emitted by the VRF callback with the bet results
     * @param playerAddress address of the player that made the bet
     * @param payout total payout transfered to the player
     * @param slotIDs slots result
     * @param multipliers multiplier of the slots result
     * @param payouts individual payouts for each bet
     */
    event Slots_Outcome_Event(
        address indexed playerAddress,
        uint256 payout,
        uint256 requestId,
        uint16[] slotIDs,
        uint256[] multipliers,
        uint256[] payouts,
        uint256 betId,
        uint32 numGames
    );

    /**
     * @dev event emitted when a refund is done in slots
     * @param player address of the player reciving the refund
     * @param wager amount of wager that was refunded
     * @param tokenAddress address of token the refund was made in
     */
    event Slots_Refund_Event(
        address indexed player,
        uint256 wager,
        address tokenAddress
    );

    function play(
        uint256 wager,
        address tokenAddress,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss,
        address msgSender,
        uint256 betId
    ) external payable returns (uint256 id);

    function runInitialChecks(
        address player,
        address tokenAddress,
        uint256 wager,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss
    ) external view;
}

interface IGame {
    function refund(address msgSender) external;

    function getVRFFee(
        uint256 gasAmount,
        uint256 l1Multiplier
    ) external view returns (uint256 fee);
}

interface IBankRollFacet {
    /**
     * @dev event emitted when game is Added or Removed
     * @param gameAddress address of game state that changed
     * @param isValid new state of game address
     */
    event BankRoll_Game_State_Changed(address gameAddress, bool isValid);
    /**
     * @dev event emitted when token state is changed
     * @param tokenAddress address of token that changed state
     * @param isValid new state of token address
     */
    event Bankroll_Token_State_Changed(address tokenAddress, bool isValid);
    /**
     * @dev event emitted when max payout percentage is changed
     * @param payout new payout percentage
     */
    event BankRoll_Max_Payout_Changed(uint256 payout);

    function getIsGame(address game) external view returns (bool);

    function getIsValidWager(
        address game,
        address tokenAddress
    ) external view returns (bool);

    function transferPayout(
        address player,
        uint256 payout,
        address token
    ) external;

    function getOwner() external view returns (address);

    function isPlayerSuspended(address player) external view returns (bool);
}

interface IDiceGame {
    /**
     * @dev Struct to store the parameters of a Dice game
     * @param wager wagered amount
     * @param stopGain gain value at which the betting stop if a gain is reached
     * @param stopLoss loss value at which the betting stop if a loss is reached
     * @param requestID request ID of the VRF callback
     * @param tokenAddress address of token the wager was made, 0 address is considered the native coin
     * @param blockNumber block number at which the game was played
     * @param numBets number of bets the player intends to make
     * @param multiplier selected multiplier for the wager range 10421-9900000, multiplier values divide by 10000
     * @param isOver if true dice outcome must be over the selected number, false must be under
     * @param betId bet ID of the game
     */
    struct DiceGame {
        uint256 wager;
        uint256 stopGain;
        uint256 stopLoss;
        uint256 requestID;
        address tokenAddress;
        uint64 blockNumber;
        uint32 numBets;
        uint32 multiplier;
        bool isOver;
        uint256 betId;
    }

    /**
     * @dev event emitted at the start of the game
     * @param playerAddress address of the player that made the bet
     * @param wager wagered amount
     * @param multiplier selected multiplier for the wager range 10421-9900000, multiplier values divide by 10000
     * @param tokenAddress address of token the wager was made, 0 address is considered the native coin
     * @param isOver if true dice outcome must be over the selected number, false must be under
     * @param numBets number of bets the player intends to make
     * @param stopGain gain value at which the betting stop if a gain is reached
     * @param stopLoss loss value at which the betting stop if a loss is reached
     * @param betId bet ID of the game
     */
    event Dice_Play_Event(
        address indexed playerAddress,
        uint256 wager,
        uint32 multiplier,
        address tokenAddress,
        bool isOver,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss,
        uint256 betId
    );

    /**
     * @dev event emitted by the VRF callback with the bet results
     * @param diceOutcomes results of dice roll, range 0-9999
     * @param payouts individual payouts for each bet
     * @param betId bet id of the game
     */
    event Dice_Outcome_Event(
        address playerAddress,
        uint256 payout,
        address tokenAddress,
        uint256[] diceOutcomes,
        uint256[] payouts,
        uint256 numGames,
        uint256 betId
    );

    /**
     * @dev event emitted when a refund is done in dice
     * @param player address of the player reciving the refund
     * @param wager amount of wager that was refunded
     * @param tokenAddress address of token the refund was made in
     */
    event Dice_Refund_Event(
        address indexed player,
        uint256 wager,
        address tokenAddress
    );

    function play(
        uint256 wager,
        address tokenAddress,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss,
        bool isOver,
        uint32 multiplier,
        address msgSender,
        uint256 betId
    ) external payable returns (uint256 id);

    function runInitialChecks(
        address player,
        address tokenAddress,
        uint256 wager,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss,
        uint32 multiplier
    ) external view;
}

