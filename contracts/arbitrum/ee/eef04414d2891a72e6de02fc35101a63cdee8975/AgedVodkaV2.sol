// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity ^0.8.19;

import "./OwnableUpgradeable.sol";
import "./ERC4626Upgradeable.sol";
import "./MathUpgradeable.sol";

import "./IExchangeRouter.sol";
import "./EventUtils.sol";

import "./console.sol";

interface IRoleStore {
    function hasRole(
        address account,
        bytes32 roleKey
    ) external view returns (bool);
}

library Role {
    /**
     * @dev The ROLE_ADMIN role.
     */
    bytes32 public constant ROLE_ADMIN = keccak256(abi.encode("ROLE_ADMIN"));

    /**
     * @dev The TIMELOCK_ADMIN role.
     */
    bytes32 public constant TIMELOCK_ADMIN =
        keccak256(abi.encode("TIMELOCK_ADMIN"));

    /**
     * @dev The TIMELOCK_MULTISIG role.
     */
    bytes32 public constant TIMELOCK_MULTISIG =
        keccak256(abi.encode("TIMELOCK_MULTISIG"));

    /**
     * @dev The CONFIG_KEEPER role.
     */
    bytes32 public constant CONFIG_KEEPER =
        keccak256(abi.encode("CONFIG_KEEPER"));

    /**
     * @dev The CONTROLLER role.
     */
    bytes32 public constant CONTROLLER = keccak256(abi.encode("CONTROLLER"));

    /**
     * @dev The ROUTER_PLUGIN role.
     */
    bytes32 public constant ROUTER_PLUGIN =
        keccak256(abi.encode("ROUTER_PLUGIN"));

    /**
     * @dev The MARKET_KEEPER role.
     */
    bytes32 public constant MARKET_KEEPER =
        keccak256(abi.encode("MARKET_KEEPER"));

    /**
     * @dev The FEE_KEEPER role.
     */
    bytes32 public constant FEE_KEEPER = keccak256(abi.encode("FEE_KEEPER"));

    /**
     * @dev The ORDER_KEEPER role.
     */
    bytes32 public constant ORDER_KEEPER =
        keccak256(abi.encode("ORDER_KEEPER"));

    /**
     * @dev The FROZEN_ORDER_KEEPER role.
     */
    bytes32 public constant FROZEN_ORDER_KEEPER =
        keccak256(abi.encode("FROZEN_ORDER_KEEPER"));

    /**
     * @dev The PRICING_KEEPER role.
     */
    bytes32 public constant PRICING_KEEPER =
        keccak256(abi.encode("PRICING_KEEPER"));
    /**
     * @dev The LIQUIDATION_KEEPER role.
     */
    bytes32 public constant LIQUIDATION_KEEPER =
        keccak256(abi.encode("LIQUIDATION_KEEPER"));
    /**
     * @dev The ADL_KEEPER role.
     */
    bytes32 public constant ADL_KEEPER = keccak256(abi.encode("ADL_KEEPER"));
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint deadline;
        uint amountIn;
        uint amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps amountIn of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as ExactInputSingleParams in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint deadline;
        uint amountIn;
        uint amountOutMinimum;
    }

    /// @notice Swaps amountIn of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as ExactInputParams in calldata
    /// @return amountOut The amount of the received token
    function exactInput(
        ExactInputParams calldata params
    ) external payable returns (uint amountOut);
}


