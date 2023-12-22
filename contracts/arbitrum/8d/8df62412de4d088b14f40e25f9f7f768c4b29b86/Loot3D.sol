// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;
import "./ISocket.sol";
import "./RescueFundsLib.sol";
import "./Ownable2Step.sol";

interface ISurgePass {
    function balanceOf(address owner) external view returns (uint256);
}

contract Loot3D is Ownable2Step {
    using SafeTransferLib for IERC20;

    address public token;

    ISocket public socket__;
    ISurgePass public surgePass__;

    address public lastMessageSender;
    uint256 public lastMessageTimestamp;
    uint256 public timeGap;
    bool public isLootBoxActive;

    event LootWithdrawn(address indexed looter, address token, uint256 amount);
    event LootAdded(address token, uint256 amount);
    event LootBoxStatusUpdated(bool newStatus);
    event TimeGapUpdated(uint256 newTimeGap);

    error SenderNotSurgePassHolder();
    error CallerNotSocket();

    constructor(address socket_, address surgePass_, address token_) {
        _transferOwnership(msg.sender);
        surgePass__ = ISurgePass(surgePass_);
        socket__ = ISocket(socket_);
        timeGap = 1 hours;
        token = token_;
    }

    modifier onlySocket() {
        if (msg.sender != address(socket__)) revert CallerNotSocket();
        _;
    }

    modifier onlyOnOptimism() {
        require(block.chainid == 10, "Not on optimism");
        _;
    }

    modifier onlyWhenLootBoxActive() {
        require(isLootBoxActive, "Loot Box Not Active");
        _;
    }

    function connectRemoteLootBox(
        uint32 siblingChainSlug_,
        address siblingPlug_,
        address inboundSwitchboard_,
        address outboundSwitchboard_
    ) external onlyOwner {
        socket__.connect(
            siblingChainSlug_,
            siblingPlug_,
            inboundSwitchboard_,
            outboundSwitchboard_
        );
    }

    function outbound(uint32 chainSlug_, uint256 gasLimit_) external payable {
        bytes memory data = abi.encode(msg.sender);
        _outbound(chainSlug_, gasLimit_, msg.value, data);
    }

    function _outbound(
        uint32 chainSlug_,
        uint256 gasLimit_,
        uint256 fees_,
        bytes memory payload_
    ) internal {
        socket__.outbound{value: fees_}(chainSlug_, gasLimit_, payload_);
    }

    function inbound(
        uint32,
        bytes calldata payload_
    ) external payable onlySocket {
        address sender = abi.decode(payload_, (address));

        if (lastMessageSender != sender) {
            lastMessageTimestamp = block.timestamp;
            lastMessageSender = sender;
        }
    }

    function addLoot(uint256 amount_) external payable onlyOnOptimism {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount_);
        emit LootAdded(token, amount_);
    }

    function withdrawLoot() external onlyOnOptimism onlyWhenLootBoxActive {
        require(
            msg.sender == lastMessageSender,
            "msg.sender don't have last message"
        );
        require(
            block.timestamp >= lastMessageTimestamp + timeGap,
            "Called too soon"
        );

        if (surgePass__.balanceOf(msg.sender) == 0)
            revert SenderNotSurgePassHolder();

        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, balance);
        emit LootWithdrawn(msg.sender, token, balance);
    }

    function updateLootBoxStatus(bool status_) external onlyOwner {
        isLootBoxActive = status_;
        emit LootBoxStatusUpdated(status_);
    }

    function updateTimeGap(uint256 timeGap_) external onlyOwner {
        timeGap = timeGap_;
        emit TimeGapUpdated(timeGap_);
    }

    function updateSocket(address socket_) external onlyOwner {
        socket__ = ISocket(socket_);
    }

    function updateToken(address token_) external onlyOwner {
        token = token_;
    }

    function rescueFunds(
        address token_,
        address userAddress_,
        uint256 amount_
    ) external onlyOwner {
        RescueFundsLib.rescueFunds(token_, userAddress_, amount_);
    }
}

