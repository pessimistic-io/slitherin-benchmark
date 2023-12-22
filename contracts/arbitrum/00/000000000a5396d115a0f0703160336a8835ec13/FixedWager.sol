//SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./BartrrBase.sol";

/// @title Bartrr Fixed Wager Contract
/// @notice This contract is used to manage fixed wagers for the Bartrr protocol.
contract FixedWager is BartrrBase {
    using SafeERC20 for IERC20;

    /// @notice Emitted when a wager is created
    /// @param wagerId The wager id
    /// @param userA The user who created the wager
    /// @param userB The user who will fill the wager (zero address if the wager is open for anyone to fill)
    /// @param wagerToken The token whose price was wagered
    /// @param wagerPrice The wagered price of wagerToken
    event WagerCreated(
        uint256 indexed wagerId,
        address indexed userA,
        address userB,
        address wagerToken,
        int256 wagerPrice
    );

    /// @notice Emitted when a wager is filled by the second party
    /// @param wagerId The wager id
    /// @param userA The user who created the wager
    /// @param userB The user who filled the wager
    /// @param wagerToken The token whose price was wagered
    /// @param wagerPrice The wagered price of wagerToken
    event WagerFilled(
        uint256 indexed wagerId,
        address indexed userA,
        address indexed userB,
        address wagerToken,
        int256 wagerPrice
    );

    constructor() {
        _transferOwnership(tx.origin);
    }

    struct Wager {
        bool above; // true if userA is betting above the price
        bool isFilled; // true if wager is filled
        bool isClosed; // true if the wager has been closed (redeemed or cancelled)
        address userA; // address of userA
        address userB; // address of userB (0x0 if p2m)
        address wagerToken; // token to be used for wager
        address paymentToken; // payment token is the token that is used to pay the wager
        int256 wagerPrice; // bet price -- USD price + 8 decimals
        uint256 amountUserA; // amount userA wagered
        uint256 amountUserB; // amount userB wagered
        uint256 duration; // duration of the wager
    }

    Wager[] public wagers; // array of wagers

    /// @notice Get all wagers
    /// @return All created wagers
    function getAllWagers() public view returns (Wager[] memory) {
        return wagers;
    }

    /// @notice Creates a new wager
    /// @param _userB address of userB (0x0 if p2m)
    /// @param _wagerToken address of token to be wagered on
    /// @param _paymentToken address of token to be paid with
    /// @param _wagerPrice bet price
    /// @param _amountUserA amount userA wagered
    /// @param _amountUserB amount userB wagered
    /// @param _duration duration of the wager
    /// @param _above true if userA is betting above the price
    function createWager(
        address _userB,
        address _wagerToken,
        address _paymentToken, // 0xeee... address if ETH
        int256 _wagerPrice,
        uint256 _amountUserA,
        uint256 _amountUserB,
        uint256 _duration,
        bool _above
    ) external payable nonReentrant {
        require(isInitialized, "Contract is not initialized");
        require(wagerTokens[_wagerToken] && refundableTimestamp[_wagerToken].refundable <= refundableTimestamp[_wagerToken].nonrefundable, "Token not allowed to be wagered on"); 
        require(paymentTokens[_paymentToken], "Token not allowed for payment");
        require(
            _duration >= MIN_WAGER_DURATION,
            "Wager duration must be at least one 1 day"
        );

        uint256 feeUserA = 0;

        if (_paymentToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) { // ETH
            require(
                msg.value == _amountUserA,
                "ETH wager must be equal to msg.value"
            );
            if (_userB == address(0)) { // p2m
                feeUserA = _calculateFee(_amountUserA, _paymentToken);
                _amountUserA = _amountUserA - feeUserA;
                _transfer(payable(feeAddress), feeUserA);
            }
        } else { // Tokens
            if (_userB != address(0)) { // p2p
                IERC20(_paymentToken).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _amountUserA
                );
            } else { // p2m
                feeUserA = _calculateFee(_amountUserA, _paymentToken);
                 _amountUserA = _amountUserA - feeUserA;

                IERC20(_paymentToken).safeTransferFrom(
                    msg.sender,
                    feeAddress,
                    feeUserA
                );

                IERC20(_paymentToken).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _amountUserA
                );
            }
        }
        _createWager(
            msg.sender,
            _userB,
            _wagerToken,
            _paymentToken,
            _wagerPrice,
            _amountUserA,
            _amountUserB,
            _duration,
            _above
        );
    }

    /// @notice Fills a wager and starts the wager countdown
    /// @param _wagerId id of the wager
    function fillWager(uint256 _wagerId) external payable nonReentrant {
        Wager memory wager = wagers[_wagerId];

        require(!wager.isFilled, "Wager already filled");
        require(refundableTimestamp[wager.wagerToken].refundable <= refundableTimestamp[wager.wagerToken].nonrefundable, "wager token not allowed");
        require(msg.sender != wager.userA, "Cannot fill own wager");

        if (wager.userB != address(0)) { // p2p
            require(msg.sender == wager.userB, "p2p restricted");
            if (wager.paymentToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) { // ETH
                require(
                    msg.value == wager.amountUserB,
                    "ETH wager must be equal to msg.value"
                );
                uint256 feeUserA = _calculateFee(wager.amountUserA, wager.paymentToken);
                wager.amountUserA = wager.amountUserA - feeUserA;

                uint256 feeUserB = _calculateFee(wager.amountUserB, wager.paymentToken);
                wager.amountUserB = wager.amountUserB - feeUserB;

                _transfer(payable(feeAddress), feeUserA + feeUserB);
            } else {
                uint256 feeUserA = _calculateFee(wager.amountUserA, wager.paymentToken);
                wager.amountUserA = wager.amountUserA - feeUserA;

                IERC20(wager.paymentToken).safeTransfer(
                    feeAddress,
                    feeUserA
                );

                uint256 feeUserB = _calculateFee(wager.amountUserB, wager.paymentToken);
                wager.amountUserB = wager.amountUserB - feeUserB;
                IERC20(wager.paymentToken).safeTransferFrom(
                    msg.sender,
                    feeAddress,
                    feeUserB
                );

                IERC20(wager.paymentToken).safeTransferFrom(
                    msg.sender,
                    address(this),
                    wager.amountUserB
                );
            }  
        } else { // p2m
            require(block.timestamp < createdTimes[_wagerId] + 30 days, "wager expired");
            wager.userB = msg.sender;
            if (wager.paymentToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                require(
                    msg.value == wager.amountUserB,
                    "ETH wager must be equal to msg.value"
                );
                uint256 feeUserB = _calculateFee(wager.amountUserB, wager.paymentToken);
                wager.amountUserB = wager.amountUserB - feeUserB;
                _transfer(payable(feeAddress), feeUserB);
            } else {
                uint256 feeUserB = _calculateFee(wager.amountUserB, wager.paymentToken);
                wager.amountUserB = wager.amountUserB - feeUserB;

                IERC20(wager.paymentToken).safeTransferFrom(
                    msg.sender,
                    feeAddress,
                    feeUserB
                );

                IERC20(wager.paymentToken).safeTransferFrom(
                    msg.sender,
                    address(this),
                    wager.amountUserB
                );
            }
        }

        endTimes[_wagerId] = wager.duration + block.timestamp;
        wager.isFilled = true;

        wagers[_wagerId] = wager; // update wager to storage

        emit WagerFilled(
            _wagerId,
            wager.userA,
            wager.userB,
            wager.wagerToken,
            wager.wagerPrice
        );
    }

    /// @notice Cancels a wager that has not been filled
    /// @dev Fee is not refunded if wager was created as p2m
    /// @param _wagerId id of the wager
    function cancelWager(uint256 _wagerId) external nonReentrant {
        Wager memory wager = wagers[_wagerId];
        require(msg.sender == wager.userA || msg.sender == wager.userB, "Only userA or UserB can cancel the wager");
        require(!wager.isFilled, "Wager has already been filled");

        wagers[_wagerId].isClosed = true;

        if (wager.paymentToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
            _transfer(payable(wager.userA), wager.amountUserA);
        } else {
            IERC20(wager.paymentToken).safeTransfer(wager.userA, wager.amountUserA);
        }
        emit WagerCancelled(_wagerId, msg.sender);
    }

    /// @notice Redeems a wager
    /// @param _wagerId id of the wager
    function redeem(uint256 _wagerId) external nonReentrant {
        Wager memory wager = wagers[_wagerId];
        require(wager.isFilled, "Wager has not been filled");
        require(!wager.isClosed, "Wager has already been closed");
        uint256 refundable = refundableTimestamp[wager.wagerToken].refundable;
        uint256 nonrefundable = refundableTimestamp[wager.wagerToken].nonrefundable;
        if (refundable > 0 && // token has been marked refundable at least once
        endTimes[_wagerId] > refundable && // wager wasn't complete when marked refundable
        (refundable > nonrefundable || nonrefundable > createdTimes[_wagerId]) || // wager was created before token was marked nonrefundable
         refundUserA[_wagerId] ||
         refundUserB[_wagerId]
        ) {
            _refundWager(_wagerId);
        } else {
            _redeemWager(_wagerId);
        }
    }

    /// @notice Returns the winner of the wager once it is completed
    /// @param _wagerId id of the wager
    /// @return winner The winner of the wager
    function checkWinner(uint256 _wagerId)
        public
        view
        returns (address winner)
    {
        Wager memory wager = wagers[_wagerId];
        require(wager.isFilled, "Wager has not been filled");
        uint256 endTime = endTimes[_wagerId];
        require(endTime <= block.timestamp, "wager not complete");

        AggregatorV2V3Interface feed = AggregatorV2V3Interface(oracles[wager.wagerToken]);

        uint80 roundId = getRoundId(feed, endTime);

        if (roundId == 0) {
            return address(0);
        }

        (int256 price,,) = _getHistoricalPrice(roundId, wager.wagerToken); // price is in USD with 8 decimals

        if (wager.above && price >= wager.wagerPrice) {
            return wager.userA;
        } else if (!wager.above && price <= wager.wagerPrice) {
            return wager.userA;
        } else if (wager.above && price < wager.wagerPrice) {
            return wager.userB;
        } else if (!wager.above && price > wager.wagerPrice) {
            return wager.userB;
        }
        revert();
    }

    function _createWager(
        address _userA,
        address _userB,
        address _wagerToken,
        address _paymentToken,
        int256 _wagerPrice,
        uint256 _amountUserA,
        uint256 _amountUserB,
        uint256 _duration,
        bool _above
    ) internal {
        Wager memory wager = Wager(
            _above,
            false,
            false,
            _userA,
            _userB,
            _wagerToken,
            _paymentToken,
            _wagerPrice,
            _amountUserA,
            _amountUserB,
            _duration
        );
        wagers.push(wager);
        createdTimes[idCounter] = block.timestamp;
        emit WagerCreated(idCounter, _userA, _userB, _wagerToken, _wagerPrice);
        idCounter++;
    }

    function _refundWager(uint256 _wagerId) internal {
        Wager memory wager = wagers[_wagerId];
        if (msg.sender == wager.userA) {
            require(!refundUserA[_wagerId], "UserA has already been refunded");
            refundUserA[_wagerId] = true;
            if (wager.paymentToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                _transfer(payable(wager.userA), wager.amountUserA);
            } else {
                IERC20(wager.paymentToken).safeTransfer(
                    wager.userA,
                    wager.amountUserA
                );
            }
            emit WagerRefunded(_wagerId, msg.sender, wager.paymentToken, wager.amountUserA);
        } else if (msg.sender == wager.userB) {
            require(!refundUserB[_wagerId], "UserB has already been refunded");
            refundUserB[_wagerId] = true;
            if (wager.paymentToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                _transfer(payable(wager.userB), wager.amountUserB);
            } else {
                IERC20(wager.paymentToken).safeTransfer(
                    wager.userB,
                    wager.amountUserB
                );
            }
            emit WagerRefunded(_wagerId, msg.sender, wager.paymentToken, wager.amountUserB);
        }
    }

    function _redeemWager(uint256 _wagerId) internal {
        Wager memory wager = wagers[_wagerId];
        require(endTimes[_wagerId] <= block.timestamp, "wager not complete");
        uint256 winningSum = wager.amountUserA + wager.amountUserB;
        address winner = checkWinner(_wagerId);

        wagers[_wagerId].isClosed = true;

        if (winner == address(0)) { // draw
            if (wager.paymentToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                _transfer(payable(wager.userA), wager.amountUserA);
                _transfer(payable(wager.userB), wager.amountUserB);
            } else {
                IERC20(wager.paymentToken).safeTransfer(
                    wager.userA,
                    wager.amountUserA
                );
                IERC20(wager.paymentToken).safeTransfer(
                    wager.userB,
                    wager.amountUserB
                );
            }
        } else {
            if (wager.paymentToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                _transfer(payable(winner), winningSum);
            } else {
                IERC20(wager.paymentToken).safeTransfer(
                    winner,
                    winningSum
                );
            }
        }
        emit WagerRedeemed(_wagerId, winner, wager.paymentToken, winningSum);
    }
}

