// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ExcessivelySafeCall.sol";
import {IWETH} from "./IWETH.sol";

contract EscrowswapV1 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ExcessivelySafeCall for address;

    /// ------------ CUSTOM ERRORS ------------

    error ActiveEmergencyWithdrawal();
    error EmptyTrade();
    error OverTokenAmountLimit();
    error Unauthorized();
    error MisalignedTradeData();
    error UnexpectedEtherTransfer();
    error WrongAmountEtherTransfer();

    /// --------------------------------------

    bool public isEmergencyWithdrawalActive;
    uint32 private baseFee;
    uint32 immutable private BASE_FEE_DENOMINATOR;
    IWETH immutable private weth;
    address private feePayoutAddress;
    uint256 private idCounter;
    uint256 immutable private TOKEN_AMOUNT_LIMIT;

    struct TradeOffer {
        address seller;
        address tokenOffered;
        address tokenRequested;
        uint256 amountOffered;
        uint256 amountRequested;
    }

    /// ------------ STORAGE ------------

    mapping(uint256 => TradeOffer) private tradeOffers;
    mapping(bytes32 => uint32) private tradingPairFees;

    /// ------------ EVENTS ------------

    event TradeOfferCreated(uint256 id, address indexed seller, address indexed tokenOffered,
        address tokenRequested, uint256 indexed amountOffered, uint256 amountRequested);
    event TradeOfferAdjusted(uint256 indexed id, address tokenRequestedUpdated, uint256 amountRequestedUpdated);
    event TradeOfferAccepted(uint256 indexed id, address indexed buyer);
    event TradeOfferCancelled(uint256 indexed id);

    /// ------------ MODIFIERS ------------

    modifier nonEmergencyCall() {
        if (isEmergencyWithdrawalActive) { revert ActiveEmergencyWithdrawal(); }
        _;
    }

    /// ------------ CONSTRUCTOR ------------

    //Set _wethAddress for a multi-chain compatability
    constructor(address _wethAddress) {
        idCounter = 0;

        baseFee = 2_000; // 2000 / 100000 = 2.0%
        BASE_FEE_DENOMINATOR = 100_000;
        feePayoutAddress = owner();

        weth = IWETH(_wethAddress);
        TOKEN_AMOUNT_LIMIT = 23158e69;
        isEmergencyWithdrawalActive = false;
    }

    /// ------------ MAKER FUNCTIONS ------------

    function createTradeOffer(address _tokenOffered, uint256 _amountOffered, address _tokenRequested, uint256 _amountRequested)
    payable
    external
    nonReentrant
    nonEmergencyCall
    returns (uint256 tradeId)
    {
        if (_amountOffered == 0 || _amountRequested == 0) { revert EmptyTrade(); }
        if (_amountRequested > TOKEN_AMOUNT_LIMIT) { revert OverTokenAmountLimit(); }

        tradeId = idCounter;
        TradeOffer memory newOffer = TradeOffer({
            seller: msg.sender,
            tokenOffered: _tokenOffered,
            tokenRequested: _tokenRequested,
            amountOffered: _amountOffered,
            amountRequested: _amountRequested
        });

        tradeOffers[idCounter] = newOffer;

        ++idCounter;

        emit TradeOfferCreated(tradeId, newOffer.seller, newOffer.tokenOffered,
            newOffer.tokenRequested, newOffer.amountOffered, newOffer.amountRequested);

        _handleIncomingTransfer(
            msg.sender,
            _amountOffered,
            _tokenOffered,
            address(this)
        );
    }

    function adjustTradeOffer(uint256 _id, address _tokenRequestedUpdated, uint256 _amountRequestedUpdated)
    external
    nonEmergencyCall
    {
        if (_amountRequestedUpdated > TOKEN_AMOUNT_LIMIT) { revert OverTokenAmountLimit(); }
        TradeOffer storage trade = tradeOffers[_id];
        if (trade.seller != msg.sender) { revert Unauthorized(); }
        if (trade.amountOffered == 0) { revert EmptyTrade(); }

        trade.amountRequested = _amountRequestedUpdated;
        trade.tokenRequested = _tokenRequestedUpdated;

        emit TradeOfferAdjusted(_id, _tokenRequestedUpdated, _amountRequestedUpdated);
    }

    function cancelTradeOffer(uint256 _id) external nonReentrant {
        //saving gas: only necessary vars in the memory
        address trade_seller = tradeOffers[_id].seller;
        uint256 trade_amountOffered = tradeOffers[_id].amountOffered;
        address trade_tokenOffered = tradeOffers[_id].tokenOffered;

        if (trade_amountOffered == 0) { revert EmptyTrade(); }
        if (trade_seller != msg.sender) { revert Unauthorized(); }

        _deleteTradeOffer(_id);
        emit TradeOfferCancelled(_id);

        //Transfer from the vault back to the trade creator.
        _handleOutgoingTransfer(address(trade_seller), trade_amountOffered, trade_tokenOffered);
    }

    /// ------------ TAKER FUNCTIONS ------------

    function acceptTradeOffer(uint256 _id, address _tokenRequested, uint256 _amountRequested)
    payable
    external
    nonReentrant
    nonEmergencyCall
    {
        TradeOffer memory trade = tradeOffers[_id];

        if (trade.tokenRequested != _tokenRequested) { revert MisalignedTradeData(); }
        if (trade.amountRequested != _amountRequested) { revert MisalignedTradeData(); }
        if (trade.amountOffered == 0) { revert EmptyTrade(); }

        _deleteTradeOffer(_id);
        emit TradeOfferAccepted(_id, msg.sender);

        //Buyer transfers to seller, buyer pays the fee to the feePayoutAddress.
        _handleTakerTransfers(
            msg.sender,
            trade.amountRequested,
            trade.tokenRequested,
            address(trade.seller),
            getTradingPairFee(_getTradingPairHash(trade.tokenRequested, trade.tokenOffered))
        );

        //Transfer from the vault to buyer.
        _handleOutgoingTransfer(msg.sender, trade.amountOffered, trade.tokenOffered);
    }

    /// ------------ MASTER FUNCTIONS ------------

    function switchEmergencyWithdrawal(bool _switch) external onlyOwner {
        isEmergencyWithdrawalActive = _switch;
    }

    function setTradingPairFee(bytes32 _hash, uint32 _fee) external onlyOwner {
        tradingPairFees[_hash] = _fee;
    }

    function deleteTradingPairFee(bytes32 _hash) external onlyOwner {
        delete tradingPairFees[_hash];
    }

    function setBaseFee(uint32 _fee) external onlyOwner {
        baseFee = _fee;
    }

    function setFeePayoutAddress(address _addr) external onlyOwner {
        feePayoutAddress = _addr;
    }

    /// ------------ VIEW FUNCTIONS ------------

    function getTradingPairFee(bytes32 _hash) public view returns (uint32)  {
        uint32 fee = tradingPairFees[_hash];
        if(fee == 0) return baseFee;
        return fee;
    }

    function getTradeOffer(uint256 _id) external view returns (TradeOffer memory) {
        return tradeOffers[_id];
    }

    /// ------------ HELPER FUNCTIONS ------------

    function _handleTakerTransfers(address _sender, uint256 _amountReq, address _tokenReq, address _dest, uint32 _tradingPairFee) private {
        // Sometimes decimal number of a token is too low or it's not possible to calculate
        // the fee without rounding it to ZERO.
        // In that case we request 1 unit of the token to be sent as a fee.
        uint256 fee = _tradingPairFee * _amountReq / BASE_FEE_DENOMINATOR;
        if (fee == 0) {
            fee = 1;
        }

        if (_tokenReq == address(0)) {
            if (msg.value != _amountReq + fee) { revert WrongAmountEtherTransfer(); }

            //transfer from buyer to seller
            _handleEthTransfer(_dest, _amountReq);
            //fee payment
            _handleEthTransfer(feePayoutAddress, fee);
        } else {
            if (msg.value != 0) { revert UnexpectedEtherTransfer(); }

            //transfer from buyer to seller
            IERC20(_tokenReq).safeTransferFrom(_sender, _dest, _amountReq);
            //fee payment
            IERC20(_tokenReq).safeTransferFrom(_sender, feePayoutAddress, fee);
        }
    }

    function _handleIncomingTransfer(address _sender, uint256 _amount, address _token, address _dest) private {
        if (_token == address(0)) {
            if (msg.value != _amount) { revert WrongAmountEtherTransfer(); }
        } else {
            if (msg.value != 0) { revert UnexpectedEtherTransfer(); }

            // We must check the balance that was actually transferred to this contract,
            // as some tokens impose a transfer fee and would not actually transfer the
            // full amount to the escrowswap, resulting in potentially locked funds
            IERC20 token = IERC20(_token);
            uint256 beforeBalance = token.balanceOf(_dest);
            token.safeTransferFrom(_sender, _dest, _amount);
            uint256 afterBalance = token.balanceOf(_dest);
            require(beforeBalance + _amount == afterBalance, "_handleIncomingTransfer token transfer call did not transfer expected amount");
        }
    }

    function _handleOutgoingTransfer(address _dest, uint256 _amount, address _token) private {
        // Handle ETH payment
        if (_token == address(0)) {
            _handleEthTransfer(_dest, _amount);
        } else {
            IERC20(_token).safeTransfer(_dest, _amount);
        }
    }

    function _handleEthTransfer(address _dest, uint256 _amount) private {
        // Using excessivelySafeCall to avoid "returnbombs".
        // Expecting only a single return bool value we specified a _maxCopy of 0 bytes.
        // Refusing to copy large blobs to local memory effectively prevents
        // the callee from triggering local OOG reversion in fallback function.
        (bool success, ) = _dest.excessivelySafeCall(gasleft(), _amount, 0, "");

        // If the ETH transfer fails, wrap the ETH and try send it as WETH.
        if (!success) {
            weth.deposit{value: _amount}();
            IERC20(address(weth)).safeTransfer(_dest, _amount);
        }
    }

    function _deleteTradeOffer(uint256 _id) private {
        delete tradeOffers[_id];
    }

    function _getTradingPairHash(address _token0, address _token1) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_token0, _token1));
    }
}

