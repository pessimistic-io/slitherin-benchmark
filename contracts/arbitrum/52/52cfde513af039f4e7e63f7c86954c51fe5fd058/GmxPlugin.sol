// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

// Libraries
import "./Ownable.sol";
import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./ReentrancyGuardUpgradeable.sol";


import "./IPlugin.sol";
import "./IExchangeRouter.sol";
import "./IDataStore.sol";
import "./IReader.sol";
import "./IMarket.sol";

import "./TokenPriceConsumer.sol";

contract GmxPlugin is Ownable, IPlugin, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // Struct defining configuration parameters for the router.
    struct RouterConfig {
        address exchangeRouter;   // Address of the exchange router contract.
        address router;           // Address of the router contract.
        address depositVault;     // Address of the deposit vault contract.
        address withdrawVault;    // Address of the withdraw vault contract.
        address orderVault;       // Address of the order vault contract.
        address reader;           // Address of the reader contract.
    }

    // Struct defining configuration parameters for a pool.
    struct PoolConfig {
        uint256 poolId;           // Unique identifier for the pool.
        address indexToken;       // Address of the index token associated with the pool.
        address longToken;        // Address of the long token associated with the pool.
        address shortToken;       // Address of the short token associated with the pool.
        address marketToken;      // Address of the market token associated with the pool.
    }

    // Struct defining parameters related to Gmx (Governance Mining) functionality.
    struct GmxParams {
        address uiFeeReceiver;    // Address to receive UI fees.
        address callbackContract;  // Address of the callback contract for Gmx interactions.
        uint256 callbackGasLimit; // Gas limit for Gmx callback functions.
        uint256 executionFee;     // Execution fee for Gmx interactions.
        bool shouldUnwrapNativeToken; // Flag indicating whether native tokens should be unwrapped during Gmx interactions.
    }

    /* ========== CONSTANTS ========== */
    // Constant defining the decimal precision for asset values.
    uint256 public constant ASSET_DECIMALS = 36;

    // Constant defining the decimal precision for market token prices.
    uint256 public constant MARKET_TOKEN_PRICE_DECIMALS = 30;

    /* ========== STATE VARIABLES ========== */
    // Address of the master contract, controlling the overall functionality.
    address public master;

    // Address of the local vault associated with the smart contract.
    address public localVault;

    // Address of the treasury where funds are managed.
    address payable public treasury;

    // Configuration parameters for the router, specifying key contracts and components.
    RouterConfig public routerConfig;

    // Parameters related to Governance Mining (Gmx) functionality.
    GmxParams public gmxParams;

    // Array storing configuration details for different pools.
    PoolConfig[] public pools;

    // Mapping to track the existence of pools based on their unique identifiers.
    mapping(uint256 => bool) public poolExistsMap;

    // Array containing unique tokens associated with the contract.
    address[] public uniqueTokens;

    // Address of the token price consumer contract used for obtaining token prices.
    address public tokenPriceConsumer;

    /* ========== EVENTS ========== */
    event SetMaster(address master);
    event PoolAdded(uint256 poolId);
    event PoolRemoved(uint256 poolId);
    event SetTreasury(address payable treasury);

    /* ========== MODIFIERS ========== */

    // Modifier allowing only the local vault to execute the function.
    modifier onlyVault() {
        require(msg.sender == localVault, "Invalid caller");
        _;
    }

    // Modifier allowing only the master contract to execute the function.
    modifier onlyMaster() {
        require(msg.sender == master, "Invalid caller");
        _;
    }


    /* ========== CONFIGURATION ========== */

    // Constructor initializing the GMX contract with the address of the local vault.
    constructor(address _localVault) {
        // Ensure the provided local vault address is valid.
        require(_localVault != address(0), "GMX: Invalid Address");
        // Set the localVault address.
        localVault = _localVault;
    }

    // Function allowing the owner to set the address of the master contract.
    function setMaster(address _master) public onlyOwner {
        // Ensure the provided master address is valid.
        require(_master != address(0), "GMX: Invalid Address");
        // Set the master address.
        master = _master;
        // Emit an event signaling the master address update.
        emit SetMaster(_master);
    }

    // Function allowing the owner to set the treasury address.
    function setTreasury(address payable _treasury) public onlyOwner {
        // Ensure the provided treasury address is valid.
        require(_treasury != address(0), "Vault: Invalid address");
        // Set the treasury address.
        treasury = _treasury;
        // Emit an event signaling the treasury address update.
        emit SetTreasury(_treasury);
    }


    // Function allowing the owner to set the router configuration parameters.
    function setRouterConfig(
        address _exchangeRouter,
        address _router,
        address _depositVault,
        address _withdrawVault,
        address _orderVault,
        address _reader
    ) external onlyOwner {
        // Ensure all provided addresses are valid.
        require(
            _exchangeRouter != address(0) && 
            _router != address(0) && 
            _depositVault != address(0) && 
            _withdrawVault != address(0) && 
            _orderVault != address(0) && 
            _reader != address(0),
            "GMX: Invalid Address"
        );

        // Set the router configuration with the provided addresses.
        routerConfig = RouterConfig({
            exchangeRouter: _exchangeRouter,
            router: _router,
            depositVault: _depositVault,
            withdrawVault: _withdrawVault,
            orderVault: _orderVault,
            reader: _reader
        });
    }

    // Function allowing the owner to set Governance Mining (Gmx) parameters.
    function setGmxParams(
        address _uiFeeReceiver,
        address _callbackContract,
        uint256 _callbackGasLimit,
        uint256 _executionFee,
        bool _shouldUnwrapNativeToken
    ) public onlyOwner {
        // Set the Gmx parameters with the provided values.
        gmxParams = GmxParams({
            uiFeeReceiver: _uiFeeReceiver,
            callbackContract: _callbackContract,
            callbackGasLimit: _callbackGasLimit,
            executionFee: _executionFee,
            shouldUnwrapNativeToken: _shouldUnwrapNativeToken
        });
    }

    // Function allowing the owner to set the token price consumer contract address.
    function setTokenPriceConsumer(address _tokenPriceConsumer) public onlyOwner {
        // Ensure the provided token price consumer address is valid.
        require(_tokenPriceConsumer != address(0), "GMX: Invalid Address");
        
        // Set the token price consumer contract address.
        tokenPriceConsumer = _tokenPriceConsumer;
    }


    // Function allowing the owner to add a new pool with specified configuration.
    function addPool(
        uint256 _poolId,
        address _indexToken,
        address _longToken,
        address _shortToken,
        address _marketToken
    ) external onlyOwner {
        // Ensure the pool with the given poolId does not already exist.
        require(_poolId != 0, "GMX: Invalid Pool Id");
        require(!poolExistsMap[_poolId], "GMX: Pool with this poolId already exists");

        // Create a new pool configuration and add it to the array.
        PoolConfig memory newPool = PoolConfig(_poolId, _indexToken, _longToken, _shortToken, _marketToken);
        pools.push(newPool);

        // Mark the pool as existing.
        poolExistsMap[_poolId] = true;

        // Add unique tokens to the list if not already present.
        if (!isTokenAdded(_longToken)) {
            uniqueTokens.push(_longToken);
        }

        if (!isTokenAdded(_shortToken)) {
            uniqueTokens.push(_shortToken);
        }

        // Emit an event indicating the addition of a new pool.
        emit PoolAdded(_poolId);
    }

    // Function allowing the owner to remove an existing pool.
    function removePool(uint256 _poolId) external onlyOwner {
        // Ensure the pool with the given poolId exists.
        require(poolExistsMap[_poolId], "GMX: Pool with this poolId does not exist");

        // Find the index of the pool in the array.
        uint256 indexToRemove = getPoolIndexById(_poolId);

        // Swap the pool to remove with the last pool in the array.
        // This avoids leaving gaps in the array.
        uint256 lastIndex = pools.length - 1;
        if (indexToRemove != lastIndex) {
            pools[indexToRemove] = pools[lastIndex];
        }

        // Remove the last pool (which now contains the removed pool's data).
        pools.pop();

        // Mark the pool as no longer existing.
        delete poolExistsMap[_poolId];

        // Update the list of unique tokens.
        updateUniqueTokens();

        // Emit an event indicating the removal of an existing pool.
        emit PoolRemoved(_poolId);
    }


    /* ========== PUBLIC FUNCTIONS ========== */
    // Function allowing the vault to execute different actions based on the specified action type.
    function execute(ActionType _actionType, bytes calldata _payload) external payable onlyVault nonReentrant {
        // Determine the action type and execute the corresponding logic.
        if (_actionType == ActionType.Stake) {
            // Execute stake action.
            stake(_payload);
        } else if (_actionType == ActionType.Unstake) {
            // Execute unstake action.
            unstake(_payload);
        } else if (_actionType == ActionType.SwapTokens) {
            // Execute token swap action (create order).
            createOrder(_payload);
        }
    }

    /* ========== VIEW FUNCTIONS ========== */
    // Function to calculate the total liquidity (totalAsset) of the vault, considering balances in unique tokens and pools.
    function getTotalLiquidity() public view returns (uint256 totalAsset) {
        // Iterate over uniqueTokens and calculate totalAsset based on token balances.
        for (uint256 i = 0; i < uniqueTokens.length; ++i) {
            address tokenAddress = uniqueTokens[i];
            uint256 tokenBalance = IERC20(tokenAddress).balanceOf(address(this));
            totalAsset += calculateTokenValueInUsd(tokenAddress, tokenBalance);
        }

        // Iterate over pools and calculate totalAsset based on market token balances and prices.
        for (uint256 i = 0; i < pools.length; ++i) {
            address marketTokenAddress = pools[i].marketToken;
            uint256 marketTokenBalance = IERC20(marketTokenAddress).balanceOf(address(this));
            uint256 marketTokenPrice = uint256(getMarketTokenPrice(pools[i].poolId, true));
            uint256 amount = marketTokenBalance * marketTokenPrice;

            // Use IERC20Metadata only once to get decimals.
            uint256 decimals = IERC20Metadata(marketTokenAddress).decimals() + MARKET_TOKEN_PRICE_DECIMALS;

            // Refactor decimalsDiff calculation to improve readability.
            uint256 decimalsDiff = abs(int256(decimals) - int256(ASSET_DECIMALS));
            uint256 adjustedAmount;

            // Adjust amount based on decimalsDiff.
            if (decimals >= ASSET_DECIMALS) {
                adjustedAmount = amount / 10**decimalsDiff;
            } else {
                adjustedAmount = amount * 10**decimalsDiff;
            }

            // Accumulate adjustedAmount to totalAsset.
            totalAsset += adjustedAmount;
        }
    }

    // Function to calculate the USD value of a given token amount based on its price and decimals.
    function calculateTokenValueInUsd(address _tokenAddress, uint256 _tokenAmount) public view returns (uint256) {
        uint256 tokenDecimals = IERC20Metadata(_tokenAddress).decimals();
        uint256 priceConsumerDecimals = TokenPriceConsumer(tokenPriceConsumer).decimals(_tokenAddress);

        // Get the token price from the TokenPriceConsumer.
        uint256 tokenPrice = TokenPriceConsumer(tokenPriceConsumer).getTokenPrice(_tokenAddress);

        uint256 decimalsDiff;

        // Adjust the token value based on the difference in decimals.
        if (tokenDecimals + priceConsumerDecimals >= ASSET_DECIMALS) {
            decimalsDiff = tokenDecimals + priceConsumerDecimals - ASSET_DECIMALS;
            return (_tokenAmount * tokenPrice) / (10 ** decimalsDiff);
        } else {
            decimalsDiff = ASSET_DECIMALS - tokenDecimals - priceConsumerDecimals;
            return (_tokenAmount * tokenPrice * (10 ** decimalsDiff));
        }
    }


    // Function to retrieve the total number of pools in the vault.
    function getPoolNumber() public view returns(uint256) {
        return pools.length;
    }

    // Function to retrieve the array of unique tokens stored in the vault.
    function getUniqueTokens() public view returns (address[] memory) {
        return uniqueTokens;
    }

    // Function to retrieve the length of the array of unique tokens.
    function getUniqueTokenLength() public view returns(uint256) {
        return uniqueTokens.length;
    }

    // Function to retrieve the array of pool configurations stored in the vault.
    function getPools() public view returns(PoolConfig[] memory) {
        return pools;
    }

    // Function to retrieve the length of the array of pool configurations.
    function getPoolLength() public view returns (uint256) {
        return pools.length;
    }

    // Function to check if a token is present in the uniqueTokens array.
    function isTokenAdded(address _token) public view returns(bool) {
        for(uint256 i; i < uniqueTokens.length; ++i) {
            if(uniqueTokens[i] == _token) return true;
        }
        return false;
    }

    // Internal function to check if a token exists in the longToken or shortToken of any pool configurations.
    function tokenExistsInList(address _token) internal view returns (bool) {
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i].longToken == _token || pools[i].shortToken == _token) {
                return true;
            }
        }
        return false;
    }


    // Internal function to get the index of a pool in the array by poolId
    function getPoolIndexById(uint256 _poolId) public view returns (uint256 poolIndex) {
        for (uint256 index = 0; index < pools.length; index++) {
            if (pools[index].poolId == _poolId) {
                // Pool found, return its index
                poolIndex = index;
                return poolIndex;
            }
        }
        // If the pool is not found, revert with an error message
        revert("GMX: Pool not found");
    }

    // Updates the 'uniqueTokens' array by removing tokens that no longer exist.
    function updateUniqueTokens() internal {
        for (uint256 i = uniqueTokens.length; i > 0; i--) {
            if (!tokenExistsInList(uniqueTokens[i - 1])) {
                // Remove the token from uniqueTokens
                uniqueTokens[i - 1] = uniqueTokens[uniqueTokens.length - 1];
                uniqueTokens.pop();
            }
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    // Internal function to stake tokens into a specified pool.
    // The payload includes the pool ID, an array of two tokens (long and short), and corresponding amounts.
    // Validates the existence of the pool, array lengths, correct pool tokens, and non-zero token amounts.
    // Transfers tokens from localVault to the contract and executes buyGMToken function.
    function stake(bytes calldata _payload) internal {
        // Decode payload
        (uint8 _poolId, address[] memory _tokens, uint256[] memory _amounts) = abi.decode(_payload, (uint8, address[], uint256[]));

        // Validate pool existence
        require(poolExistsMap[_poolId], "GMX: Pool with this poolId does not exist");

        // Validate array lengths
        require(_tokens.length == 2 && _amounts.length == 2, "GMX: Array length must be 2");

        // Get pool index and pool configuration
        uint256 index = getPoolIndexById(_poolId);
        PoolConfig memory pool = pools[index];

        // Validate tokens
        require(pool.longToken == _tokens[0] && pool.shortToken == _tokens[1], "GMX: Invalid Pool tokens");

        // Validate token amounts
        require(_amounts[0] != 0 || _amounts[1] != 0, "GMX: Invalid token amount");

        // Transfer tokens from localVault to contract if amounts are positive
        if (_amounts[0] > 0) {
            IERC20(pool.longToken).safeTransferFrom(localVault, address(this), _amounts[0]);
        }

        if (_amounts[1] > 0) {
            IERC20(pool.shortToken).safeTransferFrom(localVault, address(this), _amounts[1]);
        }

        // Execute buyGMToken function
        buyGMToken(_poolId, _amounts[0], _amounts[1]);
    }


    // Internal function to unstake GM tokens from a specified pool.
    // The payload includes the pool ID and the market amount to sell.
    // Decodes the payload and performs the sell operation using sellGMToken function.
    function unstake(bytes calldata _payload) internal {
        // Decode payload
        (uint8 _poolId, uint256 marketAmount) = abi.decode(_payload, (uint8, uint256));

        // Perform sell operation
        sellGMToken(_poolId, marketAmount);
    }

    // Internal function to create a GM token order using provided order parameters.
    // The payload includes order parameters in the CreateOrderParams structure.
    // Decodes the payload and executes createGMOrder function.
    function createOrder(bytes calldata _payload) internal {
        // Decode payload
        IExchangeRouter.CreateOrderParams memory orderParams = abi.decode(_payload, (IExchangeRouter.CreateOrderParams));

        // Execute createGMOrder function
        createGMOrder(orderParams);
    }


    /* ========== GMX FUNCTIONS ========== */
    // Internal function to buy GM tokens in a specified pool.
    // Handles the approval of token transfers, prepares swap paths, and executes multicall to deposit assets and create GM tokens.
    function buyGMToken(uint8 _poolId, uint256 _longTokenAmount, uint256 _shortTokenAmount) internal {
        // Retrieve pool configuration
        PoolConfig memory pool = pools[getPoolIndexById(_poolId)];
        IExchangeRouter _exchangeRouter = IExchangeRouter(routerConfig.exchangeRouter);

        // Prepare swap paths and other variables
        address longToken = pool.longToken;
        address shortToken = pool.shortToken;
        address marketAddress = pool.marketToken;
        address[] memory longTokenSwapPath;
        address[] memory shortTokenSwapPath;
        uint256 executionFee = gmxParams.executionFee;

        // Prepare CreateDepositParams
        IExchangeRouter.CreateDepositParams memory params = IExchangeRouter.CreateDepositParams(
            address(this),                     // receiver
            gmxParams.callbackContract,        // callbackContract
            gmxParams.uiFeeReceiver,           // uiFeeReceiver
            marketAddress,
            longToken,
            shortToken,
            longTokenSwapPath,
            shortTokenSwapPath,
            0,                                 // minMarketTokens
            gmxParams.shouldUnwrapNativeToken, // shouldUnwrapNativeToken
            executionFee,
            gmxParams.callbackGasLimit         // callbackGasLimit
        );

        // Approve token transfers if amounts are greater than 0
        if (_longTokenAmount > 0) {
            IERC20(longToken).approve(routerConfig.router, _longTokenAmount);
        }

        if (_shortTokenAmount > 0) {
            IERC20(shortToken).approve(routerConfig.router, _shortTokenAmount);
        }

        // Prepare multicall arguments
        bytes[] memory multicallArgs = new bytes[](4);

        // Encode external contract calls for multicall
        multicallArgs[0] = abi.encodeWithSignature("sendWnt(address,uint256)", routerConfig.depositVault, executionFee);
        multicallArgs[1] = abi.encodeWithSignature("sendTokens(address,address,uint256)", longToken, routerConfig.depositVault, _longTokenAmount);
        multicallArgs[2] = abi.encodeWithSignature("sendTokens(address,address,uint256)", shortToken, routerConfig.depositVault, _shortTokenAmount);
        multicallArgs[3] = abi.encodeWithSignature("createDeposit((address,address,address,address,address,address,address[],address[],uint256,bool,uint256,uint256))", params);

        // Execute multicall with optional value (executionFee)
        _exchangeRouter.multicall{value: executionFee}(multicallArgs);
    }


    function sellGMToken(uint8 _poolId, uint256 marketAmount) internal {
        // Retrieve pool configuration
        PoolConfig memory pool = pools[getPoolIndexById(_poolId)];

        // Cast exchangeRouter to IExchangeRouter
        IExchangeRouter _exchangeRouter = IExchangeRouter(routerConfig.exchangeRouter);

        // Define swap paths
        address[] memory longTokenSwapPath;
        address[] memory shortTokenSwapPath;
        uint256 executionFee = gmxParams.executionFee;

        // Extract market address from the pool configuration
        address marketAddress = pool.marketToken;

        // Check if the contract has sufficient market token balance
        uint256 balance = IERC20(marketAddress).balanceOf(address(this));
        require(balance >= marketAmount && marketAmount > 0, "GMX: Insufficient market token balance");

        // Create parameters for the external contract call
        IExchangeRouter.CreateWithdrawalParams memory params = IExchangeRouter.CreateWithdrawalParams(
            localVault,                        // receiver
            gmxParams.callbackContract,        // callbackContract
            gmxParams.uiFeeReceiver,           // uiFeeReceiver
            marketAddress,
            longTokenSwapPath,
            shortTokenSwapPath,
            0,                                 // minLongTokens
            0,                                 // minShortTokens
            gmxParams.shouldUnwrapNativeToken, // shouldUnwrapNativeToken
            executionFee,
            gmxParams.callbackGasLimit         // callbackGasLimit
        );

        // Approve market token transfer
        IERC20(marketAddress).approve(routerConfig.router, marketAmount);

        // Initialize an array to store multicall arguments
        bytes[] memory multicallArgs = new bytes[](3);

        // Encode external contract calls for multicall
        multicallArgs[0] = abi.encodeWithSignature("sendWnt(address,uint256)", routerConfig.withdrawVault, executionFee);
        multicallArgs[1] = abi.encodeWithSignature("sendTokens(address,address,uint256)", marketAddress, routerConfig.withdrawVault, marketAmount);
        multicallArgs[2] = abi.encodeWithSignature("createWithdrawal((address,address,address,address,address[],address[],uint256,uint256,bool,uint256,uint256))", params);

        // Execute multicall with optional value (executionFee)
        _exchangeRouter.multicall{value: executionFee}(multicallArgs);
    }


    function createGMOrder(IExchangeRouter.CreateOrderParams memory _params) internal {
        require(_params.addresses.receiver == localVault, "Invalid receiver");
        
        // Extract values from _params to improve readability
        address initialCollateralToken = _params.addresses.initialCollateralToken;
        uint256 initialCollateralDeltaAmount = _params.numbers.initialCollateralDeltaAmount;
        uint256 executionFee = _params.numbers.executionFee;

        // Transfer initialCollateralToken from localVault to contract
        IERC20(initialCollateralToken).transferFrom(localVault, address(this), initialCollateralDeltaAmount);

        // Approve initialCollateralToken transfer
        IERC20(initialCollateralToken).approve(routerConfig.router, initialCollateralDeltaAmount);

        // Cast exchangeRouter to IExchangeRouter
        IExchangeRouter _exchangeRouter = IExchangeRouter(routerConfig.exchangeRouter);

        // Send execution fee to orderVault
        _exchangeRouter.sendWnt{value: executionFee}(routerConfig.orderVault, executionFee);

        // Transfer initialCollateralToken to orderVault
        _exchangeRouter.sendTokens(initialCollateralToken, routerConfig.orderVault, initialCollateralDeltaAmount);

        // Create the order using the external exchange router
        _exchangeRouter.createOrder(_params);
    }


   function getMarketTokenPrice(uint256 _poolId, bool _maximize) public view returns (int256) {
        require(poolExistsMap[_poolId], "GMX: Pool with this poolId does not exist");
        
        // Retrieve pool configuration
        PoolConfig memory _pool = pools[getPoolIndexById(_poolId)];

        // Cast exchangeRouter to IExchangeRouter for interacting with the external contract
        IExchangeRouter exchangeRouterInstance = IExchangeRouter(routerConfig.exchangeRouter);

        // Retrieve dataStore from the exchangeRouter
        IDataStore dataStore = exchangeRouterInstance.dataStore();

        // Define market properties for the external contract call
        IMarket.Props memory marketProps = IMarket.Props(
            _pool.marketToken,
            _pool.indexToken,
            _pool.longToken,
            _pool.shortToken
        );

        // Fetch token prices for indexToken, longToken, and shortToken
        IPrice.Props memory indexTokenPrice = getTokenPriceInfo(_pool.indexToken);
        IPrice.Props memory longTokenPrice = getTokenPriceInfo(_pool.longToken);
        IPrice.Props memory shortTokenPrice = getTokenPriceInfo(_pool.shortToken);

        // Define additional parameters for the external contract call
        bytes32 pnlFactorType = keccak256(abi.encodePacked("MAX_PNL_FACTOR_FOR_TRADERS"));
        bool maximize = _maximize;

        // Call the external contract to get the market token price
        (int256 marketTokenPrice, ) = IReader(routerConfig.reader).getMarketTokenPrice(
            dataStore,
            marketProps,
            indexTokenPrice,
            longTokenPrice,
            shortTokenPrice,
            pnlFactorType,
            maximize
        );

        // Return the calculated market token price
        return marketTokenPrice;
    }

    // Retrieves token price information, adjusting for decimals.
    function getTokenPriceInfo(address token) public view returns (IPrice.Props memory) {
        // Create an instance of TokenPriceConsumer for fetching token prices
        TokenPriceConsumer priceConsumer = TokenPriceConsumer(tokenPriceConsumer);

        uint256 tokenDecimal = IERC20Metadata(token).decimals();
        IPrice.Props memory tokenPrice = IPrice.Props(
            convertDecimals(priceConsumer.getTokenPrice(token), priceConsumer.decimals(token), MARKET_TOKEN_PRICE_DECIMALS - tokenDecimal),
            convertDecimals(priceConsumer.getTokenPrice(token), priceConsumer.decimals(token), MARKET_TOKEN_PRICE_DECIMALS - tokenDecimal)
        );
        return tokenPrice;
    }

    // Retrieves the long and short tokens allowed in a pool.
    function getAllowedTokens(uint256 _poolId) public view returns (address[] memory) {
        address[] memory emptyArray;
        if (!poolExistsMap[_poolId]) {
            return emptyArray;
        }
        address[] memory tokens = new address[](2);
        uint256 index = getPoolIndexById(_poolId);
        PoolConfig memory pool = pools[index];

        tokens[0] = pool.longToken;
        tokens[1] = pool.shortToken;
        return tokens;
    }

    // Converts an amount from one decimal precision to another.
    function convertDecimals(uint256 _amount, uint256 _from, uint256 _to) public pure returns (uint256) {
        if(_from >= _to) return _amount / 10 ** (_from - _to);
        else return _amount * 10 ** (_to - _from);
    }

    // Helper function to calculate absolute value of an int256
    function abs(int256 x) internal pure returns (uint256) {
        return x < 0 ? uint256(-x) : uint256(x);
    }

    receive() external payable {}
    fallback() external payable {}

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    function withdrawFee(uint256 _amount) public onlyOwner {
        // get the amount of Ether stored in this contract
        uint amount = address(this).balance;
        require(amount >= _amount, "Vault: Invalid withdraw amount.");
                                                  
        require(treasury != address(0), "Vault: Invalid treasury");
        (bool success, ) = treasury.call{value: _amount}("");
        require(success, "Vault: Failed to send Ether");
    }
}
