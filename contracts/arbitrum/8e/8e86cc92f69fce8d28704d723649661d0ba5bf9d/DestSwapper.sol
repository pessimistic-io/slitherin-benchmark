// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; 

import "./SafeERC20.sol";
import "./IWrappedNative.sol";
import "./IStargate.sol";
import "./IStargateVault.sol";
import "./NonblockingLzApp.sol";

// Swaps reward and sends ETH back to src chain strategy
contract DestSwapper is NonblockingLzApp {
    using SafeERC20 for IERC20;

    address public native;
    address public reward;

    address public stgEthVault;
    address public stargate;
    uint256 public srcPoolId;
    uint16[] public chainIds;

    // Failure handling
    struct FailedSwap {
        bytes srcAddress;
        address strategy;
        uint256 amount;
    }

    mapping(uint16 => FailedSwap[]) failedSwaps;
    mapping(address => bool) public operators; // Operators allowed to call retry().
    mapping(uint16 => uint256) public dstPoolIds;
    mapping(uint16 => uint256) public gasLimit;

    // Errors
    error NotEnoughEth();
    error EtherTransferFailure();
    error NotAuthorized();
    error NotEnoughReward();

    event SuccessfulSwap(uint16 chainId, address strategy, uint256 amount);
    event Error();

    function __DestSwapper_init(
        address[] memory _destSwapperAddresses,
        address _endpoint,
        uint256 _srcPoolId
    ) internal onlyInitializing {
        __NonblockingLzApp_init(_endpoint);
        native = _destSwapperAddresses[0];
        reward = _destSwapperAddresses[1];
        stgEthVault = _destSwapperAddresses[2];
        stargate = _destSwapperAddresses[3];
        srcPoolId = _srcPoolId;

        IERC20(stgEthVault).approve(stargate, type(uint).max);
    }

    modifier onlyAuth {
        if (!operators[msg.sender] && msg.sender != owner()) revert NotAuthorized();
        _;
    }

    modifier onlyThisAddress {
        if (msg.sender != address(this)) revert NotAuthorized();
        _;
    }

    function _checkRewardBalance(uint256 _amount) internal view {
        uint256 rewardBal = IERC20(reward).balanceOf(address(this));
        if (rewardBal < _amount) revert NotEnoughReward();
    }

    function _swapAndReturn(uint16 _dstChainId, bytes memory _srcAddress, address _strategy, uint256 _amount) public onlyThisAddress {
        _checkRewardBalance(_amount);

        uint256 nativeBal = _swap(_amount);

        bytes memory payload = abi.encode(_strategy, nativeBal);
        IStargate.lzTxObj memory _lzTxObj = IStargate.lzTxObj({
            dstGasForCall: gasLimit[_dstChainId],
            dstNativeAmount: 0,
            dstNativeAddr: "0x"
        });

        _return(_dstChainId, _srcAddress, _strategy, _lzTxObj, nativeBal, payload);
    }

    function _return(uint16 _dstChainId, bytes memory _srcAddress, address _strategy, IStargate.lzTxObj memory _lzTxObj, uint256 _nativeBal, bytes memory _payload) private {
        (uint256 gasAmount,) = IStargate(stargate).quoteLayerZeroFee(
            _dstChainId,
            1, // TYPE_SWAP_REMOTE
            _srcAddress,
            _payload,
            _lzTxObj
        );

        gasAmount = gasAmount - address(this).balance;
        IWrappedNative(native).withdraw(_nativeBal);
        if (gasAmount >= _nativeBal) revert NotEnoughEth();
        _nativeBal = _nativeBal - gasAmount;

        IStargateVault(stgEthVault).deposit{ value: _nativeBal}();

        IStargate(stargate).swap{ value: gasAmount }(
            _dstChainId,
            srcPoolId,
            dstPoolIds[_dstChainId],
            payable(address(this)),
            IERC20(stgEthVault).balanceOf(address(this)),
            0,
            _lzTxObj,
            _srcAddress,
            abi.encode(_strategy, _nativeBal)
        );
    }

    function _swap(uint256 _amount) internal virtual returns (uint256 nativeAmount) {}

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64, /*_nonce*/
        bytes memory _payload
    ) internal override {
        (address _strategy, uint256 rewardSent) = abi.decode(_payload, (address,uint256)); 
        try this._swapAndReturn(_srcChainId, _srcAddress, _strategy, rewardSent) {
            emit SuccessfulSwap(_srcChainId, _strategy, rewardSent);
        } catch {
            FailedSwap memory failure = FailedSwap({
                srcAddress: _srcAddress,
                strategy: _strategy,
                amount: rewardSent
            });

            failedSwaps[_srcChainId].push(failure);
            emit Error();
        }
    }

    function retry() external onlyAuth {
        for (uint i; i < chainIds.length; ++i) {
            bool status;
            FailedSwap[] memory failures = failedSwaps[chainIds[i]];
            delete failedSwaps[chainIds[i]];
            for (uint j; j < failures.length; ++j) {
                FailedSwap memory failure = failures[i];
                uint256 rewardBal = IERC20(reward).balanceOf(address(this));
                if (failures[i].amount >= rewardBal) status = true;
                try this._swapAndReturn(chainIds[i], failure.srcAddress, failure.strategy, failure.amount) {
                     emit SuccessfulSwap(chainIds[i], failure.strategy, failure.amount);
                } catch {
                    FailedSwap memory fail = FailedSwap({
                        srcAddress: failure.srcAddress,
                        strategy: failure.strategy,
                        amount: failure.amount
                    });

                    failedSwaps[chainIds[i]].push(fail);
                    emit Error();
                }
               
            }
        }
    }

    function shouldRetry() external view returns (bool _shouldRetry) {
        uint256 rewardBal = IERC20(reward).balanceOf(address(this));
        for (uint i; i < chainIds.length; ++i) {
            FailedSwap[] memory failures = failedSwaps[chainIds[i]];
            for (uint j; j < failures.length; ++j) {
                if (failures[i].amount >= rewardBal) return true;
            }
        }

        return false;
    }

    function setOperator(address _operator, bool _status) external onlyOwner {
        operators[_operator] = _status;
    }

    function setChainIds(uint16[] calldata _chainIds, bool _delete) external onlyOwner {
        if (_delete) delete chainIds;
        
        for (uint i; i < _chainIds.length; ++i) {
            chainIds.push(_chainIds[i]);
        }
    }

    function setDestPoolIds(uint16[] calldata _chainIds, uint16[] calldata _poolIds) external onlyOwner {
        for (uint i; i < _chainIds.length; ++i) {
            dstPoolIds[_chainIds[i]] = _poolIds[i];
        }
    }

    function setGasLimit(uint16 _chainId, uint256 _limit) external onlyOwner {
        gasLimit[_chainId] = _limit;
    }

    // recover any tokens sent on error
    function inCaseTokensGetStuck(address _token, bool _native) external onlyOwner {
        if (_native) {
            uint256 _nativeAmount = address(this).balance;
            (bool sent,) = msg.sender.call{value: _nativeAmount}("");
            if (!sent) revert EtherTransferFailure();
        } else {
            uint256 _amount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, _amount);
        }
    }

    // allow this contract to receive ether
    receive() external payable {}
}

