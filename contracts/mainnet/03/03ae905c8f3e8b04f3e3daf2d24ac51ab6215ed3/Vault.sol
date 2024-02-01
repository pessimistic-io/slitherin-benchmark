// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Ownable.sol";
import "./IClipperExchangeInterface.sol";
import "./IBridge.sol";
import "./IERC20.sol";
import "./PbPool.sol";
import "./Signers.sol";
import "./OrderLib.sol";
import "./VerifySigEIP712.sol";

contract Vault is Ownable, Signers, VerifySigEIP712 {
    struct BridgeInfo {
        address dstToken;
        uint64 chainId;
        uint256 amount;
        address user;
        uint64 nonce;
    }

    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    struct BridgeDescription {
        address receiver;
        uint64 dstChainId;
        uint64 nonce;
        uint32 maxSlippage;
    }

    IERC20 private constant NATIVE_ADDRESS =
        IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    address public ROUTER;
    address public BRIDGE;

    mapping(address => mapping(uint64 => BridgeInfo)) public userBridgeInfo;
    mapping(bytes32 => BridgeInfo) public transferInfo;

    event Swap(
        address user,
        address srcToken,
        address toToken,
        uint256 amount,
        uint256 returnAmount
    );
    event send(
        address user,
        uint64 chainId,
        address dstToken,
        uint256 amount,
        uint64 nonce,
        bytes32 transferId
    );
    event Relayswap(address receiver, address toToken, uint256 returnAmount);

    receive() external payable {}

    constructor(address router, address bridge) {
        ROUTER = router;
        BRIDGE = bridge;
    }

    function bridge(
        address _token,
        uint256 _amount,
        BridgeDescription calldata bDesc
    ) external payable {
        bool isNotNative = !_isNative(IERC20(_token));

        if (isNotNative) {
            IERC20(_token).transferFrom(msg.sender, address(this), _amount);
            IERC20(_token).approve(BRIDGE, _amount);

            IBridge(BRIDGE).send(
                bDesc.receiver,
                _token,
                _amount,
                bDesc.dstChainId,
                bDesc.nonce,
                bDesc.maxSlippage
            );
        } else {
            IBridge(BRIDGE).sendNative{value: msg.value}(
                bDesc.receiver,
                _amount,
                bDesc.dstChainId,
                bDesc.nonce,
                bDesc.maxSlippage
            );
        }
        bytes32 transferId = keccak256(
            abi.encodePacked(
                address(this),
                bDesc.receiver,
                _token,
                _amount,
                bDesc.dstChainId,
                bDesc.nonce,
                uint64(block.chainid)
            )
        );

        BridgeInfo memory tif = transferInfo[transferId];
        require(
            tif.nonce == 0,
            " PLEXUS: transferId already exists. Check the nonce."
        );
        tif.dstToken = _token;
        tif.chainId = bDesc.dstChainId;
        tif.amount = _amount;
        tif.user = msg.sender;
        tif.nonce = bDesc.nonce;
        transferInfo[transferId] = tif;

        emit send(
            tif.user,
            tif.chainId,
            tif.dstToken,
            tif.amount,
            tif.nonce,
            transferId
        );
    }

    function swap(bytes calldata _data) external payable {
        (address _c, SwapDescription memory desc, bytes memory _d) = abi.decode(_data[4:],(address, SwapDescription, bytes));

        bool isNotNative = !_isNative(IERC20(desc.srcToken));

        if (isNotNative) {
            IERC20(desc.srcToken).transferFrom(msg.sender,address(this),desc.amount);
            IERC20(desc.srcToken).approve(ROUTER, desc.amount);
        }

        (bool succ, bytes memory _data) = address(ROUTER).call{value: msg.value}(_data);
        if (succ) {
            (uint256 returnAmount, uint256 gasLeft) = abi.decode(_data,(uint256, uint256));
            require(returnAmount >= desc.minReturnAmount);
            emit Swap(msg.sender,address(desc.srcToken),address(desc.dstToken),desc.amount,returnAmount);
        } else {
            revert();
        }
    }

    function unoswapTo(
        uint256 minOut,
        address toToken,
        bytes calldata _data
    ) external payable {
        (
            address user,
            IERC20 srcToken,
            uint256 amount,
            uint256 b,
            bytes32[] memory c
        ) = abi.decode(
                _data[4:],
                (address, IERC20, uint256, uint256, bytes32[])
            );

        bool isNotNative = !_isNative(srcToken);

        if (isNotNative) {
            srcToken.transferFrom(msg.sender, address(this), amount);
            srcToken.approve(ROUTER, amount);
        }

        (bool succ, bytes memory _data) = address(ROUTER).call{
            value: msg.value
        }(_data);
        if (succ) {
            uint256 returnAmount = abi.decode(_data, (uint256));
            require(returnAmount >= minOut);
            emit Swap(
                msg.sender,
                address(srcToken),
                toToken,
                amount,
                returnAmount
            );
        } else {
            revert();
        }
    }

    function v3swapTo(
        uint256 minOut,
        address srcToken,
        address toToken,
        bytes calldata _data
    ) external payable {
        (address user, uint256 amount, uint256 b, uint256[] memory c) = abi
            .decode(_data[4:], (address, uint256, uint256, uint256[]));

        bool isNotNative = !_isNative(IERC20(srcToken));
        if (isNotNative) {
            IERC20(srcToken).transferFrom(msg.sender, address(this), amount);
            IERC20(srcToken).approve(ROUTER, amount);
        }

        (bool succ, bytes memory _data) = address(ROUTER).call{
            value: msg.value
        }(_data);
        if (succ) {
            uint256 returnAmount = abi.decode(_data, (uint256));
            require(returnAmount >= minOut);
            emit Swap(msg.sender, srcToken, toToken, amount, returnAmount);
        } else {
            revert();
        }
    }

    function clipperSwapTo(bytes calldata _data, uint256 minOut)
        external
        payable
    {
        (
            IClipperExchangeInterface exchange,
            address user,
            IERC20 srcToken,
            IERC20 dstToken,
            uint256 input,
            uint256 output,
            uint256 goodUntil,
            bytes32 r,
            bytes32 vs
        ) = abi.decode(
                _data[4:],
                (
                    IClipperExchangeInterface,
                    address,
                    IERC20,
                    IERC20,
                    uint256,
                    uint256,
                    uint256,
                    bytes32,
                    bytes32
                )
            );

        {
            bool isNotNative = !_isNative(srcToken);

            if (isNotNative) {
                srcToken.transferFrom(msg.sender, address(this), input);
                srcToken.approve(ROUTER, input);
            }
        }

        (bool succ, bytes memory _data) = address(ROUTER).call{
            value: msg.value
        }(_data);
        if (succ) {
            uint256 returnAmount = abi.decode(_data, (uint256));
            require(returnAmount >= minOut);
            emit Swap(
                msg.sender,
                address(srcToken),
                address(dstToken),
                input,
                returnAmount
            );
        } else {
            revert();
        }
    }

    function swapRouter(
        IERC20 _fromToken,
        uint256 amount,
        bytes calldata _data
    ) external payable {
        bool isNotNative = !_isNative(_fromToken);

        if (isNotNative) {
            _fromToken.transferFrom(msg.sender, address(this), amount);
            _fromToken.approve(ROUTER, amount);
        }

        (bool succ, bytes memory _data) = address(ROUTER).call{
            value: msg.value
        }(_data);
        if (succ) {
            // (uint returnAmount, ) = abi.decode(_data, (uint256, uint256, bytes32));
            // emit Swap(msg.sender, _order.makerAsset, _order.takerAsset, actualMakingAmount, actualTakingAmount);
        } else {
            revert();
        }
    }

    function clipperSwapToBridge(
        bytes calldata _data,
        uint256 minOut,
        IERC20 _srcToken,
        IERC20 _dstToken,
        uint256 input,
        BridgeDescription calldata bDesc
    ) external payable {
        //  (IClipperExchangeInterface exchange, address user, IERC20 srcToken, IERC20 dstToken, uint256 input, uint256 output, uint256 goodUntil, bytes32 r, bytes32 vs) =
        //  abi.decode(_data[4:], (IClipperExchangeInterface, address, IERC20, IERC20, uint256, uint256, uint256, bytes32, bytes32));
        _isNativeSwap(_srcToken, input);
        (bool succ, bytes memory _data) = address(ROUTER).call{value: msg.value}(_data);
        if (succ) {
            uint256 returnAmount = abi.decode(_data, (uint256));
            require(returnAmount >= minOut);
            //  emit Swap(msg.sender, address(srcToken), address(dstToken), input, returnAmount);
            _isNotNativeBridge(_dstToken, returnAmount, bDesc);
        } else {
            revert();
        }
    }

    function fillOrderTo(uint256 minOut, bytes calldata _data)
        external
        payable
    {
        (
            OrderLib.Order memory _order,
            bytes memory sig,
            bytes memory a,
            uint256 make,
            uint256 take,
            uint256 b,
            address user
        ) = abi.decode(
                _data[4:],
                (
                    OrderLib.Order,
                    bytes,
                    bytes,
                    uint256,
                    uint256,
                    uint256,
                    address
                )
            );
        {
            bool isNotNative = !_isNative(IERC20(_order.makerAsset));

            if (isNotNative) {
                IERC20(_order.makerAsset).transferFrom(
                    msg.sender,
                    address(this),
                    _order.makingAmount
                );
                IERC20(_order.makerAsset).approve(ROUTER, _order.makingAmount);
            }
        }

        (bool succ, bytes memory _data) = address(ROUTER).call{
            value: msg.value
        }(_data);
        if (succ) {
            (uint256 actualMakingAmount, uint256 actualTakingAmount, ) = abi
                .decode(_data, (uint256, uint256, bytes32));
            emit Swap(
                msg.sender,
                _order.makerAsset,
                _order.takerAsset,
                actualMakingAmount,
                actualTakingAmount
            );
        } else {
            revert();
        }
    }

    function fillOrderToBridge(
        uint256 minOut,
        bytes calldata _data,
        BridgeDescription calldata bDesc
    ) external payable {
        (
            OrderLib.Order memory _order,
            bytes memory sig,
            bytes memory a,
            uint256 make,
            uint256 take,
            uint256 b,
            address user
        ) = abi.decode(
                _data[4:],
                (
                    OrderLib.Order,
                    bytes,
                    bytes,
                    uint256,
                    uint256,
                    uint256,
                    address
                )
            );

        _isNativeSwap(IERC20(_order.makerAsset), _order.makingAmount);

        (bool succ, bytes memory _data) = address(ROUTER).call{
            value: msg.value
        }(_data);
        if (succ) {
            (uint256 actualMakingAmount, uint256 actualTakingAmount, ) = abi
                .decode(_data, (uint256, uint256, bytes32));
            _isNotNativeBridge(
                IERC20(_order.makerAsset),
                _order.makingAmount,
                bDesc
            );
            // emit Swap(msg.sender, _order.makerAsset, _order.takerAsset, actualMakingAmount, actualTakingAmount);
        } else {
            revert();
        }
    }

    function swapBridge(bytes calldata _data, BridgeDescription calldata bDesc)
        external
        payable
    {
        (address _c, SwapDescription memory desc, bytes memory _d) = abi.decode(
            _data[4:],
            (address, SwapDescription, bytes)
        );

        _isNativeSwap(IERC20(desc.srcToken), desc.amount);

        (bool succ, bytes memory _data) = address(ROUTER).call{
            value: msg.value
        }(_data);
        if (succ) {
            (uint256 returnAmount, ) = abi.decode(_data, (uint256, uint256));
            require(returnAmount >= desc.minReturnAmount);
            _isNotNativeBridge(IERC20(desc.dstToken), returnAmount, bDesc);
            //     isNotNative = !_isNative(IERC20(desc.dstToken));
            //     if (isNotNative) {
            //     IERC20(desc.dstToken).approve(BRIDGE, returnAmount);
            //     IBridge(BRIDGE).send(bDesc.receiver, address(desc.dstToken) , returnAmount, bDesc.dstChainId, bDesc.nonce, bDesc.maxSlippage);
            //     } else {
            //     IBridge(BRIDGE).sendNative{value:returnAmount}(bDesc.receiver, returnAmount, bDesc.dstChainId, bDesc.nonce, bDesc.maxSlippage);
            //     }
            //     bytes32 transferId = keccak256(
            //     abi.encodePacked(address(this), bDesc.receiver, address(desc.dstToken), returnAmount, bDesc.dstChainId, bDesc.nonce, uint64(block.chainid))
            //     );

            //     BridgeInfo memory tif = transferInfo[transferId];
            //     require(tif.nonce == 0," PLEXUS: transferId already exists. Check the nonce.");
            //     tif.dstToken = address(desc.dstToken);
            //     tif.chainId = bDesc.dstChainId;
            //     tif.amount = returnAmount;
            //     tif.user = msg.sender;
            //     tif.nonce = bDesc.nonce;
            //     transferInfo[transferId] = tif;

            // // emit Swap(msg.sender, address(desc.srcToken), address(desc.dstToken), desc.amount, returnAmount);
            // emit send(tif.user, tif.chainId, tif.dstToken, tif.amount, tif.nonce, transferId );
        } else {
            revert();
        }
    }

    function unoBridge(
        uint256 minOut,
        address toToken,
        bytes calldata _data,
        BridgeDescription calldata bDesc
    ) external payable {
        (IERC20 srcToken, uint256 amount, uint256 b, bytes32[] memory c) = abi
            .decode(_data[4:], (IERC20, uint256, uint256, bytes32[]));

        // bool isNotNative = !_isNative(srcToken);

        // if (isNotNative) {
        // srcToken.transferFrom(msg.sender, address(this), amount);
        // srcToken.approve(ROUTER, amount);
        // }

        _isNativeSwap(srcToken, amount);
        (bool succ, bytes memory _data) = address(ROUTER).call{
            value: msg.value
        }(_data);
        if (succ) {
            uint256 returnAmount = abi.decode(_data, (uint256));
            require(returnAmount >= minOut);
            _isNotNativeBridge(IERC20(toToken), returnAmount, bDesc);
            // isNotNative = !_isNative(IERC20(toToken));
            // if (isNotNative) {
            // IERC20(toToken).approve(BRIDGE, returnAmount);
            // IBridge(BRIDGE).send(bDesc.receiver, toToken , returnAmount, bDesc.dstChainId, bDesc.nonce, bDesc.maxSlippage);
            // } else {
            // IBridge(BRIDGE).sendNative{value:returnAmount}(bDesc.receiver, returnAmount, bDesc.dstChainId, bDesc.nonce, bDesc.maxSlippage);
            // }

            // bytes32 transferId = keccak256(
            // abi.encodePacked(address(this), bDesc.receiver, toToken, returnAmount, bDesc.dstChainId, bDesc.nonce, uint64(block.chainid))
            // );

            // BridgeInfo memory tif = transferInfo[transferId];
            // require(tif.nonce == 0," PLEXUS: transferId already exists. Check the nonce.");
            // tif.dstToken = toToken;
            // tif.chainId = bDesc.dstChainId;
            // tif.amount = returnAmount;
            // tif.user = msg.sender;
            // tif.nonce = bDesc.nonce;
            // transferInfo[transferId] = tif;
            // // emit Swap(msg.sender, address(srcToken), toToken, amount, returnAmount);
            // emit send(tif.user, tif.chainId, tif.dstToken, tif.amount, tif.nonce, transferId );
        } else {
            revert();
        }
    }

    function v3Bridge(
        uint256 minOut,
        address fromToken,
        address toToken,
        bytes calldata _data,
        BridgeDescription calldata bDesc
    ) external payable {
        (uint256 amount, uint256 b, uint256[] memory c) = abi.decode(
            _data[4:],
            (uint256, uint256, uint256[])
        );

        // bool isNotNative = !_isNative(IERC20(fromToken));

        // if (isNotNative) {
        // IERC20(fromToken).transferFrom(msg.sender, address(this), amount);
        // IERC20(fromToken).approve(ROUTER, amount);
        // }

        _isNativeSwap(IERC20(fromToken), amount);

        (bool succ, bytes memory _data) = address(ROUTER).call{
            value: msg.value
        }(_data);
        if (succ) {
            uint256 returnAmount = abi.decode(_data, (uint256));
            require(returnAmount >= minOut);
            _isNotNativeBridge(IERC20(toToken), returnAmount, bDesc);
            // isNotNative = !_isNative(IERC20(toToken));
            // if (isNotNative) {
            // IERC20(toToken).approve(BRIDGE, returnAmount);
            // IBridge(BRIDGE).send(bDesc.receiver, toToken , returnAmount, bDesc.dstChainId, bDesc.nonce, bDesc.maxSlippage);
            // } else {
            // IBridge(BRIDGE).sendNative{value:returnAmount}(bDesc.receiver, returnAmount, bDesc.dstChainId, bDesc.nonce, bDesc.maxSlippage);
            // }

            // bytes32 transferId = keccak256(
            // abi.encodePacked(address(this), bDesc.receiver, toToken, returnAmount, bDesc.dstChainId, bDesc.nonce, uint64(block.chainid))
            // );

            // BridgeInfo memory tif = transferInfo[transferId];
            // require(tif.nonce == 0," PLEXUS: transferId already exists. Check the nonce.");
            // tif.dstToken = toToken;
            // tif.chainId = bDesc.dstChainId;
            // tif.amount = returnAmount;
            // tif.user = msg.sender;
            // tif.nonce = bDesc.nonce;
            // transferInfo[transferId] = tif;

            // // emit Swap(msg.sender, fromToken, toToken, amount, returnAmount);
            // emit send(tif.user, tif.chainId, tif.dstToken, tif.amount, tif.nonce, transferId );
        } else {
            revert();
        }
    }

    function relaySwap(uint256 minOut, bytes calldata _data)
        external
        payable
        onlyOwner
    {
        (address _c, SwapDescription memory desc, bytes memory _d) = abi.decode(
            _data[4:],
            (address, SwapDescription, bytes)
        );

        bool isNotNative = !_isNative(IERC20(desc.srcToken));
        uint256 tokenAmount = 0;
        if (isNotNative) {
            IERC20(desc.srcToken).approve(ROUTER, desc.amount);
        } else {
            tokenAmount = desc.amount;
        }

        (bool succ, bytes memory _data) = address(ROUTER).call{
            value: tokenAmount
        }(_data);
        if (succ) {
            (uint256 returnAmount, uint256 gasLeft) = abi.decode(
                _data,
                (uint256, uint256)
            );
            require(returnAmount >= minOut);
            emit Relayswap(
                desc.dstReceiver,
                address(desc.dstToken),
                returnAmount
            );
        } else {
            revert();
        }
    }

    function relaySwapEIP712(
        bytes calldata _data,
        Input calldata _sigCollect,
        bytes[] memory signature
    ) external payable onlyOwner {
        (address _c, SwapDescription memory desc, bytes memory _d) = abi.decode(
            _data[4:],
            (address, SwapDescription, bytes)
        );

        Input calldata sig = _sigCollect;
        relaySig(sig, signature);

        bool isNotNative = !_isNative(IERC20(desc.srcToken));
        uint256 tokenAmount = 0;
        if (isNotNative) {
            IERC20(desc.srcToken).approve(ROUTER, desc.amount);
        } else {
            tokenAmount = desc.amount;
        }

        (bool succ, bytes memory _data) = address(ROUTER).call{
            value: tokenAmount
        }(_data);
        if (succ) {
            (uint256 returnAmount, uint256 gasLeft) = abi.decode(
                _data,
                (uint256, uint256)
            );
            emit Relayswap(
                desc.dstReceiver,
                address(desc.dstToken),
                returnAmount
            );
        } else {
            revert();
        }
    }

    function relayV3(
        uint256 minOut,
        address srcToken,
        address toToken,
        bytes calldata _data
    ) external onlyOwner {
        (address user, uint256 amount, uint256 b, uint256[] memory c) = abi
            .decode(_data[4:], (address, uint256, uint256, uint256[]));

        bool isNotNative = !_isNative(IERC20(srcToken));
        uint256 tokenAmount = 0;
        if (isNotNative) {
            IERC20(srcToken).approve(ROUTER, amount);
        } else {
            tokenAmount = amount;
        }

        (bool succ, bytes memory _data) = address(ROUTER).call{
            value: tokenAmount
        }(_data);
        if (succ) {
            uint256 returnAmount = abi.decode(_data, (uint256));
            require(returnAmount >= minOut);
            emit Relayswap(user, toToken, returnAmount);
        } else {
            revert();
        }
    }

    function relayUno(uint256 minOut,address toToken,bytes calldata _data) external onlyOwner {
        (address user,IERC20 srcToken,uint256 amount,uint256 b,bytes32[] memory c) = abi.decode(_data[4:],(address, IERC20, uint256, uint256, bytes32[]));

        bool isNotNative = !_isNative(srcToken);
        uint256 tokenAmount = 0;
        if (isNotNative) {
            srcToken.approve(ROUTER, amount);
        } else {
            tokenAmount = amount;
        }

        (bool succ, bytes memory _data) = address(ROUTER).call{value: tokenAmount}(_data);
        if (succ) {
            uint256 returnAmount = abi.decode(_data, (uint256));
            require(returnAmount >= minOut);
            emit Relayswap(user, toToken, returnAmount);
        } else {
            revert();
        }
    }

    // delete
    function EmergencyWithdraw(address _tokenAddress, uint256 amount) public onlyOwner{
        bool isNotNative = !_isNative(IERC20(_tokenAddress));
        if (isNotNative) {
            IERC20(_tokenAddress).transfer(owner(), amount);
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
        IBridge(BRIDGE).withdraw(_wdmsg, _sigs, _signers, _powers);
        bytes32 domain = keccak256(
            abi.encodePacked(block.chainid, BRIDGE, "WithdrawMsg")
        );
        verifySigs(abi.encodePacked(domain, _wdmsg), _sigs, _signers, _powers);
        PbPool.WithdrawMsg memory wdmsg = PbPool.decWithdrawMsg(_wdmsg);
        // require(wdmsg.receiver == address(this));
        BridgeInfo memory tif = transferInfo[wdmsg.refid];

        bool isNotNative = !_isNative(IERC20(tif.dstToken));
        if (isNotNative) {
            IERC20(tif.dstToken).transfer(tif.user, tif.amount);
        } else {
            _safeNativeTransfer(tif.user, tif.amount);
        }
    }

    function setRouterBridge(address _router, address _bridge)
        public
        onlyOwner
    {
        ROUTER = _router;
        BRIDGE = _bridge;
    }

    function _isNative(IERC20 token_) internal pure returns (bool) {
        return (token_ == NATIVE_ADDRESS);
    }

    function _isNativeSwap(IERC20 _token, uint256 _amount) internal {
        bool isNotNative = !_isNative(_token);

        if (isNotNative) {
            _token.transferFrom(msg.sender, address(this), _amount);
            _token.approve(ROUTER, _amount);
        }
    }

    function _isNotNativeBridge(IERC20 _token, uint256 _amount, BridgeDescription calldata bDesc) internal {
        bool isNotNative = !_isNative(_token);
        if (isNotNative) {
            _token.approve(BRIDGE, _amount);
            IBridge(BRIDGE).send(
                bDesc.receiver,
                address(_token),
                _amount,
                bDesc.dstChainId,
                bDesc.nonce,
                bDesc.maxSlippage
            );
        } else {
            IBridge(BRIDGE).sendNative{value: _amount}(
                bDesc.receiver,
                _amount,
                bDesc.dstChainId,
                bDesc.nonce,
                bDesc.maxSlippage
            );
        }

        bytes32 transferId = keccak256(
            abi.encodePacked(
                address(this),
                bDesc.receiver,
                address(_token),
                _amount,
                bDesc.dstChainId,
                bDesc.nonce,
                uint64(block.chainid)
            )
        );

        BridgeInfo memory tif = transferInfo[transferId];
        require(
            tif.nonce == 0,
            " PLEXUS: transferId already exists. Check the nonce."
        );
        tif.dstToken = address(_token);
        tif.chainId = bDesc.dstChainId;
        tif.amount = _amount;
        tif.user = msg.sender;
        tif.nonce = bDesc.nonce;
        transferInfo[transferId] = tif;
        emit send(
            tif.user,
            tif.chainId,
            tif.dstToken,
            tif.amount,
            tif.nonce,
            transferId
        );
    }

    function _safeNativeTransfer(address to_, uint256 amount_) private {
        (bool sent, ) = to_.call{value: amount_}("");
        require(sent, "Safe transfer fail");
    }
}