contract AgedVodkaV2 is ERC4626Upgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    struct Props {
        Addresses addresses;
        Numbers numbers;
        Flags flags;
    }

    struct Addresses {
        address account;
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialLongToken;
        address initialShortToken;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
    }

    struct Numbers {
        uint256 initialLongTokenAmount;
        uint256 initialShortTokenAmount;
        uint256 minMarketTokens;
        uint256 updatedAtBlock;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }

    struct Flags {
        bool shouldUnwrapNativeToken;
    }

    address public feeReceiver;
    uint256 public mFee;
    uint256 public gmxOpenCloseFees;

    uint256 public constant DENOMINATOR = 1000;
    uint256 public AgedVodka_DEFAULT_PRICE;
    uint256 public totalGMToken;
    uint256 public currentCompoundRequest;
    bytes32[] public depositKeyHistory;

    address public GMToken;
    address public WETH;
    address public USDC;
    address public ARB;
    address public LongToken;
    address public uniRouter;
    address public keeper;
    uint256 public minSwapThreshold;

    struct GMXAddresses {
        address depositHandler;
        address withdrawalHandler;
        address depositVault;
        address withdrawVault;
        address gmxRouter;
        address exchangeRouter;
        address marketToken;
        address roleStore;
    }

    GMXAddresses public gmxAddresses;

    mapping(address => bool) public allowedSenders;
    mapping(bytes32 => uint256) public depositKeyToAmount;
    mapping(uint256 => bool) public compoundRequestStatus;

    uint256[50] private __gaps;

    modifier noZeroValues(uint256 assetsOrShares) {
        require(assetsOrShares > 0, "VALUE_0");
        _;
    }

    modifier onlyKeeper() {
        require(_msgSender() == keeper, "Not keeper");
        _;
    }

    event ProtocolFeeChanged(address newFeeReceiver, uint256 newmFee);
    event MinThresholdChanged(uint256 minSwapThreshold);
    event SetAllowedSenders(address _sender, bool _allowed);
    event GMXAddressesChanged(
        address newDepositHandler,
        address newWithdrawalHandler,
        address newDepositVault,
        address newWithdrawVault,
        address newgmxRouter,
        address newExchangeRouter
    );
    event GMXOpenCloseFeeSet(uint256 indexed gmxOpenCloseFees);
    event UniRouterChanged(address indexed uniRouter);
    event DepositExecuted(
        bytes32 indexed key,
        uint256 receivedGMTokens,
        uint256 totalGMToken
    );
    event CompoundRequested(uint256 ARBBal, uint256 USDCBal, uint256 ethBal);
    event KeeperChanged(address indexed keeper);
    event GMTokensGifted(uint256 indexed amount);
    event Deposited(address user, uint256 indexed amount, uint256 indexed shares, uint256 timestamp);
    event Withdrawn(address user, uint256 indexed amount, uint256 indexed shares, uint256 timestamp);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
    * @notice Initialize the AgedVodkaV2 contract with specified tokens.
    * @param _gmToken Address of the GM token.
    * @param _longToken Address of the Long token.
    * @param _USDC Address of the USDC token.
    * @param _ARB Address of the ARB token.
    * @dev This function can only be called once due to the initializer modifier.
    */
    function initialize(
        address _gmToken,
        address _longToken,
        address _USDC,
        address _ARB
    ) external initializer {
        require(
            _gmToken != address(0) &&
                _longToken != address(0) &&
                _USDC != address(0) &&
                _ARB != address(0),
            "Invalid token address"
        );

        LongToken = _longToken;
        USDC = _USDC;
        ARB = _ARB;
        AgedVodka_DEFAULT_PRICE = 1e18;
        GMToken = _gmToken;

        __Ownable_init();
        __ERC4626_init(IERC20Upgradeable(_gmToken));
        __ERC20_init("AgedVodkaV2", "AVODKAV2");
    }

    /** ---------------- View functions --------------- */

    /**
    * @notice Get the balance of GM tokens in the contract.
    * @return uint256 representing the total GM token balance.
    * @dev View function that returns the total balance of GM tokens.
    */
    function balanceOfGMToken() public view returns (uint256) {
        return totalGMToken;
    }

    /**
    * @notice Calculate the current price of AgedVodka.
    * @return uint256 representing the current price of AgedVodka.
    * @dev Price is calculated based on total assets and total supply.
    */
    function getAgedVodkaPrice() public view returns (uint256) {
        uint256 currentPrice;
        if (totalAssets() == 0) {
            currentPrice = AgedVodka_DEFAULT_PRICE;
        } else {
            currentPrice = totalAssets().mulDiv(
                AgedVodka_DEFAULT_PRICE,
                totalSupply()
            );
        }
        return currentPrice;
    }

    /**
    * @notice Get the total assets of the contract.
    * @return uint256 representing the total assets.
    * @dev Overrides the totalAssets function from ERC4626Upgradeable.
    */
    function totalAssets() public view virtual override returns (uint256) {
        return totalGMToken;
    }

    /**
    * @notice Check if the conditions for compounding are met.
    * @return bool indicating if compound is ready, and the ARB balance.
    * @dev Returns a boolean and the ARB balance to decide on compounding.
    */
    function isCompoundReady() public view returns (bool,uint256) {
        uint256 ARBBal = IERC20Upgradeable(ARB).balanceOf(address(this));
        return (ARBBal >= minSwapThreshold,ARBBal);
    }

    /** ----------- Change onlyOwner functions ------------- */

    function setMinSwapThreshold(uint256 _minSwapThreshold) external onlyOwner {
        require(_minSwapThreshold > 0, "Invalid min swap threshold");
        minSwapThreshold = _minSwapThreshold;
        emit MinThresholdChanged(_minSwapThreshold);
    }

    function setKeeper(address _keeper) external onlyOwner {
        require(_keeper != address(0), "Invalid keeper");
        keeper = _keeper;
        emit KeeperChanged(_keeper);
    }

    function setUniRouter(address _uniRouter) external onlyOwner {
        require(_uniRouter != address(0), "Invalid uni router");
        uniRouter = _uniRouter;
        emit UniRouterChanged(_uniRouter);
    }

    function setAllowed(address _sender, bool _allowed) public onlyOwner {
        require(_sender != address(0), "Invalid sender");
        allowedSenders[_sender] = _allowed;
        emit SetAllowedSenders(_sender, _allowed);
    }

    function setProtocolFee(
        address _feeReceiver,
        uint256 _mFee
    ) external onlyOwner {
        require(_mFee <= DENOMINATOR, "Invalid mFee fees");
        require(_feeReceiver != address(0), "Invalid fee receiver");
        mFee = _mFee;
        feeReceiver = _feeReceiver;
        emit ProtocolFeeChanged(_feeReceiver, _mFee);
    }

    function setGmxOpenCloseFees(uint256 _gmxOpenCloseFees) external onlyOwner {
        require(_gmxOpenCloseFees <= 0.1 ether, "GMXOpenCloseFees > 0.1 eth");
        gmxOpenCloseFees = _gmxOpenCloseFees;
        emit GMXOpenCloseFeeSet(_gmxOpenCloseFees);
    }

    function setGmxContracts(
        address _depositHandler,
        address _withdrawalHandler,
        address _depositVault,
        address _gmxRouter,
        address _exchangeRouter,
        address _withdrawVault,
        address _marketToken,
        address _roleStore
    ) external onlyOwner {
        gmxAddresses.depositHandler = _depositHandler;
        gmxAddresses.withdrawalHandler = _withdrawalHandler;
        gmxAddresses.depositVault = _depositVault;
        gmxAddresses.gmxRouter = _gmxRouter;
        gmxAddresses.exchangeRouter = _exchangeRouter;
        gmxAddresses.withdrawVault = _withdrawVault;
        gmxAddresses.marketToken = _marketToken;
        gmxAddresses.roleStore = _roleStore;

        emit GMXAddressesChanged(
            _depositHandler,
            _withdrawalHandler,
            _depositVault,
            _withdrawVault,
            _gmxRouter,
            _exchangeRouter
        );
    }

    function withdrawToken(address _token) external onlyOwner {
        require(_token != GMToken, "Invalid token");
        uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(msg.sender, amount);
    }

    /** ----------- Keeper functions ------------- */

    /**
    * @notice Allows the keeper to gift GM tokens to the contract.
    * @param _amount The amount of GM tokens to gift.
    * @dev Only callable by the keeper. Increases the total GM token balance.
    */
    function giftGMTokens(uint256 _amount) external onlyKeeper {
        require(_amount > 0, "Invalid amount");
        IERC20Upgradeable(GMToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        totalGMToken += _amount;
        emit GMTokensGifted(_amount);
    }

    /**
    * @notice Request a compound operation.
    * @param _isCompound Indicates if the operation is a compound action.
    * @dev Only callable by the keeper. Requires a fee. Emits CompoundRequested event.
    */
    function requestCompound(bool _isCompound) external payable onlyKeeper {
        require(msg.value >= gmxOpenCloseFees, "Invalid gmx fee amount");
        
        (bool isCompound,uint256 ARBBal) = isCompoundReady();
        if (isCompound) {
            uint256 USDCBal = _swap(ARBBal);

            IERC20Upgradeable(USDC).safeIncreaseAllowance(
                gmxAddresses.gmxRouter,
                USDCBal
            );
            IExchangeRouter(gmxAddresses.exchangeRouter).sendTokens(
                USDC,
                gmxAddresses.depositVault,
                USDCBal
            );
            IExchangeRouter(gmxAddresses.exchangeRouter).sendWnt{value: msg.value}(
                gmxAddresses.depositVault,
                msg.value
            );

            IExchangeRouter.CreateDepositParams memory params = IExchangeRouter
                .CreateDepositParams({
                    receiver: address(this),
                    callbackContract: address(this),
                    uiFeeReceiver: msg.sender,
                    market: gmxAddresses.marketToken,
                    initialLongToken: LongToken,
                    initialShortToken: USDC,
                    longTokenSwapPath: new address[](0),
                    shortTokenSwapPath: new address[](0),
                    minMarketTokens: 0,
                    shouldUnwrapNativeToken: false,
                    executionFee: gmxOpenCloseFees,
                    callbackGasLimit: 2000000
                });

            IExchangeRouter(gmxAddresses.exchangeRouter).createDeposit(params);
            compoundRequestStatus[currentCompoundRequest] = _isCompound;

            emit CompoundRequested(ARBBal, USDCBal, msg.value);
        }
    }

    /**
    * @notice Handle actions after a deposit execution. Called from GMX Keeper.
    * @param key The deposit key.
    * @param deposits The deposit properties.
    * @param eventData The event log data.
    * @dev Validates the transaction and updates contract state. Emits DepositExecuted event.
    */
    function afterDepositExecution(
        bytes32 key,
        Props memory deposits,
        EventUtils.EventLogData memory eventData
    ) external {
        require(
            deposits.addresses.account == address(this),
            "Account isnt this address"
        );
        require(
            IRoleStore(gmxAddresses.roleStore).hasRole(
                msg.sender,
                Role.CONTROLLER
            ),
            "Not proper role"
        );

        uint256 receivedGMTokens = eventData.uintItems.items[0].value;
        depositKeyHistory.push(key);
        depositKeyToAmount[key] = receivedGMTokens;
        bool isCompound = compoundRequestStatus[currentCompoundRequest];
        if (isCompound) {
            totalGMToken += receivedGMTokens;
        } else {
            IERC20Upgradeable(GMToken).safeTransfer(keeper, receivedGMTokens);
        }

        currentCompoundRequest++;

        emit DepositExecuted(key, receivedGMTokens, totalGMToken);
    }

    /** ----------- Public functions ------------- */
    /**
    * @notice Allows a user to deposit GM assets in exchange for shares.
    * @param _assets The amount of assets to deposit.
    * @param _receiver The address receiving the shares.
    * @return uint256 representing the number of shares minted.
    * @dev Overrides ERC4626Upgradeable. Validates deposit and updates total GM token balance.
    */
    function deposit(
        uint256 _assets,
        address _receiver
    ) public override noZeroValues(_assets) returns (uint256) {
        require(
            _assets <= maxDeposit(msg.sender),
            "ERC4626: deposit more than max"
        );

        uint256 shares;
        if (totalSupply() == 0) {
            require(_assets > 1e18, "Not Enough Shares for first mint");
            uint256 SCALE = 10 ** decimals() / 10 ** 18;
            shares = (_assets - 1e18) * SCALE;
            _mint(address(this), 1e18 * SCALE);
        } else {
            shares = previewDeposit(_assets);
        }

        _deposit(_msgSender(), msg.sender, _assets, shares);
        totalGMToken += _assets;

        emit Deposited(msg.sender, _assets, shares, block.timestamp);
        return shares;
    }

    /**
    * @notice Allows a user to withdraw GM Tokens in exchange for burning shares.
    * @param _assets The amount of assets to withdraw.
    * @param _receiver The address receiving the assets.
    * @param _owner The owner of the shares being burnt.
    * @return uint256 representing the number of shares burnt.
    * @dev Overrides ERC4626Upgradeable. Validates withdrawal and updates total GM token balance.
    */
    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    ) public override noZeroValues(_assets) returns (uint256) {
        uint256 maxW = maxWithdraw(msg.sender);

        require(_assets <= maxW, "ERC4626: withdraw more than max");
        require(balanceOfGMToken() > _assets, "Insufficient balance in vault");

        uint256 shares = previewWithdraw(_assets);

        _withdraw(_msgSender(), msg.sender, msg.sender, _assets, shares);
        totalGMToken -= _assets;

        emit Withdrawn(msg.sender, _assets, shares, block.timestamp);
        return shares;
    }

    /**
    * @notice Transfer function to move tokens from one address to another. Needs to be an allowed sender.
    * @param to The address to transfer tokens to.
    * @param amount The amount of tokens to transfer.
    * @return bool indicating successful transfer.
    * @dev Checks for sender or receiver allowance. Overrides the transfer function from ERC20Upgradeable.
    */
    function transfer(
        address to,
        uint256 amount
    )
        public
        virtual
        override(ERC20Upgradeable, IERC20Upgradeable)
        returns (bool)
    {
        address ownerOf = _msgSender();
        require(
            allowedSenders[ownerOf] || allowedSenders[to],
            "ERC20: transfer not allowed"
        );
        _transfer(ownerOf, to, amount);
        return true;
    }

    /**
    * @notice Transfer tokens from one address to another based on allowance. Needs to be an allowed sender.
    * @param from The address to transfer tokens from.
    * @param to The address to transfer tokens to.
    * @param value The amount of tokens to be transferred.
    * @return bool indicating successful transfer.
    * @dev Checks for sender or receiver allowance. Overrides the transferFrom function from ERC20Upgradeable.
    */
    function transferFrom(
        address from,
        address to,
        uint256 value
    )
        public
        virtual
        override(ERC20Upgradeable, IERC20Upgradeable)
        returns (bool)
    {
        require(
            allowedSenders[from] || allowedSenders[to],
            "ERC20: transfer not allowed"
        );
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function mint(
        uint256 shares,
        address receiver
    ) public virtual override returns (uint256) {
        revert("Not used");
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        revert("Not used");
    }

    /** -- Internal functions -- */
    /**
    * @notice Internal function to perform a token swap.
    * @param _amount The amount of ARB tokens to swap.
    * @return uint256 representing the amount of USDC received.
    * @dev Swaps ARB for USDC using UniSwap Router.
    */
    function _swap(uint256 _amount) internal returns (uint256) {
        IERC20Upgradeable(ARB).safeIncreaseAllowance(uniRouter, _amount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: ARB,
                tokenOut: USDC,
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = ISwapRouter(uniRouter).exactInputSingle(params);

        return amountOut;
    }

    receive() external payable {
        require(msg.sender == gmxAddresses.depositVault || msg.sender == gmxAddresses.withdrawVault, "Not GMX");
        payable(keeper).transfer(address(this).balance);
    }
}

