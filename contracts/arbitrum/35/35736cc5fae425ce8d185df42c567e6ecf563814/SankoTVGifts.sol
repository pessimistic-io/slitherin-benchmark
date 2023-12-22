// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable} from "./Ownable.sol";
import {ERC1155} from "./ERC1155.sol";
import {IFeeConverter} from "./IFeeConverter.sol";

error InvalidGift();
error InvalidAmount();
error InsufficientPayment();
error FundsTransferFailed();
error NotLiveYet();

contract SankoTVGifts is ERC1155, Ownable {
    struct Gift {
        // Denominated in ETH
        uint256 price;
        string uri;
    }

    struct MintArgs {
        address streamer;
        uint80 giftId;
        uint16 amount;
    }

    bool public live;
    IFeeConverter public feeConverter;
    address public protocolFeeDestination;
    uint256 public ethFeePercent;
    uint256 public dmtFeePercent;

    // Registry of the SankoTV gifts, mapped to their info (price and URI)
    mapping(uint96 giftId => Gift gift) public gifts;

    uint96 private _giftIdCounter = 0;

    event Minted(
        address indexed gifter,
        address indexed streamer,
        uint256 indexed giftId,
        uint256 amount,
        uint256 totalPrice,
        uint256 protocolFee
    );

    event GiftRegistered(uint96 indexed id, uint256 price, string uri);

    modifier whenLive() {
        if (!live) {
            revert NotLiveYet();
        }
        _;
    }

    constructor() {
        _initializeOwner(msg.sender);
    }

    function setLive() external onlyOwner {
        live = true;
    }

    function setFeeDestination(address _feeDestination) external onlyOwner {
        protocolFeeDestination = _feeDestination;
    }

    function setEthFeePercent(uint256 _feePercent) external onlyOwner {
        ethFeePercent = _feePercent;
    }

    function setDmtFeePercent(uint256 _feePercent) external onlyOwner {
        dmtFeePercent = _feePercent;
    }

    function setFeeConverter(IFeeConverter _feeConverter) external onlyOwner {
        feeConverter = _feeConverter;
    }

    function registerGift(uint256 price, string memory _uri)
        external
        onlyOwner
    {
        if (bytes(_uri).length == 0) {
            revert InvalidGift();
        }

        gifts[_giftIdCounter] = Gift(price, _uri);

        emit GiftRegistered(_giftIdCounter, price, _uri);

        _giftIdCounter++;
    }

    function updateGift(uint96 id, uint256 price, string memory _uri)
        external
        onlyOwner
    {
        if (bytes(_uri).length == 0) {
            revert InvalidGift();
        }

        Gift memory gift = gifts[id];
        if (bytes(gift.uri).length == 0) {
            revert InvalidGift();
        }
        gifts[id] = Gift(price, _uri);

        emit GiftRegistered(id, price, _uri);
        emit URI(_uri, id);
    }

    function tip(bytes32 args) external payable whenLive {
        MintArgs memory mintArgs = unpackMintArgs(args);
        address streamer = mintArgs.streamer;
        uint80 giftId = mintArgs.giftId;
        uint16 amount = mintArgs.amount;
        Gift memory selectedGift = gifts[giftId];

        if (bytes(selectedGift.uri).length == 0) {
            revert InvalidGift();
        }

        if (amount == 0) {
            revert InvalidAmount();
        }

        uint256 totalPrice = selectedGift.price * uint256(amount);
        uint256 ethFee = totalPrice * ethFeePercent / 1 ether;
        uint256 dmtFee = totalPrice * dmtFeePercent / 1 ether;
        uint256 totalFee = ethFee + dmtFee;
        if (msg.value < totalPrice) {
            revert InsufficientPayment();
        }

        _mint(streamer, giftId, amount, "");

        (bool streamerSend,) = streamer.call{value: totalPrice - totalFee}("");
        (bool protocolSend,) = protocolFeeDestination.call{value: ethFee}("");

        bool feeSend = true;
        if (dmtFee > 0) {
            feeSend = feeConverter.convertFees{value: dmtFee}();
        }
        if (!(streamerSend && protocolSend && feeSend)) {
            revert FundsTransferFailed();
        }

        emit Minted(
            msg.sender, streamer, giftId, uint256(amount), totalPrice, totalFee
        );
    }

    function uri(uint256 tokenId)
        public
        view
        override(ERC1155)
        returns (string memory)
    {
        return gifts[uint96(tokenId)].uri;
    }

    function unpackMintArgs(bytes32 args)
        private
        pure
        returns (MintArgs memory)
    {
        // 1. Extract the streamer address (first 20 bytes)
        address streamer = address(uint160(uint256(args) >> (96)));

        // 2. Extract the giftId (next 10 bytes)
        uint80 giftId = uint80(uint256(args) >> (16));

        // 3. Extract the amount (last 2 bytes)
        uint16 amount = uint16(uint256(args));

        return MintArgs({streamer: streamer, giftId: giftId, amount: amount});
    }

    function packMintArgs(MintArgs calldata args)
        public
        pure
        returns (bytes32)
    {
        return bytes32(
            (uint256(uint160(args.streamer)) << 96)
                | (uint256(args.giftId) << 16) | uint256(args.amount)
        );
    }
}

