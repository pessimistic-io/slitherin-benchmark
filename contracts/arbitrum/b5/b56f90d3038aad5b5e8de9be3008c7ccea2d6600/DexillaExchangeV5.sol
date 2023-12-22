// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.19;

import "./IERC20.sol";
import "./IWETH.sol";
import "./Multicall.sol";
import "./SelfPermit.sol";
import "./TransferHelper.sol";
import "./AccessControl.sol";
import "./ReentrancyGuard.sol";

contract DexillaExchangeV5 is AccessControl, ReentrancyGuard, Multicall, SelfPermit {
    bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR_ROLE");

    uint public tradeFee = 10; // 0.1%
    uint public totalBaseFee = 0;
    uint public totalQuoteFee = 0;

    uint8 private immutable BASE_TOKEN_DECIMALS;
    uint8 private immutable QUOTE_TOKEN_DECIMALS;

    address public immutable baseToken;
    address public immutable quoteToken; // should be a USD token
    address public immutable weth;

    mapping(address => mapping(uint => uint)) public bids; // owner, price, quantity
    mapping(address => mapping(uint => uint)) public asks; // owner, price, quantity

    bool public pausedTrading = false;

    uint private _counter;

    // Event emitted when an order is created.
    event OrderCreated(address indexed maker, uint8 side, uint price, uint quantity);

    // Event emitted when an order is executed.
    event OrderExecuted(address indexed maker, address indexed taker, uint8 side, uint price, uint quantity, uint fee);

    // Event emitted when the size of an order is adjusted.
    event OrderSizeAdjusted(address indexed maker, uint8 side, uint price, uint quantity);

    // Event emitted when an order is canceled.
    event OrderCanceled(address indexed maker, uint8 side, uint price, uint quantity);

    // Event emitted when accumulated fees are withdrawn.
    event FeeWithdrawn(address indexed owner, uint baseFee, uint quoteFee);

    // Event emitted when the trade fee is adjusted.
    event TradeFeeAdjusted(uint tradeFee);

    // Event emitted when trading is paused or resumed.
    event TradingPaused(bool oldPauseTrading, bool newPauseTrading);

    modifier resetCounter() {
        // Using this modifier to deal native token transfer when using multi order execution
        _;
        _counter = 0;
    }

    modifier whenNotPausedTrading() {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!pausedTrading, "Trading is paused");
        _;
    }

    /**
     * @notice Contract constructor.
     * @param _baseToken The address of the base token used for trading.
     * @param _quoteToken The address of the quote token used for trading.
     * @param _weth The address of the WETH (Wrapped Ether) token.
     * @param feeCollector The address of the fee collector.
     * @param _tradeFee The trade fee amount.
     * @dev This constructor is used to initialize the contract with the specified parameters.
     */
    constructor(address _baseToken, address _quoteToken, address _weth, address feeCollector, uint _tradeFee) {
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        weth = _weth;
        tradeFee = _tradeFee;
        BASE_TOKEN_DECIMALS = IERC20(baseToken).decimals();
        QUOTE_TOKEN_DECIMALS = IERC20(quoteToken).decimals();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FEE_COLLECTOR_ROLE, feeCollector);
    }

    /**
     * @param side The side of the order (0 for buy, 1 for sell).
     * @param price The price of the order.
     * @param quantity The quantity of the order.
     * @dev This function is used to create an order. It takes the side, price, and quantity as parameters.
     * @notice DO NOT PASS msg.value MORE THAN THE ACTUAL NEEDED AMOUNT, IT WILL BE LOST FOREVER.
     */
    function createOrder(uint8 side, uint price, uint quantity) public payable nonReentrant whenNotPausedTrading {
        _createOrder(side, price, quantity);
    }

    /**
     * @param side The side of the order (0 for buy, 1 for sell).
     * @param price The price of the order.
     * @param quantity The quantity of the order.
     * @param allowance The allowance granted by the user to spend their tokens.
     * @param deadline The deadline for the permit signature.
     * @param v The recovery byte of the permit signature.
     * @param r The R part of the permit signature.
     * @param s The S part of the permit signature.
     * @dev This function is used to create an order with a permit, which allows spending the user's tokens.
     * @notice DO NOT PASS msg.value MORE THAN THE ACTUAL NEEDED AMOUNT, IT WILL BE LOST FOREVER.
     */
    function createOrderWithPermit(
        uint8 side,
        uint price,
        uint quantity,
        uint allowance,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable nonReentrant whenNotPausedTrading {
        selfPermit(baseToken, allowance, deadline, v, r, s);
        _createOrder(side, price, quantity);
    }

    /**
     * @param side The side of the order (0 for buy, 1 for sell).
     * @param price The price of the order.
     * @param quantity The quantity of the order.
     * @param allowance The allowance granted by the user to spend their tokens.
     * @param deadline The deadline for the permit signature.
     * @param signature The signature containing the permit data.
     * @dev This function is used to create an order with a permit, which allows spending the user's tokens.
     * @notice DO NOT PASS msg.value MORE THAN THE ACTUAL NEEDED AMOUNT, IT WILL BE LOST FOREVER.
     */
    function createOrderWithPermit2(
        uint8 side,
        uint price,
        uint quantity,
        uint allowance,
        uint deadline,
        bytes calldata signature
    ) external payable nonReentrant whenNotPausedTrading {
        selfPermit2(baseToken, allowance, deadline, signature);
        _createOrder(side, price, quantity);
    }

    /**
     * @param makers The array of maker addresses involved in the order.
     * @param side The side of the order (0 for buy, 1 for sell).
     * @param price The price of the order.
     * @param quantity The quantity of the order.
     * @dev This function is used to execute an order. It takes an array of maker addresses,
     * @notice DO NOT PASS msg.value MORE THAN THE ACTUAL NEEDED AMOUNT, IT WILL BE LOST FOREVER.
     */
    function executeOrder(
        address[] memory makers,
        uint8 side,
        uint price,
        uint quantity
    ) public payable nonReentrant whenNotPausedTrading {
        _executeOrder(makers, side, price, quantity);
    }

    /**
     * @param makers The array of maker addresses involved in the order.
     * @param side The side of the order (0 for buy, 1 for sell).
     * @param price The price of the order.
     * @param quantity The quantity of the order.
     * @param allowance The allowance granted by the user to spend their tokens.
     * @param deadline The deadline for the permit signature.
     * @param v The recovery byte of the permit signature.
     * @param r The R part of the permit signature.
     * @param s The S part of the permit signature.
     * @dev This function is used to execute an order with a permit, which allows spending the user's tokens.
     * @notice DO NOT PASS msg.value MORE THAN THE ACTUAL NEEDED AMOUNT, IT WILL BE LOST FOREVER.
     */
    function executeOrderWithPermit(
        address[] memory makers,
        uint8 side,
        uint price,
        uint quantity,
        uint allowance,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable nonReentrant whenNotPausedTrading {
        if (side == 0) {
            selfPermit(quoteToken, allowance, deadline, v, r, s);
        } else {
            selfPermit(baseToken, allowance, deadline, v, r, s);
        }
        _executeOrder(makers, side, price, quantity);
    }

    /**
     * @param makers The array of maker addresses involved in the order.
     * @param side The side of the order (0 for buy, 1 for sell).
     * @param price The price of the order.
     * @param quantity The quantity of the order.
     * @param allowance The allowance granted by the user to spend their tokens.
     * @param deadline The deadline for the permit signature.
     * @param signature The signature containing the permit data.
     * @dev This function is used to execute an order with a permit, which allows spending the user's tokens.
     * @notice DO NOT PASS msg.value MORE THAN THE ACTUAL NEEDED AMOUNT, IT WILL BE LOST FOREVER.
     */
    function executeOrderWithPermit2(
        address[] memory makers,
        uint8 side,
        uint price,
        uint quantity,
        uint allowance,
        uint deadline,
        bytes calldata signature
    ) public payable nonReentrant whenNotPausedTrading {
        if (side == 0) {
            selfPermit2(quoteToken, allowance, deadline, signature);
        } else {
            selfPermit2(baseToken, allowance, deadline, signature);
        }
        _executeOrder(makers, side, price, quantity);
    }

    /**
     * @param side The side of the order (0 for buy, 1 for sell).
     * @param price The price of the order.
     * @param desiredQuantity The desired quantity to adjust the order to.
     * @dev This function is used to adjust the size of an existing order. It takes the side, price,
     * @notice DO NOT PASS msg.value MORE THAN THE ACTUAL NEEDED AMOUNT, IT WILL BE LOST FOREVER.
     */
    function adjustOrderSize(
        uint8 side,
        uint price,
        uint desiredQuantity
    ) public payable nonReentrant whenNotPausedTrading {
        _adjustOrderSize(side, price, desiredQuantity);
    }

    /**
     * @param side The side of the order (0 for buy, 1 for sell).
     * @param price The price of the order.
     * @dev This function is used to cancel an existing order. It takes the side and price as parameters.
     */
    function cancelOrder(uint8 side, uint price) public nonReentrant {
        require(side < 2, "Invalid side");

        uint quantity;
        if (side == 0) {
            quantity = bids[msg.sender][price];
            require(quantity > 0, "No bid found");
            delete bids[msg.sender][price];
            uint _quantity = _multiply(quantity, BASE_TOKEN_DECIMALS, price, QUOTE_TOKEN_DECIMALS);
            _transfer(quoteToken, msg.sender, _quantity);
        } else {
            quantity = asks[msg.sender][price];
            require(quantity > 0, "No ask found");
            delete asks[msg.sender][price];
            _transfer(baseToken, msg.sender, quantity);
        }

        emit OrderCanceled(msg.sender, side, price, quantity);
    }

    /**
     * @param newTradeFee The new trade fee to be set.
     * @dev This function is used by the default admin role to adjust the trade fee.
     */
    function adjustTradeFee(uint16 newTradeFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTradeFee <= 1000, "Invalid trade fee");
        tradeFee = newTradeFee;

        emit TradeFeeAdjusted(newTradeFee);
    }

    /**
     * @dev This function is used by the fee collector role to withdraw accumulated fees.
     */
    function withdrawFee() external onlyRole(FEE_COLLECTOR_ROLE) {
        _transfer(baseToken, msg.sender, totalBaseFee);
        _transfer(quoteToken, msg.sender, totalQuoteFee);
        emit FeeWithdrawn(msg.sender, totalBaseFee, totalQuoteFee);
        totalBaseFee = 0;
        totalQuoteFee = 0;
    }

    /**
     * @param state The new state to set for trading (true for paused, false for resumed).
     * @dev This function is used by the default admin role to set the pause state for trading.
     */
    function setPauseTrading(bool state) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bool oldState = pausedTrading;
        pausedTrading = state;

        emit TradingPaused(oldState, state);
    }

    /**
     * @param side The side of the order (0 for buy, 1 for sell).
     * @param price The price of the order.
     * @param quantity The quantity of the order.
     * @dev The 'resetCounter' modifier resets counters after executed.
     */
    function _createOrder(uint8 side, uint price, uint quantity) private resetCounter {
        require(side < 2, "Invalid side");
        require(price > 0, "Invalid price");

        if (side == 0) {
            uint quoteAmount = _multiply(quantity, BASE_TOKEN_DECIMALS, price, QUOTE_TOKEN_DECIMALS);
            _transferFrom(quoteToken, msg.sender, address(this), quoteAmount); // transfer quote token to this contract
            bids[msg.sender][price] += quantity;
        } else {
            _transferFrom(baseToken, msg.sender, address(this), quantity); // transfer base token to this contract
            asks[msg.sender][price] += quantity;
        }

        emit OrderCreated(msg.sender, side, price, quantity);
    }

    /**
     * @param makers The array of maker addresses involved in the order.
     * @param side The side of the order (0 for buy, 1 for sell).
     * @param price The price of the order.
     * @param quantity The quantity of the order.
     * @dev The 'resetCounter' modifier resets counters after executed.
     */
    function _executeOrder(address[] memory makers, uint8 side, uint price, uint quantity) private resetCounter {
        require(side < 2, "Invalid side");

        uint remainningQuantity = quantity;
        for (uint i; i < makers.length; ++i) {
            require(makers[i] != address(0), "Invalid maker");
            if (side == 0) {
                uint makerQuantity = asks[makers[i]][price];
                if (makerQuantity == 0) continue;
                uint transferQuantity;
                if (makerQuantity >= remainningQuantity) {
                    transferQuantity = remainningQuantity;
                    remainningQuantity = 0;
                } else {
                    transferQuantity = makerQuantity;
                    remainningQuantity = remainningQuantity - makerQuantity;
                }
                uint makerTransferQuantity = _multiply(
                    transferQuantity,
                    BASE_TOKEN_DECIMALS,
                    price,
                    QUOTE_TOKEN_DECIMALS
                );
                _transferFrom(quoteToken, msg.sender, makers[i], makerTransferQuantity); // transfer qoute token from taker to maker
                uint fee = (transferQuantity * tradeFee) / 10000;
                totalBaseFee += fee;
                uint remainningToTaker = transferQuantity - fee;
                _transfer(baseToken, msg.sender, remainningToTaker); // transfer base token from contract to maker
                asks[makers[i]][price] -= transferQuantity;
                if (asks[makers[i]][price] == 0) {
                    delete asks[makers[i]][price];
                    emit OrderCanceled(makers[i], side ^ 1, price, transferQuantity);
                }
                emit OrderExecuted(makers[i], msg.sender, side, price, transferQuantity, fee);
            } else {
                uint makerQuantity = bids[makers[i]][price];
                if (makerQuantity == 0) {
                    if (msg.value == 0) continue;
                    revert("No ask found");
                }
                uint transferQuantity;
                if (makerQuantity >= remainningQuantity) {
                    transferQuantity = remainningQuantity;
                    remainningQuantity = 0;
                } else {
                    transferQuantity = makerQuantity;
                    remainningQuantity = remainningQuantity - makerQuantity;
                }
                _transferFrom(baseToken, msg.sender, makers[i], transferQuantity); // transfer base from taker to maker
                uint quantityWithoutFee = _multiply(transferQuantity, BASE_TOKEN_DECIMALS, price, QUOTE_TOKEN_DECIMALS);
                uint fee = (quantityWithoutFee * tradeFee) / 10000;
                totalQuoteFee += fee;
                uint remainningToTaker = quantityWithoutFee - fee;
                _transfer(quoteToken, msg.sender, remainningToTaker); // transfer usd from contract to taker
                bids[makers[i]][price] -= transferQuantity;
                if (bids[makers[i]][price] == 0) {
                    delete bids[makers[i]][price];
                    emit OrderCanceled(makers[i], side ^ 1, price, transferQuantity);
                }
                emit OrderExecuted(makers[i], msg.sender, side, price, transferQuantity, fee);
            }
            if (remainningQuantity == 0) break;
        }
    }

    /**
     * @param side The side of the order (0 for buy, 1 for sell).
     * @param price The price of the order.
     * @param desiredQuantity The desired quantity to adjust the order to.
     * @dev This function assumes that the order exists and is valid. It does not perform any checks on the order's validity.
     */
    function _adjustOrderSize(uint8 side, uint price, uint desiredQuantity) private resetCounter {
        require(side < 2, "Invalid side");
        require(desiredQuantity > 0, "Invalid amount");

        uint oldQuantity;
        if (side == 0) {
            oldQuantity = bids[msg.sender][price];
            require(oldQuantity > 0, "Order does not exist");
            if (oldQuantity > desiredQuantity) {
                uint _quantity = _multiply(
                    oldQuantity - desiredQuantity,
                    BASE_TOKEN_DECIMALS,
                    price,
                    QUOTE_TOKEN_DECIMALS
                );
                _transfer(quoteToken, msg.sender, _quantity);
            } else if (oldQuantity < desiredQuantity) {
                uint _quantity = _multiply(
                    desiredQuantity - oldQuantity,
                    BASE_TOKEN_DECIMALS,
                    price,
                    QUOTE_TOKEN_DECIMALS
                );
                _transferFrom(quoteToken, msg.sender, address(this), _quantity); // transfer quote token to this contract
            }
            bids[msg.sender][price] = desiredQuantity;
        } else {
            oldQuantity = asks[msg.sender][price];
            require(oldQuantity > 0, "Order does not exist");
            if (oldQuantity > desiredQuantity) {
                _transfer(baseToken, msg.sender, oldQuantity - desiredQuantity);
            } else if (oldQuantity < desiredQuantity) {
                _transferFrom(baseToken, msg.sender, address(this), desiredQuantity - oldQuantity); // transfer base token to this contract
            }
            asks[msg.sender][price] = desiredQuantity;
        }

        emit OrderSizeAdjusted(msg.sender, side, price, desiredQuantity);
    }

    /**
     * @notice This function is used to multiply two numbers with decimal precision.
     * @param x The first number to multiply.
     * @param xDecimals The number of decimal places in the first number.
     * @param y The second number to multiply.
     * @param yDecimals The number of decimal places in the second number.
     * @return The product of the two numbers with proper decimal precision.
     */
    function _multiply(uint x, uint8 xDecimals, uint y, uint8 yDecimals) private pure returns (uint) {
        uint prod = x * y;
        uint8 prodDecimals = xDecimals + yDecimals;
        if (prodDecimals < yDecimals) {
            return prod * (10 ** (yDecimals - prodDecimals));
        } else if (prodDecimals > yDecimals) {
            return prod / (10 ** (prodDecimals - yDecimals));
        } else {
            return prod;
        }
    }

    /**
     * @notice This function is used to transfer tokens from the contract to a specified address.
     * @param token The address of the token to transfer.
     * @param to The address to transfer tokens to.
     * @param amount The amount of tokens to transfer.
     */
    function _transfer(address token, address to, uint amount) private {
        require(amount > 0, "Zero amount");
        if (token == weth) {
            IWETH(weth).withdraw(amount);
            TransferHelper.safeTransferETH(to, amount);
        } else {
            TransferHelper.safeTransfer(token, to, amount);
        }
    }

    /**
     * @notice Internal function to transfer tokens from a specified address to another address.
     * @param token The address of the token to transfer.
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param amount The amount of tokens to transfer.
     */
    function _transferFrom(address token, address from, address to, uint amount) private {
        require(amount > 0, "Zero amount");
        if (msg.value > 0) {
            _counter += amount;
            require(_counter <= msg.value, "Incorrect amount");
            if (token == weth) {
                IWETH(weth).deposit{value: amount}();
                if (to != address(this)) {
                    IWETH(weth).withdraw(amount);
                    TransferHelper.safeTransferETH(to, amount);
                }
            } else {
                revert("Invalid token");
            }
        } else {
            TransferHelper.safeTransferFrom(token, from, to, amount);
        }
    }

    /**
     *@notice Fallback function to receive Ether.
     *@dev This function is called when the contract receives Ether.
     */
    receive() external payable {
        require(msg.sender == weth, "Invalid sender");
    }

    /**
     * @notice This type of fallback function is triggered when a transaction is sent to the contract with no data
     * or when the transaction data doesn't match any existing function signatures.
     */
    fallback() external {
        revert();
    }
}

