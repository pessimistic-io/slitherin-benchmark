// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./IBridge.sol";
import "./SafeERC20.sol";
import "./PbPool.sol";
import "./Signers.sol";
import "./OrderLib.sol";
import "./VerifySigEIP712.sol";
import "./Structs.sol";
import "./AssetLib.sol";

interface IMultichainERC20 {
    function Swapout(uint256 amount, address bindaddr) external returns (bool);
}

contract Vault is Ownable, Signers, VerifySigEIP712 {
    using SafeERC20 for IERC20;

    IERC20 private constant NATIVE_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    //ETH chain
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public ROUTER;
    address public CBRIDGE;
    address public POLYBRIDGE;
    address public PORTAL;
    address private dev;
    uint256 feePercent = 0;
    mapping(address => mapping(uint64 => BridgeInfo)) public userBridgeInfo;
    mapping(bytes32 => BridgeInfo) public transferInfo;
    mapping(bytes32 => bool) public transfers;
    mapping(address => address) public anyTokenAddress;
    mapping(address => bool) public allowedRouter;

    event Swap(address user, address srcToken, address toToken, uint256 amount, uint256 returnAmount);
    event Bridge(address user, uint64 chainId, address srcToken, address toDstToken, uint256 fromAmount, bytes32 transferId, string bridge);
    event Relayswap(address receiver, address toToken, uint256 returnAmount);

    receive() external payable {}

    constructor(
        address router,
        address cbridge,
        address poly,
        address portal
    ) {
        ROUTER = router;
        CBRIDGE = cbridge;
        POLYBRIDGE = poly;
        PORTAL = portal;
    }

    /// @param routers multichain router address
    /// Whitelist only the router address of multichain
    function initMultichain(address[] calldata routers) external {
        require(msg.sender == dev || msg.sender == owner());
        uint256 len = routers.length;
        for (uint256 i; i < len; ) {
            if (routers[i] == address(0)) {
                revert();
            }
            allowedRouter[routers[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    /// @param mappings Mapping between multichain anyToken and real Token
    function updateAddressMapping(AnyMapping[] calldata mappings) external {
        require(msg.sender == dev || msg.sender == owner());
        for (uint64 i; i < mappings.length; i++) {
            anyTokenAddress[mappings[i].tokenAddress] = mappings[i].anyTokenAddress;
        }
    }

    /// @param bDesc Parameters to enter cBridge.
    /// address srcToken;
    /// uint256 amount;
    /// address receiver;
    /// uint64 dstChainId;
    /// uint64 nonce;
    /// uint32 maxSlippage;
    function cBridge(CBridgeDescription calldata bDesc) external payable {
        bool isNotNative = !_isNative(IERC20(bDesc.srcToken));
        if (isNotNative) {
            IERC20(bDesc.srcToken).safeTransferFrom(msg.sender, address(this), bDesc.amount);
        }
        _cBridgeStart(bDesc.amount, bDesc);
    }

    /// @param _Pdesc Parameters to enter PortalBridge.
    /// address token;
    /// uint256 amount;
    /// uint16 recipientChain;
    /// address recipient;
    /// uint32 nonce;
    /// uint256 arbiterFee;
    /// bytes payload;
    function PortalBridge(PortalBridgeDescription calldata _Pdesc) external payable {
        bool isNotNative = !_isNative(IERC20(_Pdesc.token));
        if (isNotNative) {
            IERC20(_Pdesc.token).safeTransferFrom(msg.sender, address(this), _Pdesc.amount);
        }
        _portalBridgeStart(_Pdesc.amount, _Pdesc);
    }

    function polyBridge(PolyBridgeDescription calldata pDesc) public payable {
        bool isNotNative = !_isNative(IERC20(pDesc.fromAsset));
        if (isNotNative) {
            IERC20(pDesc.fromAsset).safeTransferFrom(msg.sender, address(this), pDesc.amount);
        }
        _polyBridgeStart(pDesc.amount, pDesc);
    }

    function multiChainBridge(MultiChainDescription calldata mDesc) public payable {
        bool isNative = !_isNative(IERC20(mDesc.srcToken));

        if (isNative) {
            IERC20(mDesc.srcToken).safeTransferFrom(msg.sender, address(this), mDesc.amount);
        }

        _multiChainBridgeStart(mDesc.amount, mDesc);
    }

    function swapRouter(SwapData calldata _swap) external payable {
        _isNativeDeposit(IERC20(_swap.srcToken), _swap.amount);
        _userSwapStart(_swap);
    }

    function swapCBridge(SwapData calldata _swap, CBridgeDescription calldata bDesc) external payable {
        SwapData calldata swapData = _swap;
        _isNativeDeposit(IERC20(swapData.srcToken), swapData.amount);
        uint256 dstAmount = _swapStart(swapData);
        _cBridgeStart(dstAmount, bDesc);
    }

    function swapPortalBridge(SwapData calldata _swap, PortalBridgeDescription calldata pDesc) external payable {
        SwapData calldata swapData = _swap;
        _isNativeDeposit(IERC20(swapData.srcToken), swapData.amount);
        uint256 dstAmount = _swapStart(swapData);
        _portalBridgeStart(dstAmount, pDesc);
    }

    function swapPolyBridge(SwapData calldata _swap, PolyBridgeDescription calldata pdesc) external payable {
        SwapData calldata swapData = _swap;
        _isNativeDeposit(IERC20(swapData.srcToken), swapData.amount);
        uint256 dstAmount = _swapStart(swapData);
        _polyBridgeStart(dstAmount, pdesc);
    }

    function swapMultichain(SwapData calldata _swap, MultiChainDescription calldata mDesc) external payable {
        SwapData calldata swapData = _swap;
        _isNativeDeposit(IERC20(swapData.srcToken), swapData.amount);
        uint256 dstAmount = _swapStart(swapData);
        if (!allowedRouter[mDesc.router]) revert();
        _multiChainBridgeStart(dstAmount, mDesc);
    }

    function _fee(address dstToken, uint256 dstAmount) private returns (uint256 returnAmount) {
        uint256 fee = (dstAmount * feePercent) / 10000;
        returnAmount = dstAmount - fee;
        if (fee > 0) {
            if (!_isNative(IERC20(dstToken))) {
                IERC20(dstToken).safeTransfer(owner(), fee);
            } else {
                _safeNativeTransfer(owner(), fee);
            }
        }
    }

    function _swapStart(SwapData calldata swapData) private returns (uint256 dstAmount) {
        SwapData calldata swap = swapData;

        bool isNative = _isNative(IERC20(swap.srcToken));

        uint256 initDstTokenBalance = AssetLib.getBalance(swap.dstToken);

        (bool succ, ) = address(ROUTER).call{value: isNative ? swap.amount : 0}(swap.callData);
        if (succ) {
            uint256 dstTokenBalance = AssetLib.getBalance(swap.dstToken);
            dstAmount = dstTokenBalance > initDstTokenBalance ? dstTokenBalance - initDstTokenBalance : dstTokenBalance;

            emit Swap(swap.user, swap.srcToken, swap.dstToken, swap.amount, dstAmount);
        } else {
            revert();
        }
    }

    function _userSwapStart(SwapData calldata swapData) private returns (uint256 dstAmount) {
        SwapData calldata swap = swapData;

        bool isNative = _isNative(IERC20(swap.srcToken));

        uint256 initDstTokenBalance = AssetLib.userBalance(swap.user, swap.dstToken);

        (bool succ, ) = address(ROUTER).call{value: isNative ? swap.amount : 0}(swap.callData);
        if (succ) {
            uint256 dstTokenBalance = AssetLib.userBalance(swap.user, swap.dstToken);
            dstAmount = dstTokenBalance > initDstTokenBalance ? dstTokenBalance - initDstTokenBalance : dstTokenBalance;

            emit Swap(swap.user, swap.srcToken, swap.dstToken, swap.amount, dstAmount);
        } else {
            revert();
        }
    }

    function relaySwapRouter(
        SwapData calldata _swap,
        Input calldata _sigCollect,
        bytes[] memory signature
    ) external onlyOwner {
        SwapData calldata swap = _swap;
        Input calldata sig = _sigCollect;
        require(sig.userAddress == swap.user && sig.amount - sig.gasFee == swap.amount && sig.toTokenAddress == swap.dstToken);
        relaySig(sig, signature);
        require(transfers[sig.txHash] == false, "safeTransfer exists");
        transfers[sig.txHash] = true;
        bool isNotNative = !_isNative(IERC20(sig.fromTokenAddress));
        uint256 fromAmount = sig.amount - sig.gasFee;
        if (isNotNative) {
            IERC20(sig.fromTokenAddress).safeApprove(ROUTER, fromAmount);
            if (sig.gasFee > 0) IERC20(sig.fromTokenAddress).safeTransfer(owner(), sig.gasFee);
        } else {
            if (sig.gasFee > 0) _safeNativeTransfer(owner(), sig.gasFee);
        }
        uint256 dstAmount = _userSwapStart(swap);
        emit Relayswap(sig.userAddress, sig.toTokenAddress, dstAmount);
    }

    function portalComplete(
        bytes memory encodeVm,
        Input calldata input,
        bytes[] memory signature
    ) public onlyOwner {
        bool isNotNative = !_isNative(IERC20(input.toTokenAddress));
        relaySig(input, signature);
        uint256 finalAmount = input.amount - input.gasFee;
        if (isNotNative) {
            IBridge(PORTAL).completeTransfer(encodeVm);
            if (input.gasFee > 0) IERC20(input.toTokenAddress).safeTransfer(owner(), input.gasFee);
            IERC20(input.toTokenAddress).safeTransfer(input.userAddress, finalAmount);
        } else {
            IBridge(PORTAL).completeTransferAndUnwrapETH(encodeVm);
            if (input.gasFee > 0) _safeNativeTransfer(owner(), input.gasFee);
            _safeNativeTransfer(owner(), finalAmount);
        }
        emit Relayswap(input.userAddress, input.toTokenAddress, finalAmount);
    }

    function portalComplete(
        bytes memory encodeVm,
        SwapData calldata _swap,
        Input calldata _sigCollect,
        bytes[] memory signature
    ) public onlyOwner {
        SwapData calldata swap = _swap;
        bool isNotNative = !_isNative(IERC20(swap.srcToken));
        Input calldata sig = _sigCollect;
        require(sig.userAddress == swap.user && sig.amount - sig.gasFee == swap.amount && sig.toTokenAddress == swap.dstToken);
        relaySig(sig, signature);
        require(transfers[sig.txHash] == false);
        uint256 fromAmount = sig.amount - sig.gasFee;
        if (isNotNative) {
            IBridge(PORTAL).completeTransferWithPayload(encodeVm);
            IERC20(sig.fromTokenAddress).safeApprove(ROUTER, fromAmount);
            if (sig.gasFee > 0) IERC20(sig.fromTokenAddress).safeTransfer(owner(), sig.gasFee);
        } else {
            IBridge(PORTAL).completeTransferAndUnwrapETHWithPayload(encodeVm);
            if (sig.gasFee > 0) _safeNativeTransfer(owner(), sig.gasFee);
        }
        uint256 dstAmount = _userSwapStart(swap);
        emit Relayswap(sig.userAddress, sig.toTokenAddress, dstAmount);
    }

    function EmergencyWithdraw(address _tokenAddress, uint256 amount) public onlyOwner {
        bool isNotNative = !_isNative(IERC20(_tokenAddress));
        if (isNotNative) {
            IERC20(_tokenAddress).safeTransfer(owner(), amount);
        } else {
            _safeNativeTransfer(owner(), amount);
        }
    }

    function sigWithdraw(
        bytes calldata _wdmsg,
        bytes[] calldata _sigs,
        address[] calldata _signers,
        uint256[] calldata _powers
    ) external {
        IBridge(CBRIDGE).withdraw(_wdmsg, _sigs, _signers, _powers);
        bytes32 domain = keccak256(abi.encodePacked(block.chainid, CBRIDGE, "WithdrawMsg"));
        verifySigs(abi.encodePacked(domain, _wdmsg), _sigs, _signers, _powers);
        PbPool.WithdrawMsg memory wdmsg = PbPool.decWithdrawMsg(_wdmsg);
        BridgeInfo memory tif = transferInfo[wdmsg.refid];

        bool isNotNative = !_isNative(IERC20(tif.dstToken));
        if (isNotNative) {
            IERC20(tif.dstToken).safeTransfer(tif.user, tif.amount);
        } else {
            _safeNativeTransfer(tif.user, tif.amount);
        }
    }

    function setRouterBridge(
        address _router,
        address _cbridge,
        address poly,
        address portal
    ) public {
        require(msg.sender == dev || msg.sender == owner());
        ROUTER = _router;
        CBRIDGE = _cbridge;
        POLYBRIDGE = poly;
        PORTAL = portal;
    }

    function setFeePercent(uint256 percent) external {
        require(msg.sender == dev || msg.sender == owner());
        feePercent = percent;
    }

    function _isNative(IERC20 token_) internal pure returns (bool) {
        return (token_ == NATIVE_ADDRESS);
    }

    function _isNativeDeposit(IERC20 _token, uint256 _amount) internal returns (bool isNotNative) {
        isNotNative = !_isNative(_token);

        if (isNotNative) {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20(_token).safeApprove(ROUTER, _amount);
        }
    }

    function _cBridgeStart(uint256 dstAmount, CBridgeDescription calldata bdesc) internal {
        CBridgeDescription memory bDesc = bdesc;
        dstAmount = _fee(bDesc.srcToken, dstAmount);
        bool isNotNative = !_isNative(IERC20(bDesc.srcToken));
        if (isNotNative) {
            IERC20(bDesc.srcToken).safeApprove(CBRIDGE, dstAmount);
            IBridge(CBRIDGE).send(bDesc.receiver, bDesc.srcToken, dstAmount, bDesc.dstChainId, bDesc.nonce, bDesc.maxSlippage);
        } else {
            IBridge(CBRIDGE).sendNative{value: dstAmount}(bDesc.receiver, dstAmount, bDesc.dstChainId, bDesc.nonce, bDesc.maxSlippage);
            bDesc.srcToken = WETH;
        }

        bytes32 transferId = keccak256(
            abi.encodePacked(address(this), bDesc.receiver, bDesc.srcToken, dstAmount, bDesc.dstChainId, bDesc.nonce, uint64(block.chainid))
        );

        BridgeInfo memory tif = transferInfo[transferId];
        require(tif.nonce == 0, " PLEXUS: transferId already exists. Check the nonce.");
        tif.dstToken = bDesc.srcToken;
        tif.chainId = bDesc.dstChainId;
        tif.amount = dstAmount;
        tif.user = msg.sender;
        tif.nonce = bDesc.nonce;
        tif.bridge = "CBridge";
        transferInfo[transferId] = tif;
        emit Bridge(tif.user, tif.chainId, tif.dstToken, bDesc.toDstToken, dstAmount, transferId, tif.bridge);
    }

    function _polyBridgeStart(uint256 dstAmount, PolyBridgeDescription calldata _pDesc) private {
        PolyBridgeDescription memory pDesc = _pDesc;
        bool isNative = _isNative(IERC20(pDesc.fromAsset));
        dstAmount = _fee(pDesc.fromAsset, dstAmount);
        if (!isNative) {
            IERC20(pDesc.fromAsset).safeApprove(POLYBRIDGE, dstAmount);
            IBridge(POLYBRIDGE).lock{value: pDesc.fee}(pDesc.fromAsset, pDesc.toChainId, pDesc.toAddress, dstAmount, pDesc.fee, pDesc.id);
        } else {
            pDesc.fromAsset = address(0);
            uint256 asset = pDesc.fee + dstAmount;
            IBridge(POLYBRIDGE).lock{value: asset}(pDesc.fromAsset, pDesc.toChainId, pDesc.toAddress, dstAmount, pDesc.fee, pDesc.id);
        }
        bytes32 transferId = keccak256(
            abi.encodePacked(address(this), pDesc.toAddress, pDesc.fromAsset, dstAmount, pDesc.toChainId, pDesc.nonce, uint64(block.chainid))
        );
        BridgeInfo memory tif = transferInfo[transferId];
        require(tif.nonce == 0, " PLEXUS: transferId already exists. Check the nonce.");
        tif.dstToken = pDesc.fromAsset;
        tif.chainId = pDesc.toChainId;
        tif.amount = dstAmount;
        tif.user = msg.sender;
        tif.nonce = pDesc.nonce;
        tif.bridge = "PolyBridge";
        transferInfo[transferId] = tif;

        emit Bridge(tif.user, tif.chainId, tif.dstToken, pDesc.toDstToken, dstAmount, transferId, tif.bridge);
    }

    function _multiChainBridgeStart(uint256 dstAmount, MultiChainDescription calldata mDesc) internal {
        address anyToken = anyTokenAddress[mDesc.srcToken];
        dstAmount = _fee(mDesc.srcToken, dstAmount);
        if (mDesc.router == anyToken) {
            IMultichainERC20(anyToken).Swapout(dstAmount, mDesc.receiver);
        } else {
            if (_isNative(IERC20(mDesc.srcToken))) {
                IBridge(mDesc.router).anySwapOutNative{value: dstAmount}(anyToken, mDesc.receiver, mDesc.dstChainId);
            } else {
                IERC20(mDesc.srcToken).safeApprove(mDesc.router, dstAmount);
                IBridge(mDesc.router).anySwapOutUnderlying(
                    anyToken != address(0) ? anyToken : mDesc.srcToken,
                    mDesc.receiver,
                    dstAmount,
                    mDesc.dstChainId
                );
            }
        }

        bytes32 transferId = keccak256(
            abi.encodePacked(address(this), mDesc.receiver, mDesc.srcToken, dstAmount, mDesc.dstChainId, mDesc.nonce, uint64(block.chainid))
        );

        BridgeInfo memory tif = transferInfo[transferId];
        require(tif.nonce == 0, " PLEXUS: transferId already exists. Check the nonce.");
        tif.dstToken = mDesc.srcToken;
        tif.chainId = mDesc.dstChainId;
        tif.amount = dstAmount;
        tif.user = msg.sender;
        tif.nonce = mDesc.nonce;
        tif.bridge = "MultiChainBridge";
        transferInfo[transferId] = tif;

        emit Bridge(tif.user, tif.chainId, tif.dstToken, mDesc.toDstToken, dstAmount, transferId, tif.bridge);
    }

    function _portalBridgeStart(uint256 dstAmount, PortalBridgeDescription calldata _Pdesc) internal {
        PortalBridgeDescription memory pDesc = _Pdesc;
        dstAmount = _fee(pDesc.token, dstAmount);
        bool isNotNative = !_isNative(IERC20(pDesc.token));
        bytes32 userAddress = bytes32(uint256(uint160(pDesc.recipient)));

        if (isNotNative) {
            IERC20(pDesc.token).safeApprove(PORTAL, 0);
            IERC20(pDesc.token).safeApprove(PORTAL, dstAmount);
            IBridge(PORTAL).transferTokensWithPayload(pDesc.token, dstAmount, pDesc.recipientChain, userAddress, pDesc.nonce, pDesc.payload);
        } else {
            IBridge(PORTAL).wrapAndTransferETHWithPayload{value: dstAmount}(pDesc.recipientChain, userAddress, pDesc.nonce, pDesc.payload);
        }

        bytes32 transferId = keccak256(
            abi.encodePacked(address(this), pDesc.recipient, pDesc.token, dstAmount, pDesc.recipientChain, pDesc.nonce, uint64(block.chainid))
        );

        BridgeInfo memory tif = transferInfo[transferId];
        require(tif.nonce == 0, " PLEXUS: transferId already exists. Check the nonce.");
        tif.dstToken = pDesc.token;
        tif.chainId = pDesc.recipientChain;
        tif.amount = dstAmount;
        tif.user = msg.sender;
        tif.nonce = pDesc.nonce;
        tif.bridge = "PortalBridge";
        transferInfo[transferId] = tif;

        emit Bridge(tif.user, tif.chainId, tif.dstToken, pDesc.toDstToken, dstAmount, transferId, tif.bridge);
    }

    function _safeNativeTransfer(address to_, uint256 amount_) private {
        (bool sent, ) = to_.call{value: amount_}("");
        require(sent, "Safe safeTransfer fail");
    }
}

