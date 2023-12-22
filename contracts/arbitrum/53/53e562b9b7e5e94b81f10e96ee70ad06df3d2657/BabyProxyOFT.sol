// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./ProxyOFTWithFee.sol";
import "./SafeERC20.sol";
import "./Pausable.sol";
import "./Ownable.sol";

contract BabyProxyOFT is Ownable, Pausable, ProxyOFTWithFee {
    using SafeERC20 for IERC20;

    address public operator;

    // Outbound cap
    mapping(uint16 => uint256) public chainIdToOutboundCap;
    mapping(uint16 => uint256) public chainIdToSentTokenAmount;
    mapping(uint16 => uint256) public chainIdToLastSentTimestamp;

    // Inbound cap
    mapping(uint16 => uint256) public chainIdToInboundCap;
    mapping(uint16 => uint256) public chainIdToReceivedTokenAmount;
    mapping(uint16 => uint256) public chainIdToLastReceivedTimestamp;

    // If an address is whitelisted, the inbound/outbound cap checks are skipped
    mapping(address => bool) public whitelist;

    error NotOperator();
    error ExceedOutboundCap(uint256 cap, uint256 amount);
    error ExceedInboundCap(uint256 cap, uint256 amount);

    event SetOperator(address newOperator);
    event SetOutboundCapValue(uint16 indexed chainId, uint256 cap);
    event SetInboundCapValue(uint16 indexed chainId, uint256 cap);
    event SetWhitelist(address indexed addr, bool isWhitelist);
    event FallbackWithdraw(address indexed to, uint256 amount);
    event DropFailedMessage(uint16 srcChainId, bytes srcAddress, uint64 nonce);

    modifier onlyOperator() {
        if (msg.sender != operator) {
            revert NotOperator();
        }
        _;
    }

    constructor(
        address _token,
        uint8 _sharedDecimals,
        address _lzEndpoint
    ) ProxyOFTWithFee(_token, _sharedDecimals, _lzEndpoint) {
        operator = owner();
    }

    function _debitFrom(
        address _from,
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint256 _amount
    ) internal override whenNotPaused returns (uint256) {
        uint256 amount = super._debitFrom(
            _from,
            _dstChainId,
            _toAddress,
            _amount
        );

        if (whitelist[_from]) {
            return amount;
        }

        uint256 sentTokenAmount;
        uint256 lastSentTimestamp = chainIdToLastSentTimestamp[_dstChainId];
        uint256 currTimestamp = block.timestamp;
        if ((currTimestamp / (1 days)) > (lastSentTimestamp / (1 days))) {
            sentTokenAmount = amount;
        } else {
            sentTokenAmount = chainIdToSentTokenAmount[_dstChainId] + amount;
        }

        uint256 outboundCap = chainIdToOutboundCap[_dstChainId];
        if (sentTokenAmount > outboundCap) {
            revert ExceedOutboundCap(outboundCap, sentTokenAmount);
        }

        chainIdToSentTokenAmount[_dstChainId] = sentTokenAmount;
        chainIdToLastSentTimestamp[_dstChainId] = currTimestamp;

        return amount;
    }

    function _creditTo(
        uint16 _srcChainId,
        address _toAddress,
        uint256 _amount
    ) internal override whenNotPaused returns (uint256) {
        uint256 amount = super._creditTo(_srcChainId, _toAddress, _amount);

        if (whitelist[_toAddress]) {
            return amount;
        }

        uint256 receivedTokenAmount;
        uint256 lastReceivedTimestamp = chainIdToLastReceivedTimestamp[
            _srcChainId
        ];
        uint256 currTimestamp = block.timestamp;
        if ((currTimestamp / (1 days)) > (lastReceivedTimestamp / (1 days))) {
            receivedTokenAmount = amount;
        } else {
            receivedTokenAmount =
                chainIdToReceivedTokenAmount[_srcChainId] +
                amount;
        }

        uint256 inboundCap = chainIdToInboundCap[_srcChainId];
        if (receivedTokenAmount > inboundCap) {
            revert ExceedInboundCap(inboundCap, receivedTokenAmount);
        }

        chainIdToReceivedTokenAmount[_srcChainId] = receivedTokenAmount;
        chainIdToLastReceivedTimestamp[_srcChainId] = currTimestamp;

        return amount;
    }

    function setOperator(address newOperator) external onlyOwner {
        operator = newOperator;
        emit SetOperator(newOperator);
    }

    function setOutboundCap(uint16 chainId, uint256 cap) external onlyOwner {
        chainIdToOutboundCap[chainId] = cap;
        emit SetOutboundCapValue(chainId, cap);
    }

    function setInboundCap(uint16 chainId, uint256 cap) external onlyOwner {
        chainIdToInboundCap[chainId] = cap;
        emit SetInboundCapValue(chainId, cap);
    }

    function setWhitelist(address addr, bool isWhitelist) external onlyOwner {
        whitelist[addr] = isWhitelist;
        emit SetWhitelist(addr, isWhitelist);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /** @notice Only call it when there is no way to recover the failed message.
     * `dropFailedMessage` must be called first to avoid double spending.
     */
    /// @param to The address to withdraw to
    /// @param amount The amount of withdrawal
    function fallbackWithdraw(address to, uint256 amount)
        external
        onlyOperator
    {
        innerToken.safeTransfer(to, amount);
        emit FallbackWithdraw(to, amount);
    }

    function dropFailedMessage(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce
    ) external onlyOperator {
        failedMessages[srcChainId][srcAddress][nonce] = bytes32(0);
        emit DropFailedMessage(srcChainId, srcAddress, nonce);
    }
}

