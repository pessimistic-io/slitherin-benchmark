///SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IMultichain.sol";
import "./ERC20_IERC20.sol";
interface IAnyCall {
    function anyCall(address _to, bytes calldata _data, address _fallback, uint256 _toChainID, uint256 _flags) external;
}


contract TestArbitrum {
    address public owner;
    address public constant anyCallAddress = 0xC10Ef9F491C9B59f936957026020C321651ac078;
    address public nextChainExecutor;
    uint256 public nextChainId;
    address public lastChainExecutor;
    uint256 public lastChainId;
    address public constant multichainRouter = 0x650Af55D5877F289837c30b94af91538a7504b76;
    mapping(address => address) public tokenToAnyToken;
    uint256 lastCalledTime;
    modifier isOwner {
        require(owner == msg.sender);
        _;
    }

    constructor(address _token1, address _anyToken1, address _token2, address _anyToken2) {
        tokenToAnyToken[_token1] = _anyToken1;
        tokenToAnyToken[_token2] = _anyToken2;
        owner = msg.sender;
    }

    function anyExecute(bytes memory _data) external returns (bool success, bytes memory result) {
        lastCalledTime = block.timestamp;
        success=true;
        result="";
        // Gelato should listen out for messageReceived and start calling checkExecuteDeposits()
        // If it returns true, it can trigger it. Then stop listening.
    }

    function bridge(address[] memory _tokens) public isOwner {
        for (uint256 i; i< _tokens.length; i++) {
            address _token = _tokens[i];
            uint256 balance = IERC20(_token).balanceOf(address(this));
            IERC20(_token).approve(multichainRouter, balance);
            IMultichain(multichainRouter).anySwapOutUnderlying(tokenToAnyToken[_token], lastChainExecutor, balance, lastChainId);
        }
        
    }


    function setChainInformation(address _nextChainExecutor, uint256 _nextChainId, address _lastChainExecutor, uint256 _lastChainId) public isOwner {
        nextChainExecutor = _nextChainExecutor;
        nextChainId = _nextChainId;
        lastChainExecutor = _lastChainExecutor;
        lastChainId = _lastChainId;
    }
}
