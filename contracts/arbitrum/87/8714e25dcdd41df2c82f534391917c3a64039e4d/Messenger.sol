// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

import "./IBridgeHandle.sol";
import "./IUserApplication.sol";

contract Messenger is Initializable, OwnableUpgradeable, IUserApplication {

    uint16 public chainId;

    uint256 public maxLength;

    mapping(uint16 => uint64) public nonce;

    mapping(uint16 => uint256) public fees;

    mapping(uint16 => IBridgeHandle) public bridgeHandle;

    mapping(address => Msg[]) public messages;

    struct Msg {
        address sender;
        string message;
    }

    function initialize(uint16 _chainId) public initializer {
        __Ownable_init();
        maxLength = 140;
        chainId = _chainId;
    }

    event MessageSend(uint64 indexed nonce, uint32 indexed dstChainId, address sender, address recipient, string message);

    event MessageReceived(uint64 indexed nonce, uint32 indexed srcChainId, address sender, address recipient, string message);

    event NewFee(uint16 chainId, uint256 fee);

    function sendMessage(
        uint16 dstChainId,
        address recipient,
        string memory message,
        bytes calldata _adapterParams
    ) external payable {
        IBridgeHandle handle = bridgeHandle[dstChainId];
        require(address(handle) != address(0), "Unsupported dstChain");
        require(bytes(message).length <= maxLength, "Maximum message length exceeded.");

        uint64 currentNonce = nonce[dstChainId];
        bytes memory payload = abi.encode(currentNonce, msg.sender, recipient, message);
        require(msg.value >= _estimateFee(dstChainId, payload, _adapterParams), "insufficient Fee");

        uint256 bridgeFee = msg.value - fees[dstChainId];
        handle.sendMessage{value : bridgeFee}(dstChainId, payload, payable(msg.sender), _adapterParams, bridgeFee);
        nonce[dstChainId]++;
        emit MessageSend(currentNonce, dstChainId, msg.sender, recipient, message);
    }

    function receiveMessage(uint16 srcChainId, address srcAddress, uint64 nonce, bytes memory payload) external {
        require(msg.sender == address(bridgeHandle[srcChainId]), "invalid bridgeHandle caller");
        (uint64 nonce,address sender, address recipient, string memory message) = abi.decode(payload, (uint64, address, address, string));
        messages[recipient].push(Msg(sender, message));
        emit MessageReceived(nonce, srcChainId, sender, recipient, message);
    }

    function _estimateFee(uint16 _dstChainId, bytes memory _payload, bytes memory _adapterParams) internal view returns (uint256){
        uint256 bridgeFee = bridgeHandle[_dstChainId].estimateFees(_dstChainId, _payload, _adapterParams);
        return bridgeFee + fees[_dstChainId];
    }


    function estimateFee(uint16 dstChainId, address recipient,string memory message, bytes memory adapterParams) external view returns (uint256){
        bytes memory payload = abi.encode(nonce[dstChainId], address(this), recipient, message);
        return _estimateFee(dstChainId, payload, adapterParams);
    }

    function setMsgLength(uint256 _maxLength) external onlyOwner {
        maxLength = _maxLength;
    }

    function setFee(uint16 _dstChainId, uint256 _fee) external onlyOwner {
        require(fees[_dstChainId] != _fee, "Fee has already been set.");
        fees[_dstChainId] = _fee;
        emit NewFee(_dstChainId, _fee);
    }

    function setBridgeHandle(uint16 _dstChainId, address _bridgeHandle) external onlyOwner {
        bridgeHandle[_dstChainId] = IBridgeHandle(_bridgeHandle);
    }

    function claimFees() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}

