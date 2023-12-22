// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.19;

import {Token} from "./Token.sol";
import {Whitelist} from "./Whitelist.sol";
import {NonblockingLzApp} from "./NonblockingLzApp.sol";

contract Controller is NonblockingLzApp {

    Token public token;
    Whitelist public whitelist;

    uint16 public constant PT_BRIDGE = 0;

    event Bridge(address indexed user, uint256 amount);

    constructor(
        Token _token,
        Whitelist _whitelist,
        address _lzEndpoint
    ) NonblockingLzApp(_lzEndpoint) {
        token = _token;
        whitelist = _whitelist;
    }

    // Bridging Actions.

    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory payload) internal virtual override {
        uint16 packetType = abi.decode(payload, (uint16));
        if (packetType == PT_BRIDGE) {
            _bridgeIn(payload);
        } else {
            revert("Controller: unknown packet type");
        }
    }

    function _bridgeIn(bytes memory payload) internal {
        (, address user, uint256 amount) = abi.decode(payload, (uint16, address, uint256));
        if (!whitelist.isWhitelisted(user)) {
            whitelist.setDirectWhitelist(user, true);
        }
        token.mint(user, amount);
    }

    function bridgeOut(uint16 lzChainId, uint256 amount, address payable refundAddress, address zroPaymentAddress, bytes calldata adapterParams) public payable {
        token.transferFrom(msg.sender, address(this), amount);
        token.burn(amount);
        _checkAdapterParams(lzChainId, PT_BRIDGE, adapterParams, 0);
        bytes memory payload = abi.encode(PT_BRIDGE, msg.sender, amount);
        _lzSend(lzChainId, payload, refundAddress, zroPaymentAddress, adapterParams, msg.value);
        emit Bridge(msg.sender, amount);
    }

    function estimateBridgeFee(uint16 lzChainId, uint256 amount, bool useZro, bytes calldata adapterParams) public view returns (uint nativeFee, uint zroFee) {
        return lzEndpoint.estimateFees(lzChainId, address(this), abi.encode(PT_BRIDGE, msg.sender, amount), useZro, adapterParams);
    }

    // Direct token actions.

    function pause() external onlyOwner {
        token.pause();
    }

    function unpause() external onlyOwner {
        token.unpause();
    }

    function sendRebase(uint32 change, uint32 startTime, uint32 endTime) external onlyOwner {
        token.setRebase(change, startTime, endTime);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        token.mint(to, amount);
    }

    // Direct whitelist actions.

    function setMerkleRoot(bytes32 newMerkleRoot) external onlyOwner {
        whitelist.setMerkleRoot(newMerkleRoot);
    }

    function setDirectWhitelist(address account, bool whitelisted) external onlyOwner {
        whitelist.setDirectWhitelist(account, whitelisted);
    }

    function setDirectWhitelistBatch(address[] calldata accounts, bool[] calldata whitelisted) external onlyOwner {
        whitelist.setDirectWhitelistBatch(accounts, whitelisted);
    }

}
