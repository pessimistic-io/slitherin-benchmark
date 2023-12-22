//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import {IStargateReceiver, IStargateRouter, IStargateFeeLibrary} from "./IStargate.sol";
import {WardedLiving} from "./WardedLiving.sol";

import "./console.sol";
import "./ISgBridge.sol";
import "./Swapper.sol";

contract SgBridge is Initializable, UUPSUpgradeable, OwnableUpgradeable, IStargateReceiver, WardedLiving, ISgBridge {

    using SafeERC20 for IERC20;

    IStargateRouter public router;
    address public defaultBridgeToken;
    uint16 public currentChainId;


    struct Destination {
        address receiveContract;
        uint256 destinationPool;
    }

    mapping(uint16 => Destination) public supportedDestinations; //destination stargate_chainId => Destination struct
    mapping(address => uint256) public poolIds; // token address => Stargate poolIds for token

    IStargateFeeLibrary public feeLibrary;

    function initialize(
        address stargateRouter_,
        uint16 currentChainId_
    ) public initializer {
        __Ownable_init();

        router = IStargateRouter(stargateRouter_);

        currentChainId = currentChainId_;
        relyOnSender();
        run();
    }

    function setFeeLibrary(address _feeLibrary) external auth {
        feeLibrary = IStargateFeeLibrary(_feeLibrary);
    }

    function setCurrentChainId(uint16 newChainId) external auth {
        currentChainId = newChainId;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // Add stargate pool here. See this table: https://stargateprotocol.gitbook.io/stargate/developers/pool-ids
    function setStargatePoolId(address token, uint256 poolId) external override auth {
        poolIds[token] = poolId;
        IERC20(token).approve(address(router), 115792089237316195423570985008687907853269984665640564039457584007913129639935);
        defaultBridgeToken = token;
    }

    // Set destination.
    // Chain id is here:https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
    // Receiver is this contract deployed on the other chain
    // PoolId is picked from here https://stargateprotocol.gitbook.io/stargate/developers/pool-ids
    function setSupportedDestination(uint16 destChainId, address receiver, uint256 destPoolId) external override auth {
        supportedDestinations[destChainId] = Destination(receiver, destPoolId);
    }

    function isTokenSupported(address token) public override view returns (bool) {
        return true;
    }

    function isTokensSupported(address[] calldata tokens) public override view returns (bool[] memory) {
        bool[] memory response = new bool[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            response[i] = true;
        }
        return response;
    }

    function isPairsSupported(address[][] calldata tokens) public override view returns (bool[] memory) {
        bool[] memory response = new bool[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            response[i] = true;
        }
        return response;
    }

    function createPayload(
        address destAddress,
        address destToken,
        bytes calldata receiverPayload
    ) private pure returns (bytes memory) {
        return abi.encode(destAddress, destToken, receiverPayload);
    }

    function getLzParams() private pure returns (IStargateRouter.lzTxObj memory) {
        return IStargateRouter.lzTxObj({
        dstGasForCall : 800000, // extra gas, if calling smart contract,
        dstNativeAmount : 0, // amount of dust dropped in destination wallet
        //            dstNativeAddr: abi.encodePacked(destinationAddress) // destination wallet for dust
        dstNativeAddr : "0x8E0eeC5bCf1Ee6AB986321349ff4D08019e29918" // destination wallet for dust
        });
    }

    // @dev Returns fee in native and estimated stable coin receive
    function estimateGasFee(
        address _token,
        uint16 _destChainId,
        uint256 _stableAmount,
        bytes calldata _destinationPayload
    ) public override view returns (uint256, uint256) {

        if (_destChainId == currentChainId) {
            return (0, _stableAmount);
        }

        Destination memory destSgBridge = supportedDestinations[_destChainId];
        require(destSgBridge.receiveContract != address(0), "SgBridge/chain-not-supported");

        (uint256 fee,) = router.quoteLayerZeroFee(
            _destChainId,
            1, //SWAP
            abi.encodePacked(destSgBridge.receiveContract, _token),
            createPayload(_token, _token, _destinationPayload),
            getLzParams()
        );

        IStargateFeeLibrary.SwapObj memory swapObj = feeLibrary.getFees(
            poolIds[defaultBridgeToken],
            destSgBridge.destinationPool,
            _destChainId,
            msg.sender,
            _stableAmount
        );
        uint256 fixedCost = 20000;
        uint256 totalFees = swapObj.eqFee + swapObj.eqReward + swapObj.lpFee + swapObj.protocolFee + fixedCost;
        uint256 quote = _stableAmount - totalFees;
        return (fee, quote);
    }

    // To avoid stack too deep errors.
    struct BridgeParams {
        address token;
        uint256 fee;
        uint256 amount;
        uint256 srcPoolId;
        uint16 destChainId;
        uint256 destinationPoolId;
        address destinationAddress;
        address destinationToken;
        address destinationContract;
    }

    function bridgeInternal(
        BridgeParams memory params,
        bytes calldata destinationPayload
    ) internal {

        bytes memory payload = createPayload(
            params.destinationAddress, params.destinationToken, destinationPayload
        );

        router.swap{value: params.fee }(
            params.destChainId,
            params.srcPoolId,
            params.destinationPoolId,
            payable(msg.sender),
            params.amount,
            0, //FIXME!!!
            getLzParams(),
            abi.encodePacked(params.destinationContract),
            payload
        );

        emit Bridge(msg.sender, params.destChainId, params.amount);
    }

    function bridge(address token,
        uint256 amount,
        uint16 destChainId,
        address destinationAddress,
        address destinationToken,
        address routerSrcChain,
        bytes memory srcRoutingCallData,
        bytes calldata dstChainCallData) external override live payable {

        //        require(isTokenSupported(token), "SgBridge/token-not-supported");

        uint256 fee = msg.value;

        if (srcRoutingCallData.length > 0) {
            swapRouter(token, amount, routerSrcChain, srcRoutingCallData);
        } else {
            if (token != address(0x0)) {
                IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            } else {
                fee = msg.value - amount;
            }
        }

        if (currentChainId == destChainId) {
            return;
        }
        Destination memory destination = supportedDestinations[destChainId];
        require(destination.receiveContract != address(0), "SgBridge/chain-not-supported");
        uint256 usdtAmount = IERC20(defaultBridgeToken).balanceOf(address(this));
        uint256 srcPoolId = poolIds[token];
        if (srcPoolId == 0) {//There are no stargate pool for this token => swap on DEX
//            usdtAmount = swap(token, defaultBridgeToken, amount, address(this));
            srcPoolId = poolIds[defaultBridgeToken];
        }

        bridgeInternal(
            BridgeParams(
                token,
                fee,
                usdtAmount,
                srcPoolId,
                destChainId,
                destination.destinationPool,
                destinationAddress,
                destinationToken,
                destination.receiveContract
            ),
            dstChainCallData
        );
    }

    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint _nonce,
        address _token,
        uint _amountLD,
        bytes memory _payload) override external {
        //only-stargate-router can call sgReceive!
        require(msg.sender == address(router), "SgBridge/Forbidden");

        emit PacketReceived(_srcAddress, _payload);

        (address toAddr, address tokenOut, bytes memory destPayload) = abi.decode(_payload, (address, address, bytes));
        if (destPayload.length > 0) {
            IERC20(_token).approve(toAddr, _amountLD);
            externalCall(_token, toAddr, _amountLD, _chainId, destPayload);
            return;
        }

        IERC20(_token).transfer(toAddr, _amountLD);
        emit BridgeSuccess(toAddr, _chainId, tokenOut, _amountLD);
    }

    function externalCall(
        address token,
        address receiver,
        uint256 amount,
        uint16 chainId,
        bytes memory destPayload) private {
//        IERC20(token).transfer(receiver, amount);
        (bool success, bytes memory response) = receiver.call(destPayload);
        if (!success) {
            revert(_getRevertMsg(response));
        }
        emit ExternalCallSuccess(receiver, chainId, token, amount);
    }

    function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) return 'Transaction reverted silently';

        assembly {
        // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }

    function swapRouter(
        address tokenA,
        uint256 amountA,
        address router,
        bytes memory callData
    ) public payable live override {
        if (tokenA != address(0x0) && IERC20(tokenA).allowance(address(this), router) < amountA) {
            IERC20(tokenA).approve(router, type(uint256).max);
        }
        require(IERC20(tokenA).transferFrom(msg.sender, address(this), amountA), "Bridge/stf");
        (bool success, bytes memory returnValues) = router.call(callData);
        require(success, "Bridge/routing-failed!");
    }

    fallback() external payable {
        //do nothing
    }
}

