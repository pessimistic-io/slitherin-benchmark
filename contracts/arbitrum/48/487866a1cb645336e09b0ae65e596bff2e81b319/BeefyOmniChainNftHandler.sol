// SPDX-License-Identifier: MIT
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./NonblockingLzAp.sol";

pragma solidity ^0.8.0;

interface IBeefyNftHandler {
     function claimAllAndVote() external;
}

// SrcChain contract for cross-chain execution of voting claims. 
contract BeefyOmniChainNftHandler is NonblockingLzApp {
    using SafeERC20 for IERC20;

    uint16 public thisChainId;
    uint16[] public chainIds; // Our chainIds we are executing on.

    address[] public nftHandlers;
    mapping(address => bool) public operators; // Operators allowed to call claimAndVote().

    error NotAuthorized();
    error EtherTransferFailure();
    
    event ClaimedAndVoted (address indexed nftHandler, uint256 time);
    event Error (address indexed nftHandler, uint256 time);

    constructor(
        uint16 _thisChainId,
        address _endpoint
    ) NonblockingLzApp(_endpoint) {
        thisChainId = _thisChainId;
    }

     modifier onlyAuth {
        if (!operators[msg.sender]) NotAuthorized;
        _;
    }

    function addOperator(address _operator, bool _status)  external {
        operators[_operator] = _status;
    }

    function addNftHandler(address _nftHandler) external onlyOwner {
        nftHandlers.push(_nftHandler);
    }

    function deleteNftHandlers() external onlyOwner {
        delete nftHandlers;
    }

    function addChainIds(uint16[] calldata _chainIds) external onlyOwner {
        for (uint i; i < _chainIds.length; ++i) {
            chainIds.push(_chainIds[i]);
        }
    }

    function deleteChainIds() external onlyOwner {
        delete chainIds;
    }

    function estimateFees() external view returns (uint256 fees) {
        for (uint i; i < chainIds.length; ++i) {
            if (chainIds[i] == thisChainId) continue;
            (uint nativeFee,) = _estimateFees(chainIds[i]);
            fees += nativeFee;
        }
    }

    function _estimateFees(uint16 _dstChainId) private view returns (uint nativeFee, uint zroFee) {
        bytes memory payload;
        return lzEndpoint.estimateFees(_dstChainId, address(this), payload, false, bytes(""));
    }

    function claimAllAndVote() external onlyAuth {
        bytes memory payload;
        for (uint i; i < chainIds.length; i++) {
            if (chainIds[i] == thisChainId) {
                _claimAndVote();
                continue;
            }

            (uint nativeFee, ) = _estimateFees(chainIds[i]);

            // send LayerZero message
            _lzSend( // {value: messageFee} will be paid out of this contract!
                chainIds[i], // destination chainId
                payload, // abi.encode()'ed bytes
                payable(this), // (msg.sender will be this contract) refund address (LayerZero will refund any extra gas back to caller of send()
                address(0x0), // future param, unused for this example
                bytes(""), // v1 adapterParams, specify custom destination gas qty
                nativeFee
            );
        }
    }

    function _claimAndVote() private {
        for (uint i; i < nftHandlers.length; ++i) {
            try IBeefyNftHandler(nftHandlers[i]).claimAllAndVote() {
                emit ClaimedAndVoted(nftHandlers[i], block.timestamp);
            } catch {
                emit Error(nftHandlers[i], block.timestamp);
            }
        }
    }

    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory) internal override {}

    // recover any tokens sent on error
    function inCaseTokensGetStuck(address _token, bool _native) external onlyOwner {
        if (_native) {
            uint256 _nativeAmount = address(this).balance;
            (bool sent,) = msg.sender.call{value: _nativeAmount}("");
            if (!sent) EtherTransferFailure;
        } else {
            uint256 _amount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, _amount);
        }
    }

    // allow this contract to receive ether
    receive() external payable {}
}
