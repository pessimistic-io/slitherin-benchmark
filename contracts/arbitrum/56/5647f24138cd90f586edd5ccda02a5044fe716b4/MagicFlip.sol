// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21;

import "./ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { RewardPool } from "./RewardPool.sol";
import { VRFCoordinatorV2Interface } from "./VRFCoordinatorV2.sol";
import { AggregatorV3Interface } from "./AggregatorV3Interface.sol";
import { IArbGasInfo } from "./IArbGasInfo.sol";
import { Ownable } from "./Ownable.sol";
import { console2 } from "./console2.sol";

contract MagicFlip is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    RewardPool public rewardPool;

    uint256 public constant BASE = 10_000;
    uint256 public constant feePerGame = 300; // 3%
    VRFCoordinatorV2Interface public immutable IChainLinkVRF;
    address public immutable chainLinkVRF;
    address public treasury;

    IArbGasInfo private immutable arbGas;
    AggregatorV3Interface public linkEthFeed;

    constructor(
        address _rewardPool,
        address _vrf,
        address _treasury,
        address _linkEthFeed,
        address _arbGas,
        address _owner
    )
        Ownable(_owner)
    {
        rewardPool = RewardPool(payable(_rewardPool));
        IChainLinkVRF = VRFCoordinatorV2Interface(_vrf);
        chainLinkVRF = _vrf;
        treasury = _treasury;
        linkEthFeed = AggregatorV3Interface(_linkEthFeed);
        arbGas = IArbGasInfo(_arbGas);
    }

    struct GameRound {
        uint256 wager;
        uint256 requestID;
        address betToken;
        uint64 blockNumber;
        bool isHeads;
        uint256 fee;
    }

    mapping(address => GameRound) public rounds;
    mapping(address => uint256) public totalBets; // token address -> amount
    mapping(uint256 => address) public coinIDs;
    mapping(address => bool) public isTokenSupported;

    /**
     * @dev event emitted at the start of the game
     * @param playerAddress address of the player that made the bet
     * @param wager wagered amount
     * @param betToken address of token the wager was made, 0 address is considered the native coin
     * @param isHeads player bet on which side the coin will land  1-> Heads, 0 ->Tails
     */
    event Play(address indexed playerAddress, uint256 wager, address betToken, bool isHeads);

    /**
     * @dev event emitted by the VRF callback with the bet results
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param payout total payout transfered to the player
     * @param betToken address of token the wager was made and payout, 0 address is considered the native coin
     * @param coinOutcome result of coinFlip, 1-> Heads, 0 ->Tails
     * @param payout payout for user
     */
    event GameOutcome(
        address indexed playerAddress, uint256 wager, uint256 payout, address betToken, uint8 coinOutcome
    );

    /**
     * @dev event emitted when a refund is done in coin flip
     * @param player address of the player reciving the refund
     * @param wager amount of wager that was refunded
     * @param betToken address of token the refund was made in
     */
    event Refund(address indexed player, uint256 wager, address betToken);

    error AwaitingVRF(uint256 requestID);
    error NotAwaitingVRF();
    error BlockNumberTooLow(uint256 have, uint256 want);
    error OnlyCoordinatorCanFulfill(address have, address want);
    error TransferFailed();
    error NotEnoughRewardBalance();
    error TokenNotSupported(address token);
    error WagerBelowLimit(uint256 wager, uint256 minWager);
    error NotEnoughEthForVRFFee();

    /**
     * @dev function to start a new game
     * @param wager wager amount
     * @param betToken address of token to bet, 0 address is considered the native coin
     * @param isHeads if bet selected heads or Tails
     */
    function play(uint256 wager, address betToken, bool isHeads) external payable nonReentrant {
        address msgSender = msg.sender;
        if (!isTokenSupported[betToken]) {
            revert TokenNotSupported(betToken);
        }
        if (rounds[msgSender].requestID != 0) {
            revert AwaitingVRF(rounds[msgSender].requestID);
        }

        uint256 fee = (wager * feePerGame) / BASE;
        uint256 vrfFee = getVRFFee(700_000, 22);
        _transferVrfFee(betToken, wager + fee, vrfFee);
        // transfer tokens from user to contract
        _transferWagerFromUser(betToken, wager + fee);
        // check if there is enough balance in the bankroll
        _checkRewardPool(wager, betToken);

        uint256 id = _requestRandomWords(1);

        rounds[msgSender] = GameRound(wager, id, betToken, uint64(block.number), isHeads, fee);
        coinIDs[id] = msgSender;
        totalBets[betToken] += wager;

        emit Play(msgSender, wager, betToken, isHeads);
    }

    /**
     * @dev Function to refund user in case of VRF request failling
     */
    function refund() external nonReentrant {
        address msgSender = msg.sender;
        GameRound storage game = rounds[msgSender];
        if (game.requestID == 0) {
            revert NotAwaitingVRF();
        }
        if (game.blockNumber + 200 > block.number) {
            revert BlockNumberTooLow(block.number, game.blockNumber + 200);
        }

        uint256 wager = game.wager + game.fee;
        address tokenAddress = game.betToken;

        totalBets[tokenAddress] -= game.wager;
        delete (coinIDs[game.requestID]);
        delete (rounds[msgSender]);

        if (tokenAddress == address(0)) {
            (bool success,) = payable(msgSender).call{ value: wager }("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(msgSender, wager);
        }
        emit Refund(msgSender, wager, tokenAddress);
    }

    /**
     * @dev function called by Chainlink VRF with random numbers
     * @param requestId id provided when the request was made
     * @param randomWords array of random numbers
     */
    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        if (msg.sender != chainLinkVRF) {
            revert OnlyCoordinatorCanFulfill(msg.sender, chainLinkVRF);
        }
        fulfillRandomWords(requestId, randomWords);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal {
        address playerAddress = coinIDs[requestId];
        if (playerAddress == address(0)) revert();
        GameRound memory game = rounds[playerAddress];

        uint8 result = uint8(randomWords[0] % 2);
        uint256 payout;
        if (result == 1 && game.isHeads) {
            payout = game.wager * 2;
        }
        if (result == 0 && !game.isHeads) {
            payout = game.wager * 2;
        }
        totalBets[game.betToken] -= game.wager;
        emit GameOutcome(playerAddress, game.wager, payout, game.betToken, result);
        _transferFee(game.betToken, game.fee);
        _transferToRewardPool(game.betToken, game.wager);
        delete (coinIDs[requestId]);
        delete (rounds[playerAddress]);
        if (payout != 0) {
            rewardPool.payout(playerAddress, game.betToken, payout);
        }
    }

    function getVRFFee(uint256 gasAmount, uint256 l1Multiplier) public view returns (uint256 fee) {
        (, int256 answer,,,) = linkEthFeed.latestRoundData();
        (uint32 fulfillmentFlatFeeLinkPPMTier1,,,,,,,,) = IChainLinkVRF.getFeeConfig();

        uint256 l1CostWei = (arbGas.getCurrentTxL1GasFees() * l1Multiplier) / 10;
        fee = tx.gasprice * (gasAmount) + l1CostWei
            + ((1e12 * uint256(fulfillmentFlatFeeLinkPPMTier1) * uint256(answer)) / 1e18);
    }

    function _checkRewardPool(uint256 _wager, address _betToken) internal view {
        uint256 requiredAmount = totalBets[_betToken] + _wager;
        uint256 balance =
            _betToken == address(0) ? address(rewardPool).balance : IERC20(_betToken).balanceOf(address(rewardPool));
        if (balance < requiredAmount) revert NotEnoughRewardBalance();
    }

    function _transferWagerFromUser(address _betToken, uint256 _wager) internal {
        if (_betToken == address(0)) {
            require(msg.value > _wager, "Invalid msg.value");
        } else {
            IERC20(_betToken).safeTransferFrom(msg.sender, address(this), _wager);
        }
    }

    function _transferVrfFee(address _betToken, uint256 _wager, uint256 _fee) internal {
        uint256 exceedAmount;
        if (_betToken == address(0)) {
            if (msg.value < _wager + _fee) {
                revert NotEnoughEthForVRFFee();
            }
            exceedAmount = msg.value - _wager - _fee;
        } else {
            if (msg.value < _fee) {
                revert NotEnoughEthForVRFFee();
            }
            exceedAmount = msg.value - _fee;
        }
        (bool success,) = payable(treasury).call{ value: _fee }("");
        if (!success) revert TransferFailed();
        if (exceedAmount > 0) {
            (success,) = payable(msg.sender).call{ value: exceedAmount }("");
            if (!success) revert TransferFailed();
        }
    }

    /**
     * @dev function to send the request for randomness to chainlink
     * @param numWords number of random numbers required
     */
    function _requestRandomWords(uint32 numWords) internal returns (uint256 s_requestId) {
        s_requestId = VRFCoordinatorV2Interface(chainLinkVRF).requestRandomWords(
            0x08ba8f62ff6c40a58877a106147661db43bc58dabfb814793847a839aa03367f, 137, 1, 2_500_000, numWords
        );
    }

    function _transferToRewardPool(address _tokenAddress, uint256 _amount) internal {
        if (_tokenAddress == address(0)) {
            (bool success,) = payable(address(rewardPool)).call{ value: _amount }("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(_tokenAddress).safeTransfer(address(rewardPool), _amount);
        }
    }

    function _transferFee(address _tokenAddress, uint256 _amount) internal {
        if (_tokenAddress == address(0)) {
            (bool success,) = payable(address(treasury)).call{ value: _amount }("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(_tokenAddress).safeTransfer(address(treasury), _amount);
        }
    }

    function setTokenSupported(address _token, bool _isSupported) external onlyOwner {
        isTokenSupported[_token] = _isSupported;
    }
}

