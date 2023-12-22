// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {NonblockingLzApp} from "./NonblockingLzApp.sol";
import {ITokenFactory} from "./ITokenFactory.sol";
import {BridgedToken} from "./BridgedToken.sol";
import {ERC20} from "./token_ERC20.sol";

contract TokenFactory is NonblockingLzApp, ITokenFactory {

    uint16 public immutable LZ_CHAIN_ID;
    uint256 public bridgeFee = 100; // 0.1%;
    address public feeTo;
    address public tokenImplementation;

    constructor(address _endpoint, uint16 _lzChainId) NonblockingLzApp(_endpoint) {
        LZ_CHAIN_ID = _lzChainId; // Cannot rely on lzEndpoint.getChainId() as it doesn't return the correct value.
        feeTo = msg.sender;
        tokenImplementation = address(new BridgedToken(address(lzEndpoint)));
    }

    function _nonblockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) internal override {
        _deployToken(_payload, _srcChainId);
    }

    function estimateDeployBridgeTokensFee(
        ERC20 token,
        uint16[] memory destinationChains,
        bytes[] memory adapterParams,
        bool useZro
    ) public view returns (uint[] memory nativeFees, uint[] memory zroFees, uint256 totalNativeFees, uint256 totalZroFees) {
        bytes memory payload = abi.encode(token, token.name(), token.symbol(), token.decimals(), destinationChains);
        nativeFees = new uint[](destinationChains.length);
        zroFees = new uint[](destinationChains.length);
        for (uint256 i = 0; i < destinationChains.length; i++) {
            (nativeFees[i], zroFees[i]) = lzEndpoint.estimateFees(destinationChains[i], address(this), payload, useZro, adapterParams[0]);
            totalNativeFees += nativeFees[i];
            totalZroFees += zroFees[i];
        }
    }

    function deployBridgeTokens(
        ERC20 token,
        uint16[] memory destinationChains,
        address payable refundAddress,
        address payable zroPaymentAddress,
        bytes[] memory adapterParams, // "" for no adapter
        uint256[] memory values
    ) external payable returns (BridgedToken bridgedToken) {
        bytes memory payload = abi.encode(token, token.name(), token.symbol(), token.decimals(), destinationChains);
        for (uint256 i = 0; i < destinationChains.length; i++) {
            _lzSend(destinationChains[i], payload, refundAddress, zroPaymentAddress, adapterParams[i], values[i]);
        }
        return _deployToken(payload, LZ_CHAIN_ID);
    }

    function _deployToken(bytes memory payload, uint16 srcChain) internal returns(BridgedToken clone) {
        (
            address nativeToken,
            string memory name,
            string memory symbol,
            uint8 decimals,
            uint16[] memory chainIds
        ) = abi.decode(payload, (address, string, string, uint8, uint16[]));
        bytes32 salt = keccak256(abi.encodePacked(nativeToken, name, symbol, decimals, srcChain));
        clone = BridgedToken(_cloneDeterministic(tokenImplementation, salt));
        clone.init(name, symbol, decimals, nativeToken, srcChain == LZ_CHAIN_ID);
        _setTrustedRemotes(clone, chainIds, srcChain);
    }

    function _setTrustedRemotes(BridgedToken token, uint16[] memory chainIds, uint16 naticeChainId) internal {
        // Token is deployed under the same address accross all chains.
        bytes memory path = abi.encodePacked(address(token), address(token));
        for(uint256 i = 0; i < chainIds.length; i++) {
            token.setTrustedRemote(chainIds[i], path);
        }
        token.setTrustedRemote(naticeChainId, path);
    }

    function _cloneDeterministic(address implementation, bytes32 salt) internal returns (address instance) {
        assembly {
            mstore(0x00, or(shr(0xe8, shl(0x60, implementation)), 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000))
            mstore(0x20, or(shl(0x78, implementation), 0x5af43d82803e903d91602b57fd5bf3))
            instance := create2(0, 0x09, 0x37, salt)
        }
        require(instance != address(0), "ERC1167: create2 failed");
    }

}

