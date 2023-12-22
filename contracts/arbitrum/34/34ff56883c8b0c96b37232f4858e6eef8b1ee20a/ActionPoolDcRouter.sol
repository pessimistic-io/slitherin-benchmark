// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./NonblockingLzApp.sol";
import "./IERC20.sol";
import "./IActionPoolDcRouter.sol";

/**
 * @author DeCommas team
 * @title Implementation of the basic multiChain DeCommasStrategyRouter.
 * @dev Originally based on code by Pillardev: https://github.com/Pillardevelopment
 * @dev Original idea on architecture by Loggy: https://miro.com/app/board/uXjVOZbZQQI=/?fromRedirect=1
 */
contract ActionPoolDcRouter is NonblockingLzApp, IActionPoolDcRouter {
    uint16 private _nativeChainId;

    /// Address of Optimism Relayer Contract
    address private _deCommasRelayerAddress;

    /// deCommas address of Building block contract for lost funds
    address private _deCommasTreasurer;

    modifier onlyRelayer() {
        require(
            _deCommasRelayerAddress == _msgSender(),
            "ActionPoolDcRouter:caller is not relayer"
        );
        _;
    }

    /**
     * @notice Initializer for Proxy
     * @param _deCommasTreasurerAddress - address of Treasurer
     * @param _nativeLZEndpoint -  native LZEndpoint, see more:
     * (https://layerzero.gitbook.io/docs/technical-reference/testnet/testnet-addresses)
     * @param _nativeId -
     * @param _relayer - address of Relayer
     */
    constructor(
        address _deCommasTreasurerAddress,
        address _nativeLZEndpoint,
        uint16 _nativeId,
        address _relayer
    ) {
        require(
            _deCommasTreasurerAddress != address(0),
            "ActionPoolDcRouter:zero address"
        );
        require(
            _nativeLZEndpoint != address(0),
            "ActionPoolDcRouter:zero address"
        );
        require(_nativeId != 0, "ActionPoolDcRouter:zero native Id");
        require(_relayer != address(0), "ActionPoolDcRouter:zero address");

        _deCommasTreasurer = _deCommasTreasurerAddress;
        lzEndpoint = ILayerZeroEndpoint(_nativeLZEndpoint);
        _deCommasRelayerAddress = _relayer;
        _nativeChainId = _nativeId;
        _transferOwnership(_msgSender());
    }

    /**
     * @notice Set address of the relayer
     * @param _newRelayer - address of Action Pool contract
     * @dev only deCommas Register
     */
    function setRelayer(address _newRelayer) external override onlyRelayer {
        address oldRelayer = _deCommasRelayerAddress;
        _deCommasRelayerAddress = _newRelayer;
        emit RelayerChanged(msg.sender, oldRelayer, _newRelayer);
    }

    function performAction(
        uint256 _strategyId,
        bytes memory _funcSign,
        uint16 _receiverId,
        bytes memory _receiverAddress,
        uint256 _gasForDstLzReceive
    ) external payable override onlyRelayer {
        _performAction(
            _strategyId,
            _receiverId,
            _receiverAddress,
            _funcSign,
            _gasForDstLzReceive
        );
    }

    /**
     * @notice Performing the function of a building block/router in the source chain and passing a message to it
     * @param _funcSign - destination receiverAddress func parameters encoded in bytes
     * @param _receiver - recipient  of stable tokens in the target chain
     * @param _strategyId - strategy number by which it will be identified
     * @dev only Relayer
     */
    function performToNative(
        bytes memory _funcSign,
        address _receiver,
        uint256 _strategyId
    ) external override onlyRelayer {
        (bool success, bytes memory returnData) = address(_receiver).call(
            _funcSign
        );
        require(success, "ActionPoolDcRouter:call to native bb failed");
        emit Adjusted(_strategyId, abi.encode(_receiver), returnData);
    }

    /**
     * @notice Bridging ERC-20 to the source chain
     * @param _receiverStableToken -
     * @param _stableAmount -
     * @param _finalRecipientId - Lz id for the target contract bridging tokens to the final recipient
     * @param _finalRecipient- final recipient of tokens from the bridge
     * @param _finalStableToken -
     * @param _receiverId - target chain id in LayerZero, see more:
     *       (https://layerzero.gitbook.io/docs/technical-reference/testnet/testnet-addresses)
     * @param _receiverAddress - recipient  of stable tokens in the target chain
     * @param _gasAmount -
     * @param _nativeForDst -
     * @dev only Relayer
     */
    function bridge(
        address _receiverStableToken,
        uint256 _stableAmount,
        uint16 _finalRecipientId,
        address _finalRecipient,
        address _finalStableToken,
        uint16 _receiverId,
        bytes memory _receiverAddress,
        uint256 _gasAmount,
        uint256 _nativeForDst
    ) external payable override onlyRelayer {
        bytes4 funcSelector = bytes4(
            keccak256("bridge(address,uint256,uint16,address,address)")
        );
        bytes memory actionData = abi.encodeWithSelector(
            funcSelector,
            _receiverStableToken,
            _stableAmount,
            _finalRecipientId,
            _finalRecipient,
            _finalStableToken
        );
        uint16 version = 2;
        bytes memory lzEndpointParams = abi.encodePacked(
            version,
            _gasAmount,
            _nativeForDst,
            _receiverAddress
        );
        trustedRemoteLookup[_receiverId] = abi.encodePacked(
            _receiverAddress,
            address(this)
        );
        emit SetTrustedRemoteAddress(_receiverId, _receiverAddress);
        _lzSend(
            _receiverId,
            actionData,
            payable(_msgSender()),
            address(0x0),
            lzEndpointParams,
            msg.value
        );
        emit PerformedBridge(_receiverAddress, actionData);
    }

    /** @dev
    * payload :
        uint16[] calldata _receivingBlocksChainId,
        address[] calldata _receivingBlocks,
        uint256[] calldata _amountsPerBlock,
        address[] calldata _receivingTokens,
        uint256 _strategyId,
        uint256 _strategyTvl,
    *
    */
    function processDeposits(
        bytes memory _payload,
        uint16 _receiverId,
        bytes memory _receiverAddress,
        uint256 _gasAmount,
        uint256 _nativeForDst
    ) external payable override onlyRelayer {
        bytes4 funcSelector = bytes4(keccak256("transferDeposits(bytes)"));
        bytes memory actionData = abi.encodeWithSelector(
            funcSelector,
            _payload
        );
        bytes memory lzEndpointParams = abi.encodePacked(
            uint16(2), // lzSend version
            _gasAmount,
            _nativeForDst,
            _receiverAddress
        );
        trustedRemoteLookup[_receiverId] = abi.encodePacked(
            _receiverAddress,
            address(this)
        );
        emit SetTrustedRemoteAddress(_receiverId, _receiverAddress);
        _lzSend(
            _receiverId,
            actionData,
            payable(_msgSender()),
            address(0x0),
            lzEndpointParams,
            msg.value
        );
        emit ProcessingDeposits(_receiverAddress, actionData);
    }

    /**
     * @notice Bridging ERC-20 to the source chain
     * @param _nativeRecipient -
     * @param _nativeStableToken -
     * @param _stableAmount -
     * @param _receiverLZId -
     * @param _receiverAddress - recipient  of stable tokens in the target chain
     * @param _destinationStableToken -
     * @dev only Relayer
     */
    function bridgeToNative(
        address _nativeRecipient,
        address _nativeStableToken,
        uint256 _stableAmount,
        uint16 _receiverLZId,
        address _receiverAddress,
        address _destinationStableToken
    ) external payable override onlyRelayer {
        bytes4 funcSelector = bytes4(
            keccak256("nativeBridge(address,uint256,uint16,address,address)")
        );
        bytes memory actionData = abi.encodeWithSelector(
            funcSelector,
            _nativeStableToken,
            _stableAmount,
            _receiverLZId,
            _receiverAddress,
            _destinationStableToken
        );
        (bool success, bytes memory returnData) = _nativeRecipient.call{
            value: msg.value
        }(actionData);
        require(success, "ActionPoolDcRouter:call to destination bb failed");
        emit BridgedNative(_nativeRecipient, _stableAmount, returnData);
    }

    /**
     * @notice Rescuing Lost Tokens
     * @param _token - address of the erroneously submitted token to extrication
     * @dev use only deCommasRegister
     */
    function pullOutLossERC20(address _token) external override onlyRelayer {
        IERC20(_token).transfer(
            _deCommasTreasurer,
            IERC20(_token).balanceOf(address(this))
        );
    }

    function initNewBB(
        uint256 _strategyId,
        address _implementation,
        bytes memory _constructorData,
        uint16 _fabricID,
        bytes memory _bbFabric,
        uint256 _gasForDstLzReceive,
        uint256 _nativeForDst
    ) external payable override onlyRelayer {
        bytes4 funcSelector = bytes4(
            keccak256("initNewProxy(uint256,address,bytes)")
        );
        bytes memory actionData = abi.encodeWithSelector(
            funcSelector,
            _strategyId,
            _implementation,
            _constructorData
        );
        if (_fabricID == _nativeChainId) {
            (bool success, bytes memory response) = _bytesToAddress(_bbFabric)
                .call{value: msg.value}(actionData);
            if (!success) {
                revert(_getRevertMsg(response));
            }
        } else {
            bytes memory lzEndpointParams = abi.encodePacked(
                uint16(2), // lzSend version
                _gasForDstLzReceive,
                _nativeForDst,
                _bbFabric
            );
            trustedRemoteLookup[_fabricID] = abi.encodePacked(
                _bbFabric,
                address(this)
            );
            emit SetTrustedRemoteAddress(_fabricID, _bbFabric);
            _lzSend(
                _fabricID,
                actionData,
                payable(_msgSender()),
                address(0x0),
                lzEndpointParams,
                msg.value
            );
        }
    }

    function upgradeBB(
        uint256 _strategyId,
        address _proxy,
        address _newImplementation,
        uint16 _fabricID,
        bytes memory _bbFabric,
        uint256 _gasForDstLzReceive
    ) external payable override onlyRelayer {
        bytes4 funcSelector = bytes4(
            keccak256("upgradeProxyImplementation(uint256,address,address)")
        );
        bytes memory actionData = abi.encodeWithSelector(
            funcSelector,
            _strategyId,
            _proxy,
            _newImplementation
        );
        _performAction(
            _strategyId,
            _fabricID,
            _bbFabric,
            actionData,
            _gasForDstLzReceive
        );
    }

    function approveWithdraw(
        uint256 _withdrawalId,
        uint256 _stableDeTokenPrice,
        uint256 _strategyId,
        uint16 _recipientId,
        bytes memory _recipient,
        uint256 _gasForDstLzReceive
    ) external payable override onlyRelayer {
        bytes4 funcSelector = bytes4(
            keccak256("approveWithdraw(uint256,uint256,uint256)")
        );
        bytes memory actionData = abi.encodeWithSelector(
            funcSelector,
            _stableDeTokenPrice,
            _strategyId,
            _withdrawalId
        );
        _performAction(
            _strategyId,
            _recipientId,
            _recipient,
            actionData,
            _gasForDstLzReceive
        );
    }

    function cancelWithdraw(
        uint256 _withdrawalId,
        uint256 _strategyId,
        uint16 _recipientId,
        bytes memory _recipient,
        uint256 _gasForDstLzReceive
    ) external payable override onlyRelayer {
        bytes4 funcSelector = bytes4(
            keccak256("cancelWithdraw(uint256,uint256)")
        );
        bytes memory actionData = abi.encodeWithSelector(
            funcSelector,
            _withdrawalId,
            _strategyId
        );
        _performAction(
            _strategyId,
            _recipientId,
            _recipient,
            actionData,
            _gasForDstLzReceive
        );
    }

    function setBridge(
        address _newSgBridge,
        uint256 _strategyId,
        uint16 _recipientId,
        bytes memory _recipient,
        uint256 _gasForDstLzReceive
    ) external payable override onlyRelayer {
        bytes4 funcSelector = bytes4(keccak256("setBridge(address)"));
        bytes memory actionData = abi.encodeWithSelector(
            funcSelector,
            _newSgBridge
        );
        _performAction(
            _strategyId,
            _recipientId,
            _recipient,
            actionData,
            _gasForDstLzReceive
        );
    }

    function setStable(
        address _newStableToken,
        uint256 _strategyId,
        uint16 _recipientId,
        bytes memory _recipient,
        uint256 _gasForDstLzReceive
    ) external payable override onlyRelayer {
        bytes4 funcSelector = bytes4(keccak256("setStable(address)"));
        bytes memory actionData = abi.encodeWithSelector(
            funcSelector,
            _newStableToken
        );
        _performAction(
            _strategyId,
            _recipientId,
            _recipient,
            actionData,
            _gasForDstLzReceive
        );
    }

    /**
     * @notice Get nativeChain id in LZ
     * @return uint16  - native chain id in LayerZero, see more:
     *       (https://layerzero.gitbook.io/docs/technical-reference/testnet/testnet-addresses)
     */
    function getNativeChainId() external view override returns (uint16) {
        return _nativeChainId;
    }

    /**
     * @notice Get deCommas Treasurer address
     * @return address - address of deCommas deCommasTreasurer
     */
    function getDeCommasTreasurer() external view override returns (address) {
        return _deCommasTreasurer;
    }

    function getRelayerAddress() external view override returns (address) {
        return _deCommasRelayerAddress;
    }

    function _nonblockingLzReceive(
        uint16, /*_srcChainId */
        bytes memory, /*_srcAddress */
        uint64, /*_nonce*/
        bytes memory /* _payload */
    ) internal override {}

    function _performAction(
        uint256 _strategyId,
        uint16 _receiverId,
        bytes memory _receiverAddress,
        bytes memory _payloadToEndpoint,
        uint256 _gasForDstLzReceive
    ) private {
        uint16 version = 1;
        bytes memory adapterParams = abi.encodePacked(
            version,
            _gasForDstLzReceive
        );
        trustedRemoteLookup[_receiverId] = abi.encodePacked(
            _receiverAddress,
            address(this)
        );
        emit SetTrustedRemoteAddress(_receiverId, _receiverAddress);
        _lzSend(
            _receiverId,
            _payloadToEndpoint,
            payable(_msgSender()),
            address(0x0),
            adapterParams,
            msg.value
        );
        emit Adjusted(_strategyId, _receiverAddress, _payloadToEndpoint);
    }

    function _bytesToAddress(bytes memory _bys)
        internal
        pure
        returns (address addr)
    {
        assembly {
            addr := mload(add(_bys, 20))
        }
    }
}

