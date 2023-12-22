// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable } from "./IERC20MetadataUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { Adminable } from "./Adminable.sol";

import { IMessageReceiverApp } from "./IMessageReceiverApp.sol";
import { MessageSenderLib } from "./MessageSenderLib.sol";
import { MsgDataTypes } from "./MsgDataTypes.sol";
import { Strings } from "./Strings.sol";

import { IBond } from "./IBond.sol";
import { INaivePegToken } from "./INaivePegToken.sol";
import { IMessageBus } from "./interfaces_IMessageBus.sol";

/**
 * @title SourceChainBridge
 * @dev This contract is used to transfer token from source chain to destination chain
 * @dev nomenclatures:
 - sourceChain: the chain where token transfer from.
 - originalChain: the chain where token initial supplied. (for duet token family, it's bsc)
 - destinationChain: the chain where token transfer to.
 - originalToken address: the token address on originalChain.
 */
contract DuetBridge is ReentrancyGuardUpgradeable, PausableUpgradeable, Adminable, IMessageReceiverApp {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
    bytes public constant ACTION_TRANSFER_X = "";
    bytes public constant ACTION_REDEEM_X = "REDEEM";

    // chainId => messenger contract address
    mapping(uint64 => address) chainContractMapping;
    // original token address => current chain token address
    mapping(address => address) tokenMapping;

    address public messageBus;
    /**
     * current chain id
     */
    uint64 public chainId;
    uint64 public originalChainId;

    event MessageWithTransferReceived(address sender, address token, uint256 amount, uint64 srcChainId, bytes note);
    event MessageWithTransferRefunded(address sender, address token, uint256 amount, bytes note);

    modifier onlyMessageBus() {
        require(msg.sender == messageBus, "DuetBridge: caller is not message bus");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function isOriginalChain() public view returns (bool) {
        return chainId == originalChainId;
    }

    function initialize(address messageBus_, uint64 chainId_, uint64 originalChainId_) external initializer {
        require(chainId_ > 0, "DuetBridge: chainId must be greater than 0");
        require(originalChainId_ > 0, "DuetBridge: chainId must be greater than 0");
        require(messageBus_ != address(0), "DuetBridge: messageBus must not be zero address");

        messageBus = messageBus_;
        chainId = chainId_;
        originalChainId = originalChainId_;

        _setAdmin(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    function addChainContract(uint64 chainId_, address chainContract_) external onlyAdmin {
        chainContractMapping[chainId_] = chainContract_;
    }

    function addToken(address originalToken_, address currentChainToken_) external onlyAdmin {
        tokenMapping[originalToken_] = currentChainToken_;
    }

    /**
     * @dev called by users on source chain to send tokens to destination chain
     */
    function transferX(address originalToken_, uint256 amount_, uint64 destChainId_, uint64 nonce_) external payable {
        uint256 transferXFee = getTransferXFee();
        require(
            msg.value >= transferXFee,
            string.concat("DuetBridge: msg.value must be greater than ", Strings.toString(transferXFee))
        );

        _transferXForUser(msg.sender, originalToken_, amount_, destChainId_, nonce_, ACTION_TRANSFER_X);
    }

    function _transferXForUser(
        address user_,
        address originalToken_,
        uint256 amount_,
        uint64 destChainId_,
        uint64 nonce_,
        bytes memory action_
    ) internal whenNotPaused nonReentrant {
        require(destChainId_ != chainId, "DuetBridge: destChainId must not be current chain id");
        require(originalToken_ != address(0), "DuetBridge: originalToken must not be zero address");
        require(amount_ > 0, "DuetBridge: amount must be greater than 0");
        require(nonce_ > 0, "DuetBridge: nonce must be greater than 0");
        address currentChainToken = tokenMapping[originalToken_];
        require(currentChainToken != address(0), "DuetBridge: token not supported");
        address destChainContract = chainContractMapping[destChainId_];
        require(destChainContract != address(0), "DuetBridge: destChain not supported");

        if (isOriginalChain()) {
            // When executing transferX on originalChain, the user's tokens will be locked in the DuetBridge contract.
            IERC20MetadataUpgradeable(currentChainToken).safeTransferFrom(user_, address(this), amount_);
        } else {
            // If it is not on originalChain, the tokens will be burned.
            INaivePegToken(currentChainToken).burnFrom(user_, amount_);
        }

        bytes memory message = abi.encode(user_, action_);
        uint256 fees = IMessageBus(messageBus).calcFee(message);

        MessageSenderLib.sendMessageWithTransfer(
            destChainContract,
            originalToken_,
            amount_,
            destChainId_,
            nonce_,
            // maxSlippage, only for MsgDataTypes.BridgeSendType.Liquidity
            0,
            message,
            MsgDataTypes.BridgeSendType.Null,
            messageBus,
            fees
        );
    }

    // called by MessageBus on destination chain to receive message, record and emit info.
    // the associated token transfer is guaranteed to have already been received
    function executeMessageWithTransfer(
        address sourceContract_,
        address originalToken_,
        uint256 amount_,
        uint64 sourceChainId_,
        bytes memory message_,
        address // executor
    ) external payable override onlyMessageBus whenNotPaused returns (ExecutionStatus) {
        require(sourceChainId_ != chainId, "DuetBridge: sourceChainId must not be current chain id");
        require(chainContractMapping[sourceChainId_] == sourceContract_, "DuetBridge: Invalid sourceContract_");
        address currentChainToken = tokenMapping[originalToken_];
        require(currentChainToken != address(0), "DuetBridge: token not supported");
        (address sender, bytes memory note) = abi.decode((message_), (address, bytes));

        if (isOriginalChain()) {
            // When receive tokens on originalChain, the user's tokens will be unlocked from the DuetBridge contract.
            IERC20MetadataUpgradeable(currentChainToken).transfer(sender, amount_);
        } else {
            INaivePegToken(currentChainToken).mint(msg.sender, amount_);
        }
        emit MessageWithTransferReceived(sender, originalToken_, amount_, sourceChainId_, note);
        return ExecutionStatus.Success;
    }

    // called by MessageBus on source chain to handle message with failed token transfer
    // the associated token transfer is guaranteed to have already been refunded
    function executeMessageWithTransferRefund(
        address originalToken_,
        uint256 amount_,
        bytes calldata message_,
        address executor_
    ) external payable override onlyMessageBus returns (ExecutionStatus) {
        (address sender, bytes memory note) = abi.decode((message_), (address, bytes));
        address currentChainToken = tokenMapping[originalToken_];

        if (isOriginalChain()) {
            // When executing refund on originalChain, the user's tokens will be unlocked from the DuetBridge contract.
            IERC20MetadataUpgradeable(currentChainToken).transfer(sender, amount_);
        } else {
            // If it is not on originalChain, tokens will be minted (as a burn rollback operation).
            INaivePegToken(currentChainToken).mint(sender, amount_);
        }

        emit MessageWithTransferRefunded(sender, originalToken_, amount_, note);
        return ExecutionStatus.Success;
    }

    function getTransferXFee() public view returns (uint256) {
        return calcFee(ACTION_TRANSFER_X);
    }

    function calcFee(bytes memory message_) public view returns (uint256) {
        bytes memory message = abi.encodePacked(address(this), message_);
        return IMessageBus(messageBus).calcFee(message) * 2;
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    /**
     * @notice Called by MessageBus to execute a message
     * @param _sender The address of the source app contract
     * @param _srcChainId The source chain ID where the transfer is originated from
     * @param _message Arbitrary message bytes originated from and encoded by the source app contract
     * @param _executor Address who called the MessageBus execution function
     */
    function executeMessage(
        address _sender,
        uint64 _srcChainId,
        bytes calldata _message,
        address _executor
    ) external payable returns (ExecutionStatus) {}

    // same as above, except that sender is an non-evm chain address,
    // otherwise same as above.
    function executeMessage(
        bytes calldata _sender,
        uint64 _srcChainId,
        bytes calldata _message,
        address _executor
    ) external payable returns (ExecutionStatus) {}

    /**
     * @notice Only called by MessageBus if
     *         1. executeMessageWithTransfer reverts, or
     *         2. executeMessageWithTransfer returns ExecutionStatus.Fail
     * The contract is guaranteed to have received the right amount of tokens before this function is called.
     * @param _sender The address of the source app contract
     * @param _token The address of the token that comes out of the bridge
     * @param _amount The amount of tokens received at this contract through the cross-chain bridge.
     * @param _srcChainId The source chain ID where the transfer is originated from
     * @param _message Arbitrary message bytes originated from and encoded by the source app contract
     * @param _executor Address who called the MessageBus execution function
     */
    function executeMessageWithTransferFallback(
        address _sender,
        address _token,
        uint256 _amount,
        uint64 _srcChainId,
        bytes calldata _message,
        address _executor
    ) external payable returns (ExecutionStatus) {}
}

