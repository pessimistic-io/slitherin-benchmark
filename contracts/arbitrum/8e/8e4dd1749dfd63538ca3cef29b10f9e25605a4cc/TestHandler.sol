// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {ArcBaseWithRainbowRoad} from "./ArcBaseWithRainbowRoad.sol";
import {IHandler} from "./IHandler.sol";

/**
 * Test Handler
 */
contract TestHandler is ArcBaseWithRainbowRoad, IHandler
{
    address private lastTargetSent;
    string private lastTokenSent;
    address private lastTokenAddressSent;
    uint256 private lastAmountSent;
    uint256 private lastTokenIdSent;
    
    address private lastTargetReceived;
    string private lastTokenReceived;
    address private lastTokenAddressReceived;
    uint256 private lastAmountReceived;
    uint256 private lastTokenIdReceived;
    
    constructor(address _rainbowRoad) ArcBaseWithRainbowRoad(_rainbowRoad)
    {
        _transferOwnership(rainbowRoad.team());
    }
    
    function encodePayload(string calldata token, uint256 amount, uint256 tokenId) view external returns (bytes memory payload)
    {
        address tokenAddress = rainbowRoad.tokens(token);
        require(tokenAddress != address(0), 'Token cannot be zero address');
        require(!rainbowRoad.blockedTokens(tokenAddress), 'Token is blocked');
        return abi.encode(token, amount, tokenId);
    }
    
    function handleSend(address target, bytes calldata payload) external onlyRainbowRoad whenNotPaused
    {
        require(target != address(0), 'Target cannot be zero address');
        lastTargetSent = target;
        (lastTokenSent, lastAmountSent, lastTokenIdSent) = abi.decode(payload, (string, uint256, uint256));
        lastTokenAddressSent = rainbowRoad.tokens(lastTokenSent);
        require(lastTokenAddressSent != address(0), 'Token cannot be zero address');
        require(!rainbowRoad.blockedTokens(lastTokenAddressSent), 'Token is blocked');
    }
    
    function handleReceive(address target, bytes calldata payload) external onlyRainbowRoad whenNotPaused
    {
        require(target != address(0), 'Target cannot be zero address');
        lastTargetReceived = target;
        (lastTokenReceived, lastAmountReceived, lastTokenIdReceived) = abi.decode(payload, (string, uint256, uint256));
        lastTokenAddressReceived = rainbowRoad.tokens(lastTokenReceived);
        require(lastTokenAddressReceived != address(0), 'Token cannot be zero address');
        require(!rainbowRoad.blockedTokens(lastTokenAddressReceived), 'Token is blocked');
    }
    
    function getLastSendDetails() external view returns (address target, string memory token, string memory tokenName, string memory tokenSymbol, address tokenAddress, uint256 amount, uint256 tokenId)
    {
        return (lastTargetSent, lastTokenSent, IERC20Metadata(lastTokenAddressSent).name(), IERC20Metadata(lastTokenAddressSent).symbol(), lastTokenAddressSent, lastAmountSent, lastTokenIdSent);
    }
    
    function getLastReceiveDetails() external view returns (address target, string memory token, string memory tokenName, string memory tokenSymbol, address tokenAddress, uint256 amount, uint256 tokenId)
    {
        return (lastTargetReceived, lastTokenReceived, IERC20Metadata(lastTokenAddressReceived).name(), IERC20Metadata(lastTokenAddressReceived).symbol(), lastTokenAddressReceived, lastAmountReceived, lastTokenIdReceived);
    }
}
