// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.15;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

import { ITransport } from "./ITransport.sol";
import { VaultChildProxy } from "./VaultChildProxy.sol";
import { VaultParentProxy } from "./VaultParentProxy.sol";
import { VaultChild } from "./VaultChild.sol";
import { VaultParent } from "./VaultParent.sol";

import { VaultBaseExternal } from "./VaultBaseExternal.sol";
import { VaultRiskProfile } from "./IVaultRiskProfile.sol";
import { Accountant } from "./Accountant.sol";
import { Registry } from "./Registry.sol";
import { TransportStorage } from "./TransportStorage.sol";
import { GasFunctionType } from "./ITransport.sol";

import { ILayerZeroReceiver } from "./ILayerZeroReceiver.sol";
import { ILayerZeroEndpoint } from "./ILayerZeroEndpoint.sol";

import { IStargateRouter } from "./IStargateRouter.sol";
import { IStargateReceiver } from "./IStargateReceiver.sol";

import { SafeOwnable } from "./SafeOwnable.sol";

import { Call } from "./Call.sol";

// solhint-disable ordering
contract Transport is
    SafeOwnable,
    ITransport,
    ILayerZeroReceiver,
    IStargateReceiver
{
    using SafeERC20 for IERC20;

    // EVENTS

    event VaultParentCreated(address target);
    event VaultChildCreated(address target);

    function initialize(
        address _registry,
        address _lzEndpoint,
        address _stargateRouter
    ) external onlyOwner {
        TransportStorage.Layout storage l = TransportStorage.layout();
        l.registry = Registry(_registry);
        l.lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        l.stargateRouter = _stargateRouter;
    }

    receive() external payable {}

    modifier whenNotPaused() {
        require(!registry().paused(), 'paused');
        _;
    }

    modifier onlyThis() {
        require(address(this) == msg.sender, 'not this');
        _;
    }

    modifier onlyVaultParent() {
        require(registry().isVaultParent(msg.sender), 'not parent vault');
        _;
    }

    modifier onlyVaultChild() {
        require(registry().isVaultChild(msg.sender), 'not child vault');
        _;
    }

    modifier onlyVault() {
        require(registry().isVault(msg.sender), 'not child vault');
        _;
    }

    function registry() public view returns (Registry) {
        TransportStorage.Layout storage l = TransportStorage.layout();
        return l.registry;
    }

    function bridgeApprovalCancellationTime() public view returns (uint256) {
        TransportStorage.Layout storage l = TransportStorage.layout();
        return l.bridgeApprovalCancellationTime;
    }

    function lzEndpoint() public view returns (ILayerZeroEndpoint) {
        TransportStorage.Layout storage l = TransportStorage.layout();
        return l.lzEndpoint;
    }

    function trustedRemoteLookup(
        uint16 remoteChainId
    ) public view returns (bytes memory) {
        TransportStorage.Layout storage l = TransportStorage.layout();
        return l.trustedRemoteLookup[remoteChainId];
    }

    function stargateRouter() public view returns (address) {
        TransportStorage.Layout storage l = TransportStorage.layout();
        return l.stargateRouter;
    }

    function stargateAssetToDstPoolId(
        uint16 dstChainId,
        address srcBridgeToken
    ) public view returns (uint256) {
        TransportStorage.Layout storage l = TransportStorage.layout();
        return l.stargateAssetToDstPoolId[dstChainId][srcBridgeToken];
    }

    function stargateAssetToSrcPoolId(
        address bridgeToken
    ) public view returns (uint256) {
        TransportStorage.Layout storage l = TransportStorage.layout();
        return l.stargateAssetToSrcPoolId[bridgeToken];
    }

    function getGasUsage(
        GasFunctionType gasFunctionType
    ) public view returns (uint) {
        TransportStorage.Layout storage l = TransportStorage.layout();
        return l.gasUsage[gasFunctionType];
    }

    function lzReceive(
        uint16 srcChainId,
        bytes calldata srcAddress,
        uint64, // nonce
        bytes calldata payload
    ) external {
        require(
            msg.sender == address(lzEndpoint()),
            'LzApp: invalid endpoint caller'
        );

        bytes memory trustedRemote = trustedRemoteLookup(srcChainId);
        require(
            srcAddress.length == trustedRemote.length &&
                keccak256(srcAddress) == keccak256(trustedRemote),
            'LzApp: invalid source sending contract'
        );
        Call._call(address(this), payload);
    }

    function getLzFee(
        GasFunctionType gasFunctionType,
        uint16 dstChainId
    ) public view returns (uint256 sendFee, uint dstGasForCall) {
        // We just use the largest message for now
        ChildVault memory childVault = ChildVault({
            chainId: 0,
            vault: address(0)
        });
        ChildVault[] memory childVaults = new ChildVault[](2);
        childVaults[0] = childVault;
        childVaults[1] = childVault;

        VaultChildCreationRequest memory request = VaultChildCreationRequest({
            parentVault: address(0),
            parentChainId: 0,
            newChainId: 0,
            manager: address(0),
            riskProfile: VaultRiskProfile.low,
            children: childVaults
        });

        bytes memory payload = abi.encodeWithSelector(
            this.sendVaultChildCreationRequest.selector,
            request
        );

        address dstAddr = _getTrustedRemoteDestination(dstChainId);
        dstGasForCall = getGasUsage(gasFunctionType);

        (sendFee, ) = lzEndpoint().estimateFees(
            dstChainId,
            dstAddr,
            payload,
            false,
            abi.encodePacked(uint16(1), dstGasForCall)
        );
    }

    ///
    /// Stargate
    ///

    function getBridgeAssetQuote(
        uint16 dstChainId, // Stargate/LayerZero chainId
        address dstVault, // the address to send the destination tokens to
        uint16 parentChainId,
        address parentVault
    ) external view returns (uint fee) {
        address dstAddr = _getTrustedRemoteDestination(dstChainId);

        // encode payload data to send to destination contract, which it will handle with sgReceive()
        bytes memory data = abi.encode(
            SGReceivePayload({
                dstVault: dstVault,
                srcVault: msg.sender,
                parentChainId: parentChainId,
                parentVault: parentVault
            })
        );

        // this contract calls stargate swap()
        uint DST_GAS = getGasUsage(GasFunctionType.sgReceive);
        IStargateRouter.lzTxObj memory lzTxObj = IStargateRouter.lzTxObj({
            ///
            /// This needs to be enough for the sgReceive to execute successfully on the remote
            /// We will need to accurately access how much the Transport.sgReceive function needs
            ///
            dstGasForCall: DST_GAS,
            // Not quite sure what these are for sg doco very vague
            dstNativeAmount: 0,
            dstNativeAddr: abi.encodePacked(dstVault)
        });

        (fee, ) = IStargateRouter(stargateRouter()).quoteLayerZeroFee(
            dstChainId,
            1, // function type: see Stargate Bridge.sol for all types
            abi.encodePacked(dstAddr), // destination contract. it must implement sgReceive()
            data,
            lzTxObj
        );
    }

    function bridgeAsset(
        uint16 dstChainId, // Stargate/LayerZero chainId
        address dstVault, // the address to send the destination tokens to
        uint16 parentChainId,
        address parentVault,
        address bridgeToken, // the address of the native ERC20 to swap() - *must* be the token for the poolId
        uint amount,
        uint minAmountOut
    ) external payable onlyVault whenNotPaused {
        require(amount > 0, 'error: swap() requires amount > 0');
        address dstAddr = _getTrustedRemoteDestination(dstChainId);

        uint srcPoolId = stargateAssetToSrcPoolId(bridgeToken);
        uint dstPoolId = stargateAssetToDstPoolId(dstChainId, bridgeToken);
        require(srcPoolId != 0, 'no srcPoolId');
        require(dstPoolId != 0, 'no dstPoolId');

        // encode payload data to send to destination contract, which it will handle with sgReceive()
        bytes memory data = abi.encode(
            SGReceivePayload({
                dstVault: dstVault,
                srcVault: msg.sender,
                parentChainId: parentChainId,
                parentVault: parentVault
            })
        );

        uint DST_GAS = getGasUsage(GasFunctionType.sgReceive);
        IStargateRouter.lzTxObj memory lzTxObj = IStargateRouter.lzTxObj({
            ///
            /// This needs to be enough for the sgReceive to execute successfully on the remote
            /// We will need to accurately access how much the Transport.sgReceive function needs
            ///
            dstGasForCall: DST_GAS,
            dstNativeAmount: 0,
            dstNativeAddr: abi.encodePacked(dstVault)
        });

        // this contract calls stargate swap()
        IERC20(bridgeToken).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(bridgeToken).safeApprove(address(stargateRouter()), amount);

        // Stargate's Router.swap() function sends the tokens to the destination chain.
        IStargateRouter(stargateRouter()).swap{ value: msg.value }(
            dstChainId, // the destination chain id
            srcPoolId, // the source Stargate poolId
            dstPoolId, // the destination Stargate poolId
            payable(address(this)), // refund adddress. if msg.sender pays too much gas, return extra eth
            amount, // total tokens to send to destination chain
            minAmountOut, // min amount allowed out
            lzTxObj, // default lzTxObj
            abi.encodePacked(dstAddr), // destination address, the sgReceive() implementer
            data // bytes payload
        );
    }

    ///
    /// Message senders
    ///

    function sendChangeManagerRequest(
        ChangeManagerRequest memory request
    ) external payable onlyVaultParent whenNotPaused {
        _send(
            request.child.chainId,
            abi.encodeWithSelector(this.changeManager.selector, request),
            msg.value,
            getGasUsage(GasFunctionType.standard)
        );
    }

    function sendWithdrawRequest(
        WithdrawRequest memory request
    ) external payable onlyVaultParent whenNotPaused {
        _send(
            request.child.chainId,
            abi.encodeWithSelector(this.withdraw.selector, request),
            msg.value,
            getGasUsage(GasFunctionType.withdraw)
        );
    }

    function sendBridgeApproval(
        BridgeApprovalRequest memory request
    ) external payable onlyVaultParent whenNotPaused {
        _send(
            request.approvedChainId,
            abi.encodeWithSelector(this.bridgeApproval.selector, request),
            msg.value,
            getGasUsage(GasFunctionType.standard)
        );
    }

    function sendBridgeApprovalCancellation(
        BridgeApprovalCancellationRequest memory request
    ) external payable onlyVaultChild whenNotPaused {
        _send(
            request.parentChainId,
            abi.encodeWithSelector(
                this.bridgeApprovalCancellation.selector,
                request
            ),
            msg.value,
            getGasUsage(GasFunctionType.standard)
        );
    }

    function sendValueUpdateRequest(
        ValueUpdateRequest memory request
    ) external payable onlyVault whenNotPaused {
        _send(
            request.child.chainId,
            abi.encodeWithSelector(this.getVaultValue.selector, request),
            msg.value,
            getGasUsage(GasFunctionType.getVaultValue)
        );
    }

    function sendVaultChildCreationRequest(
        VaultChildCreationRequest memory request
    ) external payable onlyVaultParent whenNotPaused {
        require(
            _getTrustedRemoteDestination(request.newChainId) != address(0),
            'unsupported destination chain'
        );
        _send(
            request.newChainId,
            abi.encodeWithSelector(this.createVaultChild.selector, request),
            msg.value,
            getGasUsage(GasFunctionType.createChild)
        );
    }

    /// Return message senders

    function sendAddSiblingRequest(
        AddVaultSiblingRequest memory request
    ) external onlyVaultParent whenNotPaused {
        (uint fee, uint gas) = registry().transport().getLzFee(
            GasFunctionType.standard,
            request.child.chainId
        );
        _send(
            request.child.chainId,
            abi.encodeWithSelector(this.addSibling.selector, request),
            fee,
            gas
        );
    }

    function sendWithdrawComplete(WithdrawComplete memory request) internal {
        (uint fee, uint gas) = registry().transport().getLzFee(
            GasFunctionType.standard,
            request.parentChainId
        );
        _send(
            request.parentChainId,
            abi.encodeWithSelector(this.withdrawComplete.selector, request),
            fee,
            gas
        );
    }

    function _sendValueUpdatedRequest(
        ValueUpdatedRequest memory request
    ) internal {
        (uint fee, uint gas) = registry().transport().getLzFee(
            GasFunctionType.standard,
            request.parentChainId
        );
        _send(
            request.parentChainId,
            abi.encodeWithSelector(this.updateVaultValue.selector, request),
            fee,
            gas
        );
    }

    function _sendSGBridgedAssetAcknowledment(
        SGBridgedAssetReceivedAcknoledgementRequest memory request
    ) internal {
        (uint fee, uint gas) = registry().transport().getLzFee(
            GasFunctionType.standard,
            request.parentChainId
        );
        _send(
            request.parentChainId,
            abi.encodeWithSelector(
                this.sgBridgedAssetReceived.selector,
                request
            ),
            fee,
            gas
        );
    }

    function _sendChildCreatedRequest(
        ChildCreatedRequest memory request
    ) internal {
        (uint fee, uint gas) = registry().transport().getLzFee(
            GasFunctionType.standard,
            request.parentChainId
        );
        _send(
            request.parentChainId,
            abi.encodeWithSelector(this.childCreated.selector, request),
            fee,
            gas
        );
    }

    ///
    /// Message received callbacks
    ///

    function bridgeApprovalCancellation(
        BridgeApprovalCancellationRequest memory request
    ) public onlyThis {
        VaultParent(request.parentVault).receiveBridgeApprovalCancellation(
            request.requester
        );
    }

    function bridgeApproval(
        BridgeApprovalRequest memory request
    ) public onlyThis {
        VaultChild(request.approvedVault).receiveBridgeApproval();
    }

    function withdraw(WithdrawRequest memory request) public onlyThis {
        VaultChild(request.child.vault).receiveWithdrawRequest(
            request.tokenId,
            request.withdrawer,
            request.portion
        );

        sendWithdrawComplete(
            ITransport.WithdrawComplete({
                parentChainId: request.parentChainId,
                parentVault: request.parentVault
            })
        );
    }

    function withdrawComplete(WithdrawComplete memory request) public onlyThis {
        VaultParent(request.parentVault).receiveWithdrawComplete();
    }

    function getVaultValue(ValueUpdateRequest memory request) public onlyThis {
        try
            // This would fail if for instance chainlink timeout
            // If a callback fails the message is deemed failed to deliver by LZ and is queued
            // This is not the behaviour we want
            VaultChild(request.child.vault).getVaultValue()
        returns (uint _minValue, uint _maxValue) {
            _sendValueUpdatedRequest(
                ValueUpdatedRequest({
                    parentChainId: request.parentChainId,
                    parentVault: request.parentVault,
                    child: request.child,
                    time: block.timestamp,
                    minValue: _minValue,
                    maxValue: _maxValue
                })
            );
        } catch {}
    }

    function updateVaultValue(
        ValueUpdatedRequest memory request
    ) public onlyThis {
        VaultParent(request.parentVault).receiveChildValue(
            request.child.chainId,
            request.minValue,
            request.maxValue,
            request.time
        );
    }

    function createVaultChild(
        VaultChildCreationRequest memory request
    ) public onlyThis {
        address child = _deployChild(
            request.parentChainId,
            request.parentVault,
            request.manager,
            request.riskProfile,
            request.children
        );
        _sendChildCreatedRequest(
            ChildCreatedRequest({
                parentVault: request.parentVault,
                parentChainId: request.parentChainId,
                newChild: ChildVault({
                    chainId: registry().chainId(),
                    vault: child
                })
            })
        );
    }

    function childCreated(ChildCreatedRequest memory request) public onlyThis {
        VaultParent(request.parentVault).receiveChildCreated(
            request.newChild.chainId,
            request.newChild.vault
        );
    }

    function addSibling(AddVaultSiblingRequest memory request) public onlyThis {
        VaultChild(request.child.vault).receiveAddSibling(
            request.newSibling.chainId,
            request.newSibling.vault
        );
    }

    function changeManager(
        ChangeManagerRequest memory request
    ) public onlyThis {
        VaultChild(request.child.vault).receiveManagerChange(
            request.newManager
        );
    }

    function createParentVault(
        string memory name,
        string memory symbol,
        address manager,
        uint streamingFee,
        uint performanceFee,
        VaultRiskProfile riskProfile
    ) external whenNotPaused returns (address deployment) {
        return
            _createParentVault(
                name,
                symbol,
                manager,
                streamingFee,
                performanceFee,
                riskProfile
            );
    }

    function createParentAndChildVault(
        string memory name,
        string memory symbol,
        address manager,
        uint streamingFee,
        uint performanceFee,
        VaultRiskProfile riskProfile,
        uint16 childChainId,
        uint lzFee
    ) external payable whenNotPaused returns (address deployment) {
        address parentVault = _createParentVault(
            name,
            symbol,
            manager,
            streamingFee,
            performanceFee,
            riskProfile
        );
        VaultParent(parentVault).requestCreateChild{ value: msg.value }(
            childChainId,
            lzFee
        );
        return parentVault;
    }

    // sgReceive() - the destination contract must implement this function to receive the tokens and payload
    function sgReceive(
        uint16, // _srcChainId,
        bytes memory, // _srcAddress
        uint, // _nonce
        address _token,
        uint amountLD,
        bytes memory _payload
    ) external override {
        require(
            msg.sender == address(stargateRouter()),
            'only stargate router can call sgReceive!'
        );
        SGReceivePayload memory payload = abi.decode(
            _payload,
            (SGReceivePayload)
        );
        // send transfer _token/amountLD to _toAddr
        IERC20(_token).transfer(payload.dstVault, amountLD);
        VaultBaseExternal(payload.dstVault).receiveBridgedAsset(_token);
        // Already on the parent chain - no need to send a message
        if (registry().chainId() == payload.parentChainId) {
            this.sgBridgedAssetReceived(
                SGBridgedAssetReceivedAcknoledgementRequest({
                    parentChainId: payload.parentChainId,
                    parentVault: payload.parentVault
                })
            );
        } else {
            _sendSGBridgedAssetAcknowledment(
                SGBridgedAssetReceivedAcknoledgementRequest({
                    parentChainId: payload.parentChainId,
                    parentVault: payload.parentVault
                })
            );
        }
    }

    function setTrustedRemoteAddress(
        uint16 _remoteChainId,
        bytes calldata _remoteAddress
    ) external onlyOwner {
        TransportStorage.Layout storage l = TransportStorage.layout();
        l.trustedRemoteLookup[_remoteChainId] = abi.encodePacked(
            _remoteAddress,
            address(this)
        );
    }

    function setSGAssetToSrcPoolId(
        address asset,
        uint poolId
    ) external onlyOwner {
        TransportStorage.Layout storage l = TransportStorage.layout();
        l.stargateAssetToSrcPoolId[asset] = poolId;
    }

    function setSGAssetToDstPoolId(
        uint16 chainId,
        address asset,
        uint poolId
    ) external onlyOwner {
        TransportStorage.Layout storage l = TransportStorage.layout();
        l.stargateAssetToDstPoolId[chainId][asset] = poolId;
    }

    function setGasUsage(
        GasFunctionType gasUsage,
        uint gas
    ) external onlyOwner {
        TransportStorage.Layout storage l = TransportStorage.layout();
        l.gasUsage[gasUsage] = gas;
    }

    function setBridgeApprovalCancellationTime(uint time) external onlyOwner {
        TransportStorage.Layout storage l = TransportStorage.layout();
        l.bridgeApprovalCancellationTime = time;
    }

    function _send(
        uint16 dstChainId,
        bytes memory payload,
        uint sendFee,
        uint dstGasForCall
    ) internal {
        lzEndpoint().send{ value: sendFee }(
            dstChainId,
            trustedRemoteLookup(dstChainId),
            payload,
            payable(address(this)),
            payable(address(this)),
            abi.encodePacked(uint16(1), dstGasForCall)
        );
    }

    function _getTrustedRemoteDestination(
        uint16 dstChainId
    ) internal view returns (address dstAddr) {
        bytes memory trustedRemote = trustedRemoteLookup(dstChainId);
        require(
            trustedRemote.length != 0,
            'LzApp: destination chain is not a trusted source'
        );
        assembly {
            dstAddr := mload(add(trustedRemote, 20))
        }
    }

    function _createParentVault(
        string memory name,
        string memory symbol,
        address manager,
        uint streamingFee,
        uint performanceFee,
        VaultRiskProfile riskProfile
    ) internal returns (address deployment) {
        require(
            registry().parentVaultDiamond() != address(0),
            'not parent chain'
        );
        deployment = address(
            new VaultParentProxy(registry().parentVaultDiamond())
        );

        VaultParent(deployment).initialize(
            name,
            symbol,
            manager,
            streamingFee,
            performanceFee,
            riskProfile,
            registry()
        );

        registry().addVaultParent(deployment);

        emit VaultParentCreated(deployment);
        registry().emitEvent();
    }

    function _deployChild(
        uint16 parentChainId,
        address parentVault,
        address manager,
        VaultRiskProfile riskProfile,
        Transport.ChildVault[] memory children
    ) internal whenNotPaused returns (address deployment) {
        deployment = address(
            new VaultChildProxy(registry().childVaultDiamond())
        );
        VaultChild(deployment).initialize(
            parentChainId,
            parentVault,
            manager,
            riskProfile,
            registry(),
            children
        );
        registry().addVaultChild(deployment);

        emit VaultChildCreated(deployment);
        registry().emitEvent();
    }

    function sgBridgedAssetReceived(
        SGBridgedAssetReceivedAcknoledgementRequest memory request
    ) public onlyThis {
        VaultParent(request.parentVault).receiveBridgedAssetAcknowledgement();
    }
}

