// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {VRFConsumerBaseV2} from "./VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from "./VRFCoordinatorV2Interface.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./ERC20_IERC20.sol";
import {IDarkAgeRealm} from "./IDarkAgeRealm.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";

contract LootBox is VRFConsumerBaseV2, Initializable, UUPSUpgradeable, PausableUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    VRFCoordinatorV2Interface COORDINATOR;
    RequestConfig public requestConfig;
    address public DAC;
    LootBoxConfig internal lootBoxConfig;
    IDarkAgeRealm public realm;
    mapping(uint256 => address) private randomRequests;
    mapping(address => Box) private boxAddress;

    struct RequestConfig {
        uint64 subscriptionId;
        uint32 callbackGasLimit;
        uint16 requestConfirmations;
        uint32 numWords;
        bytes32 keyHash;
    }

    struct Box {
        address user;
        Status status;
        uint256 randomness;
        Prize prize;
    }

    struct LootBoxConfig {
        uint256 lootBoxPrice;
        uint256 prizeProbability;
        uint256 burnProbability;
        uint256 nothingProbability;
        uint256 winningAmount;
        uint256 burnAmount;
    }

    enum Status {
        OPENED,
        PENDING,
        AVAILABLE
    }
    enum Prize {
        TOKENS,
        BURN,
        NOTHING
    }

    constructor(address vrfCoordinator) VRFConsumerBaseV2(vrfCoordinator) {
        _disableInitializers();
    }

    function initialize(
        address vrfCoordinator,
        uint64 subscriptionId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        bytes32 keyHash,
        uint256 _lootBoxPrice,
        address _realm
    ) public initializer {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        realm = IDarkAgeRealm(_realm);
        lootBoxConfig = LootBoxConfig({
            lootBoxPrice: _lootBoxPrice,
            prizeProbability: 5,
            burnProbability: 10,
            nothingProbability: 85,
            winningAmount: 100 ether,
            burnAmount: 100 ether
        });
        requestConfig = RequestConfig({
            subscriptionId: subscriptionId,
            callbackGasLimit: callbackGasLimit,
            requestConfirmations: requestConfirmations,
            numWords: 1,
            keyHash: keyHash
        });
    }

    function onTokenTransfer(address sender, uint256 value, bytes calldata) external {
        require(msg.sender == DAC, "Sender must be DAC address");
        require(value >= lootBoxConfig.lootBoxPrice, "Not enough tokens to buy loot box");

        _buyLootBox(sender);
    }

    function _buyLootBox(address sender) internal {
        uint256 requestId = COORDINATOR.requestRandomWords(
            requestConfig.keyHash,
            requestConfig.subscriptionId,
            requestConfig.requestConfirmations,
            requestConfig.callbackGasLimit,
            1
        );
        randomRequests[requestId] = sender;
        Box memory box = Box({user: sender, status: Status.PENDING, randomness: 0, prize: Prize.NOTHING});
        boxAddress[sender] = box;
    }

    function openLootBox() external {
        require(boxAddress[msg.sender].status == Status.AVAILABLE, "LootBox: Not available");
        uint256 randomNumber = boxAddress[msg.sender].randomness % 100;
        if (randomNumber < lootBoxConfig.prizeProbability) {
            // mint tokens
            realm.mintTreasure(msg.sender, lootBoxConfig.winningAmount);
            boxAddress[msg.sender].prize = Prize.TOKENS;
        } else if (randomNumber < lootBoxConfig.prizeProbability + lootBoxConfig.burnProbability) {
            // burn tokens
            realm.burnTreasure(msg.sender, lootBoxConfig.burnAmount);
            boxAddress[msg.sender].prize = Prize.BURN;
        }

        boxAddress[msg.sender].status = Status.OPENED;
    }

    function setLootBoxPrice(uint256 _lootBoxPrice) external onlyOwner {
        lootBoxConfig.lootBoxPrice = _lootBoxPrice;
    }

    function setDAC(address _dac) external onlyOwner {
        DAC = _dac;
    }

    function setPrizeProbability(uint256 _prizeProbability) external onlyOwner {
        lootBoxConfig.prizeProbability = _prizeProbability;
    }

    function setBurnProbability(uint256 _burnProbability) external onlyOwner {
        lootBoxConfig.burnProbability = _burnProbability;
    }

    function setNothingProbability(uint256 _nothingProbability) external onlyOwner {
        lootBoxConfig.nothingProbability = _nothingProbability;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 randomNumber = randomWords[0];
        address user = randomRequests[requestId];
        boxAddress[user].randomness = randomNumber;
    }

    function withdrawTokens() external onlyOwner {
        IERC20 token = IERC20(DAC);
        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

