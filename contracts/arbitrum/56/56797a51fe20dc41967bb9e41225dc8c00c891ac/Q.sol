// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IAccount} from "./IAccount.sol";
import {Errors} from "./Errors.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {Clones} from "./Clones.sol";
import {ECDSA} from "./ECDSA.sol";
import {IOperator} from "./IOperator.sol";
import {console} from "./console.sol";

contract Q {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public nonce;
    address public operator;
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant CROSS_CHAIN_TYPEHASH = keccak256("executeData(bytes memory data,uint256 nonce)");

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event InitQ(address indexed operator, bytes32 indexed domainSeparator, bytes32 indexed crossChainTypehash);
    event Deposit(
        address indexed trader,
        address indexed traderAccount,
        address indexed token,
        uint96 amount,
        uint256 returnAmount
    );
    event Withdraw(address indexed trader, address indexed traderAccount, address indexed token, uint96 amount);
    event Execute(bytes indexed data, uint256 msgValue);
    event CreateTraderAccount(address indexed trader, address indexed traderAccount);
    event CrossChainTrade(address indexed traderAccount, uint256 msgValue, bytes data, bytes signature);

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR/MODIFIERS
    //////////////////////////////////////////////////////////////*/

    constructor(address _operator) {
        operator = _operator;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ozo")),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
        emit InitQ(_operator, DOMAIN_SEPARATOR, CROSS_CHAIN_TYPEHASH);
    }

    modifier onlyAdmin() {
        address admin = IOperator(operator).getAddress("ADMIN");
        if (msg.sender != admin) revert Errors.NotAdmin();
        _;
    }

    modifier onlyPlugin() {
        bool isPlugin = IOperator(operator).getPlugin(msg.sender);
        if (!isPlugin) revert Errors.NotPlugin();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit multiple tokens to your account.
    /// @param tokens The addresses of the tokens to be deposited.
    /// @param amounts The amounts of the tokens to be deposited.
    function deposit(
        address[] calldata tokens,
        uint96[] calldata amounts,
        bytes[] calldata exchangeData,
        bytes[] calldata signature
    ) external {
        uint256 tLen = tokens.length;
        uint256 i;
        if (tLen != amounts.length) revert Errors.LengthMismatch();
        for (; i < tLen;) {
            deposit(tokens[i], amounts[i], exchangeData[i], signature[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Deposits token to your account.
    /// @param token The address of the token to be deposited.
    /// @param amount The amount of the token to be deposited.
    /// @param exchangeData data to transfer the token to the defaultStableCoin
    function deposit(address token, uint96 amount, bytes calldata exchangeData, bytes calldata signature)
        public
        payable
    {
        if (amount == 0) revert Errors.ZeroAmount();
        address defaultToken = IOperator(operator).getAddress("DEFAULTSTABLECOIN");

        if (token == address(0)) {
            if (msg.value != amount) revert Errors.InputMismatch();
        } else {
            uint256 tokenBalance = IERC20(token).balanceOf(msg.sender);
            if (amount > tokenBalance) revert Errors.BalanceLessThanAmount();
        }

        address account = IOperator(operator).getTraderAccount(msg.sender);
        if (account == address(0)) account = _createAccount(msg.sender);

        uint256 returnAmount;
        if (token != defaultToken) {
            if (exchangeData.length == 0) revert Errors.ExchangeDataMismatch();
            _verifyData(exchangeData, signature);
            address exchangeRouter = IOperator(operator).getAddress("ONEINCHROUTER");
            uint256 balanceBefore = IERC20(defaultToken).balanceOf(account);
            if (token != address(0)) {
                IERC20(token).safeTransferFrom(msg.sender, account, amount);
                bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, exchangeRouter, amount);
                IAccount(account).execute(token, approveData);
            }
            IAccount(account).execute{value: msg.value}(exchangeRouter, exchangeData);
            uint256 balanceAfter = IERC20(defaultToken).balanceOf(account);
            if (balanceAfter <= balanceBefore) revert Errors.BalanceLessThanAmount();
            returnAmount = balanceAfter - balanceBefore;
        } else {
            if (exchangeData.length != 0) revert Errors.ExchangeDataMismatch();
            IERC20(defaultToken).safeTransferFrom(msg.sender, account, amount);
        }
        emit Deposit(msg.sender, account, token, amount, returnAmount);
    }

    /// @notice withdraw any number of tokens from the `Account` contract
    /// @param token address of the token to be swapped
    /// @param amount total amount of `defaultStableCoin` to be withdrawn
    /// @param exchangeData calldata to swap from the dex
    function withdraw(address token, uint96 amount, bytes calldata exchangeData) external {
        if (amount == 0) revert Errors.ZeroAmount();
        address account = IOperator(operator).getTraderAccount(msg.sender);
        if (account == address(0)) revert Errors.NotInitialised();

        address defaultStableCoin = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
        uint256 tokenBalance = IERC20(defaultStableCoin).balanceOf(account);
        if (amount > tokenBalance) revert Errors.BalanceLessThanAmount();

        if (token == defaultStableCoin) {
            if (exchangeData.length != 0) revert Errors.ExchangeDataMismatch();
            bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", msg.sender, amount);
            IAccount(account).execute(defaultStableCoin, transferData);
        } else {
            address exchangeRouter = IOperator(operator).getAddress("ONEINCHROUTER");
            bytes memory approvalData = abi.encodeWithSignature("approve(address,uint256)", exchangeRouter, amount);
            IAccount(account).execute(defaultStableCoin, approvalData);
            uint256 defaultStableCoinBalanceBefore = IERC20(defaultStableCoin).balanceOf(account);
            IAccount(account).execute(exchangeRouter, exchangeData);
            uint256 defaultStableCoinBalanceAfter = IERC20(defaultStableCoin).balanceOf(account);
            if (defaultStableCoinBalanceBefore - defaultStableCoinBalanceAfter != amount) {
                revert Errors.ExchangeDataMismatch();
            }
        }

        emit Withdraw(msg.sender, account, token, amount);
    }

    /// @notice Deposit & execute a trade in one transaction.
    /// @param token The address of the token to be deposited.
    /// @param amount The amount of the token to be deposited.
    /// @param exchangeData data to transfer the token to the defaultStableCoin
    /// @param data The data to be executed.
    /// @param signature The signature of the data.
    function depositAndExecute(
        address token,
        uint96 amount,
        bytes calldata exchangeData,
        bytes calldata data,
        bytes calldata signature,
        bytes calldata exchangeDataSignature
    ) external payable {
        _verifyData(data, signature);
        deposit(token, amount, exchangeData, exchangeDataSignature);
        address perpTrade = IOperator(operator).getAddress("PERPTRADE");
        (bool success,) = perpTrade.call{value: msg.value}(data);
        if (!success) revert Errors.CallFailed(data);
        emit Execute(data, msg.value);
    }

    /// @notice execute the type of trade
    /// @dev can only be called by the `admin`
    /// @param command the command of the ddex protocol from `Commands` library
    /// @param data encoded data of parameters depending on the ddex
    /// @param isOpen bool to check if its an increase or decrease trade
    function execute(uint256 command, bytes calldata data, bool isOpen) public payable onlyAdmin {
        bytes memory tradeData = abi.encodeWithSignature("execute(uint256,bytes,bool)", command, data, isOpen);
        address perpTrade = IOperator(operator).getAddress("PERPTRADE");
        (bool success,) = perpTrade.call{value: msg.value}(tradeData);
        if (!success) revert Errors.CallFailed(tradeData);
        emit Execute(data, msg.value);
    }

    /// @notice executes many trades in a single function
    /// @dev can only be called by the `admin`
    /// @param commands array of commands of the ddex protocol from `Commands` library
    /// @param data array of encoded data of parameters depending on the ddex
    /// @param msgValue msg.value for each command which has to be transfered when executing the position
    /// @param isOpen array of bool to check if its an increase or decrease trade
    function multiExecute(
        uint256[] calldata commands,
        bytes[] calldata data,
        uint256[] calldata msgValue,
        bool[] calldata isOpen
    ) public payable onlyAdmin {
        if (data.length != msgValue.length) revert Errors.LengthMismatch();
        address perpTrade = IOperator(operator).getAddress("PERPTRADE");
        uint256 i;
        for (; i < data.length;) {
            uint256 command = commands[i];
            bytes calldata tradeData = data[i];
            uint256 value = msgValue[i];
            bool openOrClose = isOpen[i];

            bytes memory perpTradeData =
                abi.encodeWithSignature("execute(uint256,bytes,bool)", command, tradeData, openOrClose);
            (bool success,) = perpTrade.call{value: value}(perpTradeData);
            if (!success) revert Errors.CallFailed(perpTradeData);

            emit Execute(tradeData, value);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Creates a new account for the trader.
    /// @dev can only be called by a plugin
    /// @param trader The address of the trader.
    function createAccount(address trader) public onlyPlugin returns (address newAccount) {
        address traderAccount = IOperator(operator).getTraderAccount(trader);
        if (traderAccount != address(0)) revert Errors.AccountAlreadyExists();
        newAccount = _createAccount(trader);
        emit CreateTraderAccount(trader, newAccount);
    }

    /// @notice Trade on a exchange using lifi
    /// @dev The function should be called by lifi
    /// @param data The payload to be passed to the perpTrade contract
    /// @dev "user" is the address of the trader, so to get account we have to query traderAccount[user]
    function crossChainTradeReciever(bytes memory data, bytes memory signature) public payable {
        bool success;
        // EIP-712
        _verifyData(data, signature);

        (address token, address user, uint96 amount, bytes memory payload) =
            abi.decode(data, (address, address, uint96, bytes));

        address tradeAccount = IOperator(operator).getTraderAccount(user);
        if (tradeAccount == address(0)) tradeAccount = _createAccount(user);
        if (token != address(0)) _depositTo(token, tradeAccount, amount);

        address perpTrade = IOperator(operator).getAddress("PERPTRADE");
        (success, payload) = perpTrade.call{value: msg.value}(payload);
        if (!success) revert Errors.CallFailed(payload);

        emit CrossChainTrade(tradeAccount, msg.value, data, signature);
    }

    function sgReceive(uint16, bytes memory, uint256, address, uint256, bytes memory payload) external payable {
        bytes memory signature;
        (payload, signature) = abi.decode(payload, (bytes, bytes));
        crossChainTradeReciever(payload, signature);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createAccount(address trader) internal returns (address newAccount) {
        bytes32 salt = keccak256(abi.encodePacked(trader));
        address accountImplementation = IOperator(operator).getAddress("ACCOUNT");
        newAccount = Clones.cloneDeterministic(accountImplementation, salt);
        IOperator(operator).setTraderAccount(trader, newAccount);
    }

    /*
    
        * `TradeRemote` is a function that will only be called by lifi
        * It will be called when a trader wants to trade on a remote exchange
        
        FLOW:
            * TradeRemote called by lifi
            * DepositRemote fucntion is called from inside TradeRemote
                - it decodes msg.sender from the payload
                - it creates a new account for the trader, if not already exists
                - It transferFrom the tokens from the lifi to the Trader Account
            * Trade Remote Pass the payload to the perpTrade contract
            * perpTrade contract will execute the trade on the remote exchange
    */

    function _depositTo(address token, address user, uint256 amount) internal {
        if (amount == 0) revert Errors.ZeroAmount();

        uint256 tokenBalance = IERC20(token).balanceOf(msg.sender);
        if (amount > tokenBalance) revert Errors.BalanceLessThanAmount();

        IERC20(token).safeTransferFrom(msg.sender, user, amount);
    }

    function _verifyData(bytes memory data, bytes memory signature) internal {
        bytes32 structHash = keccak256(abi.encode(CROSS_CHAIN_TYPEHASH, data, nonce++));
        bytes32 signedData = ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
        address signer = ECDSA.recover(signedData, signature);
        address admin = IOperator(operator).getAddress("ADMIN");
        if (signer != admin) revert Errors.NotAdmin();
    }
}

