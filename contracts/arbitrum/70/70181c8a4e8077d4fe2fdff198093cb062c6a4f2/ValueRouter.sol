// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

library libbytes {
    function addressToBytes32(address addr) external pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function bytes32ToAddress(bytes32 _buf) public pure returns (address) {
        return address(uint160(uint256(_buf)));
    }

    function slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _length
    ) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                tempBytes := mload(0x40)

                let lengthmod := and(_length, 31)

                let mc := add(
                    add(tempBytes, lengthmod),
                    mul(0x20, iszero(lengthmod))
                )
                let end := add(mc, _length)

                for {
                    let cc := add(
                        add(
                            add(_bytes, lengthmod),
                            mul(0x20, iszero(lengthmod))
                        ),
                        _start
                    )
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                mstore(0x40, and(add(mc, 31), not(31)))
            }
            default {
                tempBytes := mload(0x40)
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }
}

library CCTPMessage {
    using libbytes for *;
    uint8 public constant MESSAGE_BODY_INDEX = 116;

    function body(bytes memory message) public pure returns (bytes memory) {
        return
            message.slice(
                MESSAGE_BODY_INDEX,
                message.length - MESSAGE_BODY_INDEX
            );
    }

    /*function testGetCCTPMessageBody() public pure {
        bytes
            memory message = hex"00000000000000030000000000000000000000710000000000000000000000007fa4b6f62ff79352877b3411ed4101c394a711d500000000000000000000000089eca6d68e52e27682a649f33bf75a96e72595190000000000000000000000000000000000000000000000000000000000000000233333";
        bytes memory messageBody = body(message);
        require(keccak256(messageBody) == keccak256(hex"233333"));
    }*/
}

struct SwapMessage {
    uint32 version;
    uint256 sellAmount;
    bytes32 buyToken;
    uint256 guaranteedBuyAmount;
    bytes32 recipient;
    uint256 callgas;
    bytes swapdata;
}

library SwapMessageCodec {
    using libbytes for *;

    uint8 public constant VERSION_END_INDEX = 4;
    uint8 public constant SELLAMOUNT_END_INDEX = 36;
    uint8 public constant BUYTOKEN_END_INDEX = 68;
    uint8 public constant BUYAMOUNT_END_INDEX = 100;
    uint8 public constant RECIPIENT_END_INDEX = 132;
    uint8 public constant GAS_END_INDEX = 164;
    uint8 public constant SWAPDATA_INDEX = 164;

    function encode(SwapMessage memory swapMessage)
        public
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                swapMessage.version,
                swapMessage.sellAmount,
                swapMessage.buyToken,
                swapMessage.guaranteedBuyAmount,
                swapMessage.recipient,
                swapMessage.callgas,
                swapMessage.swapdata
            );
    }

    function decode(bytes memory message)
        public
        pure
        returns (SwapMessage memory)
    {
        uint32 version;
        uint256 sellAmount;
        bytes32 buyToken;
        uint256 guaranteedBuyAmount;
        bytes32 recipient;
        uint256 callgas;
        bytes memory swapdata;
        assembly {
            version := mload(add(message, VERSION_END_INDEX))
            sellAmount := mload(add(message, SELLAMOUNT_END_INDEX))
            buyToken := mload(add(message, BUYTOKEN_END_INDEX))
            guaranteedBuyAmount := mload(add(message, BUYAMOUNT_END_INDEX))
            recipient := mload(add(message, RECIPIENT_END_INDEX))
            callgas := mload(add(message, GAS_END_INDEX))
        }
        swapdata = message.slice(
            SWAPDATA_INDEX,
            message.length - SWAPDATA_INDEX
        );
        return
            SwapMessage(
                version,
                sellAmount,
                buyToken,
                guaranteedBuyAmount,
                recipient,
                callgas,
                swapdata
            );
    }

    /*
    function testEncode() public pure returns (bytes memory) {
        return
            encode(
                SwapMessage(
                    3,
                    1000,
                    0xFFFffFFf00000000fffffFfF00000000FfFFFfFF
                        .addressToBytes32(),
                    2000,
                    0xEeeEeEEE11111111eeEEEeeE11111111eeeEeeEE
                        .addressToBytes32(),
                    0x33aaaa,
                    hex"ffffeeeeddddcccc"
                )
            );
        //hex
        //00000003
        //00000000000000000000000000000000000000000000000000000000000003e8
        //000000000000000000000000ffffffff00000000ffffffff00000000ffffffff
        //00000000000000000000000000000000000000000000000000000000000007d0
        //000000000000000000000000eeeeeeee11111111eeeeeeee11111111eeeeeeee
        //000000000000000000000000000000000000000000000000000000000033aaaa
        //ffffeeeeddddcccc
    }

    function testDecode() public pure returns (SwapMessage memory) {
        return
            decode(
                hex"0000000300000000000000000000000000000000000000000000000000000000000003e8000000000000000000000000ffffffff00000000ffffffff00000000ffffffff00000000000000000000000000000000000000000000000000000000000007d0000000000000000000000000eeeeeeee11111111eeeeeeee11111111eeeeeeee000000000000000000000000000000000000000000000000000000000033aaaaffffeeeeddddcccc"
            );
    }

    function testMessageCodec() public pure {
        bytes
            memory message = hex"0000000300000000000000000000000000000000000000000000000000000000000003e8000000000000000000000000ffffffff00000000ffffffff00000000ffffffff00000000000000000000000000000000000000000000000000000000000007d0000000000000000000000000eeeeeeee11111111eeeeeeee11111111eeeeeeee000000000000000000000000000000000000000000000000000000000033aaaaffffeeeeddddcccc";
        SwapMessage memory args = decode(message);
        bytes memory encoded = encode(args);
        require(keccak256(message) == keccak256(encoded));
    }
    */
}

