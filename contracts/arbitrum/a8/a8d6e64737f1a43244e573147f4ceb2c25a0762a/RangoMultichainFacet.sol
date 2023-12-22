// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./IRangoMultichain.sol";
import "./IRango.sol";
import "./IMultichainRouter.sol";
import "./ReentrancyGuard.sol";
import "./LibTransform.sol";
import "./LibSwapper.sol";
import "./LibDiamond.sol";
import "./LibInterchain.sol";
import "./Interchain.sol";

/// TODO: read and think how interchain message works in multichain
/// TODO: better comments & docs

/// @title The root contract that handles Rango's interaction with MultichainOrg bridge
/// @author George
contract RangoMultichainFacet is IRango, ReentrancyGuard, IRangoMultichain, IAnycallProxy {

    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.multichain")
    bytes32 internal constant MULTICHAIN_NAMESPACE = hex"13c8a23e4f93052e4f541b4dd19c72a5c4c1e8d163db3bede27c064fc6d5767c";

    struct MultichainStorage {
        /// @notice List of whitelisted MultichainOrg routers in the current chain
        mapping(address => bool) multichainRouters;
        mapping(address => bool) multichainExecutors;
    }

    /// @notice Notifies that some new router addresses are whitelisted
    /// @param _addresses The newly whitelisted addresses
    event MultichainRoutersAdded(address[] _addresses);

    /// @notice Notifies that some router addresses are blacklisted
    /// @param _addresses The addresses that are removed
    event MultichainRoutersRemoved(address[] _addresses);

    /// @notice Notifies that some new router addresses are whitelisted
    /// @param _addresses The newly whitelisted addresses
    event MultichainExecutorsAdded(address[] _addresses);

    /// @notice Notifies that some router addresses are blacklisted
    /// @param _addresses The addresses that are removed
    event MultichainExecutorsRemoved(address[] _addresses);

    /// @notice The constructor of this contract
    /// @param _routers The address of whitelist contracts for bridge routers
    /// @param _executors The address of whitelist contracts for executors calling this contract on destination
    function initMultichain(address[] calldata _routers, address[] calldata _executors) external {
        LibDiamond.enforceIsContractOwner();
        addMultichainRoutersInternal(_routers);
        addMultichainExecutorsInternal(_executors);
    }

    /// @notice Enables the contract to receive native ETH token from other contracts including WETH contract
    receive() external payable {}

    /// Only permit allowed executors
    modifier onlyAllowedExecutors(){
        require(getMultichainStorage().multichainExecutors[msg.sender] == true, "not allowed");
        _;
    }

    /// @notice Adds a list of new addresses to the whitelisted MultichainOrg routers
    /// @param routers The list of new routers
    function addMultichainRouters(address[] calldata routers) public {
        LibDiamond.enforceIsContractOwner();
        addMultichainRoutersInternal(routers);
    }

    /// @notice Adds a list of new addresses to the whitelisted MultichainOrg executors
    /// @param executors The list of new executors
    function addMultichainExecutors(address[] calldata executors) public {
        LibDiamond.enforceIsContractOwner();
        addMultichainExecutorsInternal(executors);
    }

    /// @notice Removes a list of routers from the whitelisted addresses
    /// @param _routers The list of addresses that should be deprecated
    function removeMultichainRouters(address[] calldata _routers) external {
        LibDiamond.enforceIsContractOwner();
        MultichainStorage storage s = getMultichainStorage();
        for (uint i = 0; i < _routers.length; i++) {
            delete s.multichainRouters[_routers[i]];
        }
        emit MultichainRoutersRemoved(_routers);
    }

    /// @notice Removes a list of executors from the whitelisted addresses
    /// @param _executors The list of addresses that should be deprecated
    function removeMultichainExecutors(address[] calldata _executors) external {
        LibDiamond.enforceIsContractOwner();
        MultichainStorage storage s = getMultichainStorage();
        for (uint i = 0; i < _executors.length; i++) {
            delete s.multichainExecutors[_executors[i]];
        }
        emit MultichainExecutorsRemoved(_executors);
    }

    /// @inheritdoc IAnycallProxy
    function exec(
        address token,
        address receiver,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant onlyAllowedExecutors returns (bool success, bytes memory result){
        Interchain.RangoInterChainMessage memory m = abi.decode((data), (Interchain.RangoInterChainMessage));
        (,, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(token, amount, m);
        success = status == CrossChainOperationStatus.Succeeded;
        result = "";
    }
    /// Bridge functions

    /// @notice Executes a DEX (arbitrary) call + a MultichainOrg bridge call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function multichainSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoMultichain.MultichainBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        (uint out,) = LibSwapper.onChainSwapsPreBridge(request, calls, 0);

        doMultichainBridge(bridgeRequest, request.toToken, out);
        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            bridgeRequest.receiverAddress,
            "",
            bridgeRequest.receiverChainID,
            false,
            false,
            uint8(BridgeType.Multichain),
            request.dAppTag
        );
    }

    /// @notice Executes a bridge through Multichain
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function multichainBridge(
        IRangoMultichain.MultichainBridgeRequest memory request,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        if (token != LibSwapper.ETH) {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
            LibSwapper.approve(token, request.multichainRouter, amount);
        } else {
            require(msg.value >= amountWithFee);
        }
        LibSwapper.collectFees(bridgeRequest);
        if (request.actionType == MultichainBridgeType.OUT_NATIVE) {
            require(msg.value >= amount, 'Insufficient ETH OUT_NATIVE');
        }
        doMultichainBridge(request, token, amount);
        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            request.receiverAddress,
            "",
            request.receiverChainID,
            false,
            false,
            uint8(BridgeType.Multichain),
            bridgeRequest.dAppTag
        );
    }

    /// @param anycallTargetContractOnDestChain the contract on the destination chain that is called.
    function multichainBridgeAndAnyCall(
        IRangoMultichain.MultichainBridgeRequest memory request,
        RangoBridgeRequest memory bridgeRequest,
        string calldata anycallTargetContractOnDestChain,
        Interchain.RangoInterChainMessage memory imMessage
    ) external payable nonReentrant {
        address token = bridgeRequest.token;
        uint amountWithFee = bridgeRequest.amount + LibSwapper.sumFees(bridgeRequest);
        if (token != LibSwapper.ETH) {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
            LibSwapper.approve(token, request.multichainRouter, bridgeRequest.amount);
        } else {
            require(msg.value >= amountWithFee);
        }
        LibSwapper.collectFees(bridgeRequest);
        if (request.actionType == MultichainBridgeType.OUT_NATIVE) {
            require(msg.value >= bridgeRequest.amount, 'Insufficient ETH OUT_NATIVE');
        }
        doMultichainBridgeAndAnyCall(request, token, bridgeRequest.amount, anycallTargetContractOnDestChain, imMessage);
        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            bridgeRequest.amount,
            request.receiverAddress,
            keccak256(abi.encode(imMessage)),
            request.receiverChainID,
            true,
            false,
            uint8(BridgeType.Multichain),
            bridgeRequest.dAppTag
        );
    }

    /// @param anycallTargetContractOnDestChain the contract on the destination chain that is called.
    function multichainSwapAndAnyCall(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoMultichain.MultichainBridgeRequest memory bridgeRequest,
        string calldata anycallTargetContractOnDestChain,
        Interchain.RangoInterChainMessage memory imMessage
    ) external payable nonReentrant {
        (uint out,) = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
        if (bridgeRequest.actionType == MultichainBridgeType.OUT_NATIVE) {
            require(request.toToken == LibSwapper.ETH, "token must be null");
        }
        doMultichainBridgeAndAnyCall(bridgeRequest, request.toToken, out, anycallTargetContractOnDestChain, imMessage);
        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            bridgeRequest.receiverAddress,
            keccak256(abi.encode(imMessage)),
            bridgeRequest.receiverChainID,
            true,
            false,
            uint8(BridgeType.Multichain),
            request.dAppTag
        );
    }

    /// @notice Executes a MultichainOrg bridge call
    /// @param fromToken The address of bridging token
    /// @param inputAmount The amount of the token to be bridged
    /// @param request The other required field by MultichainOrg bridge
    function doMultichainBridge(
        MultichainBridgeRequest memory request,
        address fromToken,
        uint inputAmount
    ) internal {
        MultichainStorage storage s = getMultichainStorage();
        require(s.multichainRouters[request.multichainRouter], 'Requested router address not whitelisted');

        if (request.actionType != MultichainBridgeType.OUT_NATIVE) {
            LibSwapper.approve(fromToken, request.multichainRouter, inputAmount);
        } else {
            require(fromToken == LibSwapper.ETH, 'invalid token');
        }

        IMultichainRouter router = IMultichainRouter(request.multichainRouter);

        if (request.actionType == MultichainBridgeType.OUT) {
            router.anySwapOut(request.underlyingToken, request.receiverAddress, inputAmount, request.receiverChainID);
        } else if (request.actionType == MultichainBridgeType.OUT_UNDERLYING) {
            router.anySwapOutUnderlying(request.underlyingToken, request.receiverAddress, inputAmount, request.receiverChainID);
        } else if (request.actionType == MultichainBridgeType.OUT_NATIVE) {
            router.anySwapOutNative{value : inputAmount}(request.underlyingToken, request.receiverAddress, request.receiverChainID);
        } else {
            revert();
        }
    }

    /// @notice Executes a MultichainOrg token bridge and call
    function doMultichainBridgeAndAnyCall(
        MultichainBridgeRequest memory request,
        address fromToken,
        uint inputAmount,
        string calldata anycallTargetContractOnDestChain,
        Interchain.RangoInterChainMessage memory imMessage
    ) internal {
        MultichainStorage storage s = getMultichainStorage();
        require(s.multichainRouters[request.multichainRouter], 'router not allowed');

        if (request.actionType != MultichainBridgeType.OUT_NATIVE) {
            LibSwapper.approve(fromToken, request.multichainRouter, inputAmount);
        } else {
            require(fromToken == LibSwapper.ETH, 'invalid token');
        }

        IMultichainV7Router router = IMultichainV7Router(request.multichainRouter);

        if (request.actionType == MultichainBridgeType.OUT) {
            router.anySwapOutAndCall(
                request.underlyingToken,
                LibTransform.addressToString(request.receiverAddress),
                inputAmount,
                request.receiverChainID,
                anycallTargetContractOnDestChain,
                abi.encode(imMessage)
            );
        } else if (request.actionType == MultichainBridgeType.OUT_UNDERLYING) {
            router.anySwapOutUnderlyingAndCall(
                request.underlyingToken,
                LibTransform.addressToString(request.receiverAddress),
                inputAmount,
                request.receiverChainID,
                anycallTargetContractOnDestChain,
                abi.encode(imMessage)
            );
        } else if (request.actionType == MultichainBridgeType.OUT_NATIVE) {
            router.anySwapOutNativeAndCall{value : inputAmount}(
                request.underlyingToken,
                LibTransform.addressToString(request.receiverAddress),
                request.receiverChainID,
                anycallTargetContractOnDestChain,
                abi.encode(imMessage)
            );
        } else {
            revert();
        }
    }

    function addMultichainRoutersInternal(address[] calldata _addresses) private {
        MultichainStorage storage s = getMultichainStorage();

        for (uint i = 0; i < _addresses.length; i++) {
            s.multichainRouters[_addresses[i]] = true;
        }

        emit MultichainRoutersAdded(_addresses);
    }

    function addMultichainExecutorsInternal(address[] calldata _addresses) private {
        MultichainStorage storage s = getMultichainStorage();
        for (uint i = 0; i < _addresses.length; i++) {
            s.multichainExecutors[_addresses[i]] = true;
        }
        emit MultichainExecutorsAdded(_addresses);
    }

    /// @dev fetch local storage
    function getMultichainStorage() private pure returns (MultichainStorage storage s) {
        bytes32 namespace = MULTICHAIN_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }

}
