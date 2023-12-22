//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import {Ownable} from "./Ownable.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

contract Escrow is Ownable {
    using SafeERC20 for IERC20;

    /// @dev The trade fee percentage
    uint256 public tradeFeePercentage;

    /// @dev Fee distributor address
    address public feeDistributor;

    /// ================================ MAPPINGS ================================

    /// @dev token symbol => address
    mapping(address => bool) public quoteAddresses;

    /// @dev token address => boolean
    mapping(address => bool) public baseAddresses;

    /// @dev keccak256(quote, base,  dealer, counterParty) => balance
    mapping(bytes32 => uint256) public balances;

    /// @dev keccak256(base, quote, dealer, counterParty) => amount
    mapping(bytes32 => uint256) public pendingBalances;

    /// ================================ EVENTS ================================

    event AddToken(address indexed asset, bool isQuote);

    event RemoveToken(address asset);

    event Open(
        address indexed dealer,
        address indexed counterParty,
        address quote,
        address base,
        uint256 sendAmount,
        uint256 receiveAmount
    );

    event Cancel(
        address indexed dealer,
        address indexed counterParty,
        address quote,
        address base,
        uint256 withdrawAmount
    );

    event Fulfill(
        address indexed counterParty,
        address indexed dealer,
        address quote,
        address base,
        uint256 dealerSendAmount,
        uint256 dealerReceiveAmount
    );

    /// ================================ CONSTRUCTOR ================================

    constructor(
        address[] memory quotes,
        address[] memory bases,
        address _feeDistributor
    ) {
        require(_feeDistributor != address(0), 'E1');

        for (uint256 i = 0; i < quotes.length; i++) {
            require(quotes[i] != address(0), 'E1');
            quoteAddresses[quotes[i]] = true;
        }

        for (uint256 i = 0; i < bases.length; i++) {
            require(bases[i] != address(0), 'E1');
            baseAddresses[bases[i]] = true;
        }

        tradeFeePercentage = 1e15; // 0.1% in 1e18 precision
        feeDistributor = _feeDistributor;
    }

    /// ================================ Functions ================================

    /// @notice update fee percentage
    /// @param newFee new fee percentage
    function updateTradeFeePercentage(uint256 newFee) external onlyOwner {
        tradeFeePercentage = newFee;
    }

    /// @notice update the fee distributor address
    /// @param _feeDistributor the fee distributor address
    function updateFeeDistributor(address _feeDistributor) external onlyOwner {
        feeDistributor = _feeDistributor;
    }

    /// @notice Add a quote asset to Escrow
    /// @param token asset address
    function addQuoteToken(address token) external onlyOwner returns (bool) {
        require(token != address(0), 'E1');

        quoteAddresses[token] = true;

        emit AddToken(token, true);

        return true;
    }

    /// @notice Add asset to Escrow
    /// @param tokens asset address
    function addBaseTokens(address[] calldata tokens)
        external
        onlyOwner
        returns (bool)
    {
        address token;
        for (uint256 i = 0; i < tokens.length; i++) {
            token = tokens[i];

            require(token != address(0), 'E1');

            baseAddresses[token] = true;

            emit AddToken(token, false);
        }

        return true;
    }

    /// @notice Remove asset
    /// @param tokens asset address
    function removeTokens(address[] calldata tokens)
        external
        onlyOwner
        returns (bool)
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokens[i] != address(0), 'E1');

            baseAddresses[tokens[i]] = false;
            quoteAddresses[tokens[i]] = false;

            emit RemoveToken(tokens[i]);
        }

        return true;
    }

    /// @notice Open a trade on the Escrow
    /// @dev Dealer locks collateral in Escrow for a specified base asset & amount
    /// @param quote dealer's quote
    /// @param base dealer's base
    /// @param counterParty counter-party address
    /// @param sendAmount of quote to lock
    /// @param receiveAmount amount of base required
    /// @return whether open() was called successfully
    function open(
        address quote,
        address base,
        address counterParty,
        uint256 sendAmount,
        uint256 receiveAmount
    ) external returns (bool) {
        require(quoteAddresses[quote] || baseAddresses[quote], 'E3');
        require(quoteAddresses[base] || baseAddresses[base], 'E3');
        bytes32 balancesId = keccak256(
            abi.encodePacked(quote, base, msg.sender, counterParty)
        );
        bytes32 pendingBalancesId = keccak256(
            abi.encodePacked(base, quote, msg.sender, counterParty)
        );

        require(balances[balancesId] == 0, 'E4');
        require(counterParty != address(0), 'E5');

        balances[balancesId] = sendAmount;
        pendingBalances[pendingBalancesId] = receiveAmount;

        IERC20(quote).safeTransferFrom(msg.sender, address(this), sendAmount);

        emit Open(
            msg.sender,
            counterParty,
            quote,
            base,
            sendAmount,
            receiveAmount
        );

        return true;
    }

    /// @notice Withdraw deposits
    /// @dev Update pendingBalances to cancel a dealer's open trade
    /// @param quote dealer's quote asset to withdraw
    /// @param base dealer's selected base asset for trade
    /// @param counterParty of quote to withdraw from escrow
    /// @return withdrawAmount
    function cancel(
        address quote,
        address base,
        address counterParty
    ) external returns (uint256) {
        bytes32 balancesId = keccak256(
            abi.encodePacked(quote, base, msg.sender, counterParty)
        );
        bytes32 pendingBalancesId = keccak256(
            abi.encodePacked(base, quote, msg.sender, counterParty)
        );

        uint256 withdrawAmount = balances[balancesId];

        require(
            balances[balancesId] != 0 &&
                pendingBalances[pendingBalancesId] != 0,
            'E6'
        );

        balances[balancesId] = 0;
        pendingBalances[pendingBalancesId] = 0;

        IERC20(quote).safeTransfer(msg.sender, withdrawAmount);

        emit Cancel(msg.sender, counterParty, quote, base, withdrawAmount);

        return withdrawAmount;
    }

    /// @notice Settle trade on behalf of dealer
    /// @dev Invoked by counter-party. The trade is fulfilled only if the base asset
    /// address of CP matches dealer's required quote
    /// @param quote quote asset w.r.t dealer (cp's base asset)
    /// @param base base asset w.r.t dealer (cp's quote asset)
    /// @param dealer address of dealer
    /// @return whether trade was fulfilled
    function fulfill(
        address quote,
        address base,
        address dealer
    ) external returns (bool) {
        require(quoteAddresses[quote] || baseAddresses[quote], 'E3');
        require(quoteAddresses[base] || baseAddresses[base], 'E3');

        bytes32 balancesId = keccak256(
            abi.encodePacked(quote, base, dealer, msg.sender)
        );
        bytes32 pendingBalancesId = keccak256(
            abi.encodePacked(base, quote, dealer, msg.sender)
        );

        require(
            balances[balancesId] != 0 &&
                pendingBalances[pendingBalancesId] != 0,
            'E7'
        );

        uint256 lockedAmount = balances[balancesId];
        uint256 paymentAmount = pendingBalances[pendingBalancesId];

        bool isBuy = quoteAddresses[quote];

        // dealer buy order => charge fee on quote
        // dealer sell order => charge fee on base
        uint256 fee = calculateSettlementFees(
            isBuy ? quote : base,
            isBuy ? lockedAmount : paymentAmount
        );

        // transfer asset to dealer minus fee
        pendingBalances[pendingBalancesId] = 0;
        IERC20(base).safeTransferFrom(
            msg.sender,
            dealer,
            isBuy ? paymentAmount : paymentAmount - fee
        );

        // transfer asset to counter-party
        balances[balancesId] = 0;
        IERC20(quote).safeTransfer(
            msg.sender,
            isBuy ? lockedAmount - fee : lockedAmount
        );

        // Transfer fee to fee distributor
        if (isBuy) {
            IERC20(quote).safeTransfer(feeDistributor, fee);
        } else {
            IERC20(base).safeTransferFrom(msg.sender, feeDistributor, fee);
        }

        emit Fulfill(
            msg.sender,
            dealer,
            quote,
            base,
            lockedAmount,
            paymentAmount
        );

        return true;
    }

    /// ================================ View Functions ================================

    /// @notice Calculate fee on completion of trade
    /// @dev Account for asset decimals
    /// @param asset asset to charge a fee on
    /// @param amount quote amount
    /// @return fee
    function calculateSettlementFees(address asset, uint256 amount)
        public
        view
        returns (uint256)
    {
        require(quoteAddresses[asset], 'E11');
        return (tradeFeePercentage * amount) / 1e18;
    }
}
// {
//   "E1": "Escrow: Invalid address",
//   "E2": "Escrow: Address array length mismatch",
//   "E3": "Escrow: Invalid Quote/Base",
//   "E4": "Escrow: User already deposited quote",
//   "E5": "Escrow: Invalid target address",
//   "E6": "Escrow: No order to cancel",
//   "E7": "Escrow: No order to fulfill",
// }