interface ITokenMessenger {
    function depositForBurnWithCaller(
        uint256 _amount,
        uint32 _destinationDomain,
        bytes32 _mintRecipient,
        address _burnToken,
        bytes32 destinationCaller
    ) external returns (uint64 _nonce);
}

interface IMessageTransmitter {
    function sendMessageWithCaller(
        uint32 destinationDomain,
        bytes32 recipient,
        bytes32 destinationCaller,
        bytes calldata messageBody
    ) external returns (uint64);

    function receiveMessage(bytes calldata message, bytes calldata attestation)
        external
        returns (bool success);

    function replaceMessage(
        bytes calldata originalMessage,
        bytes calldata originalAttestation,
        bytes calldata newMessageBody,
        bytes32 newDestinationCaller
    ) external;
}

contract ValueRouter {
    using libbytes for *;
    using SwapMessageCodec for *;
    using CCTPMessage for *;

    struct MessageWithAttestation {
        bytes message;
        bytes attestation;
    }

    struct SellArgs {
        address sellToken;
        uint256 sellAmount;
        uint256 sellcallgas;
        bytes sellcalldata;
    }

    struct BuyArgs {
        bytes32 buyToken;
        uint256 guaranteedBuyAmount;
        uint256 buycallgas;
        bytes buycalldata;
    }

    address public immutable usdc;
    IMessageTransmitter public immutable messageTransmitter;
    ITokenMessenger public immutable tokenMessenger;
    address public immutable zeroEx;
    uint16 public immutable version = 1;

    mapping(uint32 => bytes32) public remoteRouter;
    mapping(bytes32 => address) swapHashSender;

    event TakeFee(address token, address to, uint256 amount);

    event SwapAndBridge(
        address sellToken,
        uint256 sellAmount,
        uint256 bridgeUSDCAmount,
        address buyToken,
        uint256 buyAmount,
        uint32 destDomain,
        address recipient,
        uint64 bridgeNonce,
        uint64 swapMessageNonce
    );

    event ReplaceSwapMessage(
        address buyToken,
        uint256 buyAmount,
        uint32 destDomain,
        address recipient,
        uint64 swapMessageNonce
    );

    constructor(
        address _usdc,
        address _messageTransmtter,
        address _tokenMessenger,
        address _zeroEx
    ) {
        /*
        Goerli addresses
        usdc - 0x2f3A40A3db8a7e3D09B0adfEfbCe4f6F81927557
        messageTransmitter - 0x26413e8157CD32011E726065a5462e97dD4d03D9
        tokenMessenger- 0xd0c3da58f55358142b8d3e06c1c30c5c6114efe8
        zeroEx - 0xF91bB752490473B8342a3E964E855b9f9a2A668e
        */
        usdc = _usdc;
        messageTransmitter = IMessageTransmitter(_messageTransmtter);
        tokenMessenger = ITokenMessenger(_tokenMessenger);
        zeroEx = _zeroEx;
    }

    function setRemoteRouter(uint32 remoteDomain, address router) public {
        // TODO only admin
        remoteRouter[remoteDomain] = router.addressToBytes32();
    }

    function takeFee(
        address token,
        address to,
        uint256 amount
    ) public {
        // TODO only paused
        // TODO only admin
        if (token == address(0)) {
            (bool succ, ) = to.call{value: amount}("");
            require(succ);
        } else {
            bool succ = IERC20(token).transfer(to, amount);
            require(succ);
        }
        emit TakeFee(token, to, amount);
    }

    function zeroExSwap(bytes memory swapcalldata, uint256 callgas)
        external
        payable
    {
        _zeroExSwap(swapcalldata, callgas);
    }

    function _zeroExSwap(bytes memory swapcalldata, uint256 callgas) internal {
        (bool succ, ) = zeroEx.call{value: msg.value, gas: callgas}(
            swapcalldata
        );
        require(succ, "call swap failed");
    }

    /// User entrance
    /// @param sellArgs : sell-token arguments
    /// @param buyArgs : buy-token arguments
    /// @param destDomain : destination domain
    /// @param recipient : token receiver on dest domain
    function swapAndBridge(
        SellArgs calldata sellArgs,
        BuyArgs calldata buyArgs,
        uint32 destDomain,
        bytes32 recipient
    ) public payable returns (uint64, uint64) {
        if (recipient == bytes32(0)) {
            recipient = msg.sender.addressToBytes32();
        }

        // swap sellToken to usdc
        if (sellArgs.sellToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            require(msg.value >= sellArgs.sellAmount, "tx value is not enough");
        } else {
            bool succ = IERC20(sellArgs.sellToken).transferFrom(
                msg.sender,
                address(this),
                sellArgs.sellAmount
            );
            require(succ, "erc20 transfer failed");
            require(
                IERC20(sellArgs.sellToken).approve(zeroEx, sellArgs.sellAmount),
                "erc20 approve failed"
            );
        }
        uint256 bridgeUSDCAmount;
        if (sellArgs.sellToken == usdc) {
            bridgeUSDCAmount = sellArgs.sellAmount;
        } else {
            uint256 usdc_bal_0 = IERC20(usdc).balanceOf(address(this));
            _zeroExSwap(sellArgs.sellcalldata, sellArgs.sellcallgas);
            uint256 usdc_bal_1 = IERC20(usdc).balanceOf(address(this));

            bridgeUSDCAmount = ((usdc_bal_1 - usdc_bal_0) * 999) / 1000;
        }

        // bridge usdc
        require(
            IERC20(usdc).approve(address(tokenMessenger), bridgeUSDCAmount),
            "erc20 approve failed"
        );

        bytes32 destRouter = remoteRouter[destDomain];

        uint64 bridgeNonce = tokenMessenger.depositForBurnWithCaller(
            bridgeUSDCAmount,
            destDomain,
            destRouter,
            usdc,
            destRouter
        );

        // send swap message
        SwapMessage memory swapMessage = SwapMessage(
            version,
            bridgeUSDCAmount,
            buyArgs.buyToken,
            buyArgs.guaranteedBuyAmount,
            recipient,
            buyArgs.buycallgas,
            buyArgs.buycalldata
        );
        bytes memory messageBody = swapMessage.encode();
        uint64 swapMessageNonce = messageTransmitter.sendMessageWithCaller(
            destDomain,
            destRouter, // remote router will receive this message
            destRouter, // message will only submited through the remote router (handleBridgeAndSwap)
            messageBody
        );
        emit SwapAndBridge(
            sellArgs.sellToken,
            sellArgs.sellAmount,
            bridgeUSDCAmount,
            buyArgs.buyToken.bytes32ToAddress(),
            buyArgs.guaranteedBuyAmount,
            destDomain,
            recipient.bytes32ToAddress(),
            bridgeNonce,
            swapMessageNonce
        );
        swapHashSender[
            keccak256(abi.encode(destDomain, swapMessageNonce))
        ] = msg.sender;
        return (bridgeNonce, swapMessageNonce);
    }

    function replaceSwapMessage(
        uint64 swapMessageNonce,
        MessageWithAttestation calldata originalMessage,
        uint32 destDomain,
        BuyArgs calldata buyArgs,
        address recipient
    ) public {
        require(
            swapHashSender[
                keccak256(abi.encode(destDomain, swapMessageNonce))
            ] == msg.sender
        );

        SwapMessage memory swapMessage = SwapMessage(
            version,
            0,
            buyArgs.buyToken,
            buyArgs.guaranteedBuyAmount,
            recipient.addressToBytes32(),
            buyArgs.buycallgas,
            buyArgs.buycalldata
        );

        messageTransmitter.replaceMessage(
            originalMessage.message,
            originalMessage.attestation,
            swapMessage.encode(),
            remoteRouter[destDomain]
        );
        emit ReplaceSwapMessage(
            buyArgs.buyToken.bytes32ToAddress(),
            buyArgs.guaranteedBuyAmount,
            destDomain,
            recipient,
            swapMessageNonce
        );
    }

    /// Relayer entrance
    function relay(
        MessageWithAttestation calldata bridgeMessage,
        MessageWithAttestation calldata swapMessage
    ) public {
        // verifys bridge message attestation and mint usdc to this contract
        uint256 usdc_bal_0 = IERC20(usdc).balanceOf(address(this));
        messageTransmitter.receiveMessage(
            bridgeMessage.message,
            bridgeMessage.attestation
        );
        uint256 usdc_bal_1 = IERC20(usdc).balanceOf(address(this));
        require(usdc_bal_1 >= usdc_bal_0, "usdc bridge error");

        // verifys swap message attestation
        messageTransmitter.receiveMessage(
            swapMessage.message,
            swapMessage.attestation
        );

        SwapMessage memory swapArgs = swapMessage.message.body().decode();

        address recipient = swapArgs.recipient.bytes32ToAddress();
        uint256 bridgeUSDCAmount;
        if (swapArgs.sellAmount == 0) {
            bridgeUSDCAmount = usdc_bal_1 - usdc_bal_0;
        } else {
            bridgeUSDCAmount = swapArgs.sellAmount;
            require(
                bridgeUSDCAmount <= (usdc_bal_1 - usdc_bal_0),
                "router did not receive enough usdc"
            );
        }
        require(
            IERC20(usdc).approve(zeroEx, bridgeUSDCAmount),
            "erc20 approve failed"
        );

        require(swapArgs.version == version, "wrong swap message version");

        uint256 buyToken_bal_0;
        if (
            swapArgs.buyToken == bytes32(0) ||
            swapArgs.buyToken == usdc.addressToBytes32()
        ) {
            // receive usdc
            bool succ = IERC20(usdc).transfer(recipient, bridgeUSDCAmount);
            require(succ, "erc20 transfer failed");
        } else if (
            swapArgs.buyToken ==
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE.addressToBytes32()
        ) {
            // convert usdc to eth
            buyToken_bal_0 = address(this).balance;

            try this.zeroExSwap(swapArgs.swapdata, swapArgs.callgas) {} catch {
                IERC20(usdc).transfer(recipient, bridgeUSDCAmount);
                return;
            }

            uint256 buyToken_bal_1 = address(this).balance;
            require(
                buyToken_bal_1 - buyToken_bal_0 >= swapArgs.guaranteedBuyAmount,
                "swap output not enough"
            );
            (bool succ, ) = recipient.call{
                value: buyToken_bal_1 - buyToken_bal_0
            }("");
            require(succ, "send eth failed");
        } else {
            // convert usdc to erc20
            buyToken_bal_0 = IERC20(swapArgs.buyToken.bytes32ToAddress())
                .balanceOf(address(this));

            try this.zeroExSwap(swapArgs.swapdata, swapArgs.callgas) {} catch {
                IERC20(usdc).transfer(recipient, bridgeUSDCAmount);
                return;
            }

            uint256 buyToken_bal_1 = IERC20(
                swapArgs.buyToken.bytes32ToAddress()
            ).balanceOf(address(this));
            require(
                buyToken_bal_1 - buyToken_bal_0 >= swapArgs.guaranteedBuyAmount,
                "swap output not enough"
            );
            bool succ = IERC20(swapArgs.buyToken.bytes32ToAddress()).transfer(
                recipient,
                buyToken_bal_1 - buyToken_bal_0
            );
            require(succ, "erc20 transfer failed");
        }
    }

    /// @dev Does not handle message.
    /// Returns a boolean to make message transmitter accept or refuse a message.
    function handleReceiveMessage(
        uint32 sourceDomain,
        bytes32 sender,
        bytes calldata messageBody
    ) external returns (bool) {
        require(
            msg.sender == address(messageTransmitter),
            "caller not allowed"
        );
        if (remoteRouter[sourceDomain] == sender) {
            return true;
        }
        return false;
    }
}