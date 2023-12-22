// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {Initializable} from "./Initializable.sol";

import {IStargateRouter, IStargateReceiver} from "./IStargate.sol";
import {ISgBridge} from "./ISgBridge.sol";

contract SgBridge is Initializable, OwnableUpgradeable, ISgBridge {
    using SafeERC20 for IERC20;

    IStargateRouter public router;

    uint256 public slippage;
    uint256 public dstGasForCall;
    uint16 public currentChainId;

    mapping(address => mapping(uint16 => uint256)) public poolIds;

    function initialize(
        address _router,
        uint16 _currentChainId
    ) public override initializer {
        __Ownable_init();

        router = IStargateRouter(_router);
        currentChainId = _currentChainId;
        slippage = 9_900;
        dstGasForCall = 1_000_000;
    }

    function setRouter(address _router) external override onlyOwner {
        router = IStargateRouter(_router);
    }

    function setSlippage(uint256 _slippage) external override onlyOwner {
        slippage = _slippage;
    }

    function setDstGasForCall(
        uint256 _dstGasForCall
    ) external override onlyOwner {
        dstGasForCall = _dstGasForCall;
    }

    function setCurrentChainId(
        uint16 _currentChainId
    ) external override onlyOwner {
        currentChainId = _currentChainId;
    }

    function setStargatePoolId(
        address _token,
        uint16 _chainId,
        uint256 _poolId
    ) external override onlyOwner {
        IERC20(_token).forceApprove(address(router), type(uint256).max);
        poolIds[_token][_chainId] = _poolId;
    }

    function revokeFunds() external override onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function bridge(
        address _token,
        uint256 _amount,
        uint16 _destChainId,
        address _destinationAddress,
        bytes memory _message
    ) external payable override {
        uint256 destinationPool = poolIds[_token][_destChainId];
        if (destinationPool == 0) {
            revert TokenNotSupported(_token, _destChainId);
        }

        uint256 sourcePool = poolIds[_token][currentChainId];
        if (sourcePool == 0) {
            revert TokenNotSupported(_token, currentChainId);
        }

        if (_destChainId == currentChainId) {
            IERC20(_token).safeTransferFrom(
                msg.sender,
                _destinationAddress,
                _amount
            );
            IStargateReceiver(_destinationAddress).sgReceive(
                _destChainId,
                abi.encodePacked(address(this)),
                0,
                _token,
                _amount,
                _message
            );
            return;
        }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        _bridgeInternal(
            _amount,
            sourcePool,
            _destChainId,
            destinationPool,
            _destinationAddress,
            _message
        );
    }

    function feeForBridge(
        uint16 _destChainId,
        address _destinationContract,
        bytes memory _payload
    ) external view override returns (uint256) {
        if (_destChainId == currentChainId) {
            return 0;
        }

        (uint256 fee, ) = router.quoteLayerZeroFee(
            _destChainId,
            /* _functionType */ 1,
            abi.encodePacked(_destinationContract),
            _payload,
            _getLzParams()
        );

        return fee;
    }

    function _bridgeInternal(
        uint256 _amount,
        uint256 _srcPoolId,
        uint16 _destChainId,
        uint256 _destinationPoolId,
        address _destinationContract,
        bytes memory _payload
    ) internal {
        uint256 withSlippage = (_amount * slippage) / 10_000;

        (uint256 fee, ) = router.quoteLayerZeroFee(
            _destChainId,
            /* _functionType */ 1,
            abi.encodePacked(_destinationContract),
            _payload,
            _getLzParams()
        );

        router.swap{value: fee}(
            _destChainId,
            _srcPoolId,
            _destinationPoolId,
            payable(address(this)),
            _amount,
            withSlippage,
            _getLzParams(),
            abi.encodePacked(_destinationContract),
            _payload
        );

        emit Bridge(_destChainId, _amount);
    }

    function _getLzParams()
        internal
        view
        returns (IStargateRouter.LzTxObj memory)
    {
        return
            IStargateRouter.LzTxObj({
                dstGasForCall: dstGasForCall,
                dstNativeAmount: 0,
                dstNativeAddr: abi.encode(address(this))
            });
    }

    receive() external payable {}
}

