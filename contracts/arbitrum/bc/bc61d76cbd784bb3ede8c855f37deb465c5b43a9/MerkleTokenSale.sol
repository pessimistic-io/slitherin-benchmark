// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC20 } from "./ERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { MerkleProofLib } from "./MerkleProofLib.sol";

/// @title MerkleTokenSale
/// @notice Allows tokens to be exchanged at a fixed rate with the sell amount per address 
/// capped via merkle tree
/// @author Chris Dev <chrdevmar@gmail.com>
/// @dev tokens sold via this contract should be considered burnt as they are non recoverable
contract MerkleTokenSale is ReentrancyGuard {

    /// @notice token exchange calculations are done with an exchange rate with this precision
    uint256 constant public EXCHANGE_RATE_PRECISION = 1e18;

    /// @notice maximum sellable amount per address is defined in this merkle tree
    bytes32 public merkleRoot;

    /// @notice address of ERC20 token sold via this contract
    address public sellToken;

    /// @notice address of ERC20 token bought via this contract
    address[] public buyTokens;

    /// @notice amount of tokens available to buy from this contract
    /// @dev this increases when admin deposits and decreases when tokens are bought or recovered by admin address
    mapping(address => uint256) public buyTokenBalances;

    /// @notice amount of sellTokens received per 1 buyToken, raised to 10**18
    /// @dev must be same precision as EXCHANGE_RATE_PRECISION
    mapping(address => uint256) public buyTokenExchangeRates;

    /// @notice buy token decimals used for exchange amount calculations
    mapping(address => uint8) public buyTokenDecimals;

    /// @notice sell token decimals used for exchange amount calculations
    uint8 public sellTokenDecimals;

    /// @notice total sum of all tokens sold to this contract
    /// @dev tokens in excess of this amount can be recovered by admin address
    uint256 public totalSellTokensSold;

    /// @notice address that can perform admin functionality
    /// @dev this address must be non-zero on contract creation but can be set to 0 after deployment
    address public adminAddress;

    /// @notice keeps track of amounts that addresses have sold to date
    /// @dev this is used to prevent users from selling more than they are allowed to (over potentially multiple sales)
    mapping(address => uint256) public userSoldAmounts;

    /// @notice emitted when the admin address is initially set and when updated
    event AdminSet(
        address indexed adminAddress
    );

    /// @notice emitted when the merkle root is initially set and when updated
    event MerkleRootSet(
        bytes32 indexed merkleRoot
    );

    /// @notice emitted when the exchange rates are initially set and when updated
    event ExchangeRateSet(
        address indexed token,
        uint256 indexed exchangeRate
    );

    /// @notice emitted once per buy token when a sale is made
    event Sell(
        address indexed seller,
        address indexed buyToken,
        uint256 indexed buyAmount
    );

    /// @notice emitted when buy token is deposited
    event Deposit(
        address indexed token,
        uint256 indexed amount
    );

    /// @notice thrown when attempting to sell 0 tokens
    error InvalidSellAmount();

    /// @notice thrown when attempting to sell more tokens than allowed as per merkle tree
    error MaxSellableExceeded();

    /// @notice thrown when invalid merkle proof is provided during claim
    error InvalidMerkleProof();

    /// @notice thrown when non-admin address attempts to call admin functions
    error Unauthorised();

    /// @notice thrown when supplying 0 address for sellToken
    error InvalidSellToken();

    /// @notice thrown when supplying 0 address for buyToken
    error InvalidBuyToken();

    /// @notice thrown when number of buy tokens does not match number of exchange rates
    error BuyTokenCountMismatch();

    /// @notice thrown when supplying 0 address for adminAddress (only at contract creation)
    error InvalidAdminAddress();

    /// @notice thrown when supplying an exchangeRate of 0
    error InvalidExchangeRate();
    
    /// @notice thrown when calculated buyAmount is rounded to 0 due to small sellAmount
    error SellAmountTooSmall();

    /// @notice thrown when calculated buyAmount exceeds the current amount of buyTokens available
    error SellAmountTooBig();

    /// @notice thrown when there are no tokens available to claim
    error NoTokensToClaim();

    /// @notice thrown when there are no excess tokens available to recover by admin
    error NoTokensToRecover();

    /// @notice thrown when attempting to recover sellToken via generic recoverERC20 function
    error CannotRecoverSellToken();

    /// @notice thrown when attempting to recover buyToken via generic recoverERC20 function
    error CannotRecoverBuyToken();

    /// @notice thrown when attempting to send ETH to this contract via fallback method
    error FallbackNotPayable();
    
    /// @notice thrown when attempting to send ETH to this contract via receive method
    error ReceiveNotPayable();

    /// @notice ensures only admin address can call admin functions
    modifier onlyAdmin() {
        if(msg.sender != adminAddress) revert Unauthorised();
        _;
    }

    /// @notice creates a new MerkleTokenSale instance
    /// @param _sellToken address of token to sell to this contract
    /// @param _buyTokens addresses of tokens to buy from this contract
    /// @param _exchangeRates exchange rates of all tokens bought from this contract
    /// @param _adminAddress address allowed to call admin functions
    /// @param _merkleRoot root of merkle tree containg maximum sellable amount per address
    constructor(
        address _sellToken,
        address[] memory _buyTokens,
        uint256[] memory _exchangeRates,
        address _adminAddress,
        bytes32 _merkleRoot
    ) {
        if(_sellToken == address(0)) revert InvalidSellToken();
        sellToken = _sellToken;
        sellTokenDecimals = ERC20(_sellToken).decimals();

        if(_buyTokens.length != _exchangeRates.length) revert BuyTokenCountMismatch();

        for(uint256 i = 0; i < _buyTokens.length; i++) {
            address tokenAddress = _buyTokens[i];
            uint256 exchangeRate = _exchangeRates[i];
            if(tokenAddress == address(0)) revert InvalidBuyToken();
            if(tokenAddress == _sellToken) revert InvalidBuyToken();
            if(exchangeRate == 0) revert InvalidExchangeRate();

            buyTokens.push(tokenAddress);
            buyTokenDecimals[tokenAddress] = ERC20(tokenAddress).decimals();
            buyTokenExchangeRates[tokenAddress] = exchangeRate;
            emit ExchangeRateSet(tokenAddress, exchangeRate);
        }

        if(_adminAddress == address(0)) revert InvalidAdminAddress();
        adminAddress = _adminAddress;
        emit AdminSet(_adminAddress);

        merkleRoot = _merkleRoot;
        emit MerkleRootSet(_merkleRoot);
    }

    /// @notice validates the amount being sold against merkle proof and amount already sold to the contract
    /// @param sellAmount amount to be sold
    /// @param maxSellable maximum amount allow to sell as per merkle tree
    /// @param proof merkle proof containing address and maximum sell amount
    function _validateSellAmount(
        uint256 sellAmount, 
        uint256 maxSellable, 
        bytes32[] calldata proof
    ) private view {
        if(sellAmount == 0) revert InvalidSellAmount();

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, maxSellable));
        bool isValidLeaf = MerkleProofLib.verify(proof, merkleRoot, leaf);
        if (!isValidLeaf) revert InvalidMerkleProof();
        
        // prevent user from selling more than they are allowed to
        if (sellAmount > maxSellable - userSoldAmounts[msg.sender]) revert MaxSellableExceeded();
    }

    /// @notice sells an amount of sellAmount to the contract and received buyToken in return
    /// @param sellAmount amount to be sold
    /// @param maxSellable maximum amount allow to sell as per merkle tree
    /// @param proof merkle proof containing address and maximum sell amount
    function claimSale(uint256 sellAmount, uint256 maxSellable, bytes32[] calldata proof) public nonReentrant {
        _validateSellAmount(sellAmount, maxSellable, proof);

        // update sold amounts/transfer sell token from the seller once
        // and not in the loop body
        totalSellTokensSold += sellAmount;
        userSoldAmounts[msg.sender] += sellAmount;
        ERC20(sellToken).transferFrom(msg.sender, address(this), sellAmount);

        for(uint256 i = 0; i < buyTokens.length; i++) {
            address _buyTokenAddress = buyTokens[i];
            uint256 _buyTokenDecimals = buyTokenDecimals[_buyTokenAddress];
            uint256 _buyTokenBalance = buyTokenBalances[_buyTokenAddress];
            uint256 _buyTokenExchangeRate = buyTokenExchangeRates[_buyTokenAddress];

            uint256 normalisedSellAmount = _buyTokenDecimals == sellTokenDecimals
                ? sellAmount // same decimals, no normalising needed
                : sellTokenDecimals > _buyTokenDecimals
                ? sellAmount / (10 ** (sellTokenDecimals - _buyTokenDecimals)) // sellTokenDecimals > _buyTokenDecimals
                : sellAmount * (10 ** (_buyTokenDecimals - sellTokenDecimals)); // sellTokenDecimals < buyTokenDecimals

            uint256 buyAmount = normalisedSellAmount * _buyTokenExchangeRate / EXCHANGE_RATE_PRECISION;

            // CHECKS
            if(buyAmount == 0) revert SellAmountTooSmall();
            if(buyAmount > _buyTokenBalance) revert SellAmountTooBig();

            // EFFECTS
            buyTokenBalances[_buyTokenAddress] -= buyAmount;

            // INTERACTIONS
            ERC20(_buyTokenAddress).transfer(msg.sender , buyAmount);

            emit Sell(msg.sender, _buyTokenAddress, buyAmount);
        }
    }

    /// @notice deposits an amount of buyToken from the sender to this contract and makes them available for buying
    /// @dev increments buyTokenBalance
    /// @param tokenAddress address of buy token
    /// @param depositAmount amount of tokens to deposit
    function depositBuyToken(address tokenAddress, uint256 depositAmount) public onlyAdmin {
        if(tokenAddress == address(0)) revert InvalidBuyToken();
        if(buyTokenExchangeRates[tokenAddress] == 0) revert InvalidBuyToken();
        if(tokenAddress == sellToken) revert InvalidBuyToken();

        buyTokenBalances[tokenAddress] += depositAmount;
        ERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            depositAmount
        );

        emit Deposit(tokenAddress, depositAmount);
    }

    /// @notice sets a new exchange rate for the given token
    /// @param newExchangeRate new exchange rate
    function setExchangeRate(address tokenAddress, uint256 newExchangeRate) public onlyAdmin {
        if(tokenAddress == address(0)) revert InvalidBuyToken();
        if(buyTokenExchangeRates[tokenAddress] == 0) revert InvalidBuyToken();
        if(newExchangeRate == 0) revert InvalidExchangeRate();

        buyTokenExchangeRates[tokenAddress] = newExchangeRate;
        emit ExchangeRateSet(tokenAddress, newExchangeRate);
    }

    /// @notice sets a new merkle tree root
    /// @param newMerkleRoot new merkle tree root
    function setMerkleRoot(bytes32 newMerkleRoot) public onlyAdmin {
        merkleRoot = newMerkleRoot;
        emit MerkleRootSet(newMerkleRoot);
    }

    /// @notice sets a new admin address
    /// @param newAdminAddress new admin address
    function setAdminAddress(address newAdminAddress) public onlyAdmin {
        adminAddress = newAdminAddress;
        emit AdminSet(newAdminAddress);
    }

    /// @notice transfers any sellToken in excess of totalSellTokensSold to the admin address
    function recoverSellToken() public onlyAdmin nonReentrant {
        uint256 tokenBalance = ERC20(sellToken).balanceOf(address(this));

        // treat tokens sold as burnt, this means they are unrecoverable from this contract
        // this imitates burning sell tokens that implement NonBurnable and cannot actually be burnt
        if(totalSellTokensSold >= tokenBalance) revert NoTokensToRecover();

        ERC20(sellToken).transfer(
            adminAddress,
            tokenBalance - totalSellTokensSold
        );
    }

    /// @notice transfers full buyToken balance to the admin address
    /// @dev resets buyTokenBalance for the given token to 0
    function recoverBuyToken(address tokenAddress) public onlyAdmin nonReentrant {
        if(tokenAddress == address(0)) revert InvalidBuyToken();
        if(tokenAddress == sellToken) revert CannotRecoverSellToken();

        uint256 recoverableAmount = ERC20(tokenAddress).balanceOf(address(this));

        if(recoverableAmount == 0) revert NoTokensToRecover();

        buyTokenBalances[tokenAddress] = 0;
        ERC20(tokenAddress).transfer(adminAddress, recoverableAmount);
    }

    /// @notice transfers token balance to admin address if the token is not a buyToken or the sellToken
    /// @param tokenAddress address of erc20 token to recover
    function recoverERC20(address tokenAddress) public onlyAdmin nonReentrant {
        if(tokenAddress == sellToken) revert CannotRecoverSellToken();
        if(buyTokenExchangeRates[tokenAddress] > 0) revert CannotRecoverBuyToken();

        uint256 tokenBalance = ERC20(tokenAddress).balanceOf(address(this));
        if(tokenBalance == 0) revert NoTokensToRecover();

        ERC20(tokenAddress).transfer(adminAddress, tokenBalance);
    }

    /// @notice prevents ETH being sent directly to this contract
    fallback() external {
        // ETH received with no msg.data
        revert FallbackNotPayable();
    }

    /// @notice prevents ETH being sent directly to this contract
    receive() external payable {
        // ETH received with msg.data that does not match any contract function
        revert ReceiveNotPayable();
    }
}

