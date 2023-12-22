// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Address.sol";
import "./IUniswapV2Router02.sol";
import "./IXToken.sol";
import "./IYToken.sol";
import "./IYTokenReserve.sol";
import "./IMasterOracle.sol";
import "./IWETH.sol";
import "./ISwapStrategy.sol";
import "./WethUtils.sol";

contract Pool is Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;
    using SafeERC20 for IWETH;
    using SafeERC20 for IXToken;
    using SafeERC20 for IYToken;

    struct UserInfo {
        uint256 xTokenBalance;
        uint256 yTokenBalance;
        uint256 ethBalance;
        uint256 lastAction;
    }

    /* ========== ADDRESSES ================ */

    IMasterOracle public oracle;
    IXToken public xToken;
    IYToken public yToken;
    IYTokenReserve public yTokenReserve;
    ISwapStrategy public swapStrategy;
    address public treasury;

    /* ========== STATE VARIABLES ========== */

    mapping(address => UserInfo) public userInfo;

    uint256 public unclaimedEth;
    uint256 public unclaimedXToken;
    uint256 public unclaimedYToken;

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e18;
    uint256 private constant COLLATERAL_RATIO_MAX = 1e6;
    uint256 private constant PRECISION = 1e6;

    // AccessControl state variables
    bool public mintPaused = false;
    bool public redeemPaused = false;

    // Collateral ratio
    uint256 public collateralRatio = 1e6;
    uint256 public lastRefreshCrTimestamp;
    uint256 public refreshCooldown = 3600; // = 1 hour
    uint256 public ratioStepUp = 2000; // = 0.002 or 0.2% -> ratioStep when CR increase
    uint256 public ratioStepDown = 1000; // = 0.001 or 0.1% -> ratioStep when CR decrease
    uint256 public priceTarget = 1e18; // = 1; 1 XToken pegged to the value of 1 ETH
    uint256 public priceBand = 5e15; // = 0.005; CR will be adjusted if XToken > 1.005 ETH or XToken < 0.995 ETH
    uint256 public minCollateralRatio = 1e6;
    uint256 public yTokenSlippage = 100000; // 10%
    bool public collateralRatioPaused = false;

    // fees
    uint256 public redemptionFee = 5000; // 6 decimals of precision, .5%
    uint256 public constant REDEMPTION_FEE_MAX = 9000; // 0.9%
    uint256 public mintingFee = 5000; // 6 decimals of precision, .5%
    uint256 public constant MINTING_FEE_MAX = 5000; // 0.5%

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _xToken,
        address _yToken,
        address _yTokenReserve
    ) {
        require(_xToken != address(0), "Pool::initialize: invalidAddress");
        require(_yToken != address(0), "Pool::initialize: invalidAddress");
        require(_yTokenReserve != address(0), "Pool::initialize: invalidAddress");
        xToken = IXToken(_xToken);
        xToken.setMinter(address(this));
        yToken = IYToken(_yToken);
        yTokenReserve = IYTokenReserve(_yTokenReserve);
        yTokenReserve.setPool(address(this));
    }

    /* ========== VIEWS ========== */

    function info()
        external
        view
        returns (
            uint256 _collateralRatio,
            uint256 _lastRefreshCrTimestamp,
            uint256 _mintingFee,
            uint256 _redemptionFee,
            bool _mintingPaused,
            bool _redemptionPaused,
            uint256 _collateralBalance
        )
    {
        _collateralRatio = collateralRatio;
        _lastRefreshCrTimestamp = lastRefreshCrTimestamp;
        _mintingFee = mintingFee;
        _redemptionFee = redemptionFee;
        _mintingPaused = mintPaused;
        _redemptionPaused = redeemPaused;
        _collateralBalance = usableCollateralBalance();
    }

    function usableCollateralBalance() public view returns (uint256) {
        uint256 _balance = WethUtils.weth.balanceOf(address(this));
        return _balance > unclaimedEth ? (_balance - unclaimedEth) : 0;
    }

    function getXSupplyAndUnclaimed() public view returns (uint256) {
        return ((xToken.totalSupply()) + (unclaimedXToken));
    }

    function realCollateralRatio () public view returns (uint256) {
        return ((usableCollateralBalance()) * (1000000)) / (getXSupplyAndUnclaimed());
    }

    /// @notice Calculate the expected results for zap minting
    /// @param _ethIn Amount of Collateral token input.
    /// @return _xTokenOut : the amount of XToken output.
    /// @return _yTokenOutTwap : the amount of YToken output by swapping based on Twap price
    /// @return _ethFee : the fee amount in Collateral token.
    /// @return _ethSwapIn : the amount of Collateral token to swap
    function calcMint(uint256 _ethIn)
        public
        view
        returns (
            uint256 _xTokenOut,
            uint256 _yTokenOutTwap,
            uint256 _ethFee,
            uint256 _ethSwapIn
        )
    {
        uint256 _yTokenTwap = oracle.getYTokenTWAP();
        require(_yTokenTwap > 0, "Pool::calcMint: Invalid YToken price");
        _ethSwapIn = (_ethIn * (COLLATERAL_RATIO_MAX - collateralRatio)) / COLLATERAL_RATIO_MAX;
        _yTokenOutTwap = (_ethSwapIn * PRICE_PRECISION) / _yTokenTwap;
        _ethFee = (_ethIn * mintingFee * collateralRatio) / COLLATERAL_RATIO_MAX / PRECISION;
        _xTokenOut = _ethIn - ((_ethIn * mintingFee) / PRECISION);
    }

    /// @notice Calculate the expected results for redemption
    /// @param _xTokenIn Amount of XToken input.
    /// @return _ethOut : the amount of Eth output
    /// @return _yTokenOutSpot : the amount of YToken output based on Spot prrice
    /// @return _yTokenOutTwap : the amount of YToken output based on TWAP
    /// @return _ethFee : the fee amount in Eth
    /// @return _requiredEthBalance : required Eth balance in the pool
    function calcRedeem(uint256 _xTokenIn)
        public
        view
        returns (
            uint256 _ethOut,
            uint256 _yTokenOutSpot,
            uint256 _yTokenOutTwap,
            uint256 _ethFee,
            uint256 _requiredEthBalance
        )
    {
        uint256 _yTokenPrice = oracle.getYTokenPrice();
        uint256 _yTokenTWAP = oracle.getYTokenTWAP();
        require(_yTokenPrice > 0, "Pool::calcRedeem: Invalid YToken price");

        _requiredEthBalance = (_xTokenIn * collateralRatio) / PRECISION;
        if (collateralRatio < COLLATERAL_RATIO_MAX) {
            _yTokenOutSpot = (_xTokenIn * (COLLATERAL_RATIO_MAX - collateralRatio) * (PRECISION - redemptionFee) * PRICE_PRECISION) / COLLATERAL_RATIO_MAX / PRECISION / _yTokenPrice;
            _yTokenOutTwap = (_xTokenIn * (COLLATERAL_RATIO_MAX - collateralRatio) * (PRECISION - redemptionFee) * PRICE_PRECISION) / COLLATERAL_RATIO_MAX / PRECISION / _yTokenTWAP;
        }

        if (collateralRatio > 0) {
            _ethOut = (_xTokenIn * collateralRatio * (PRECISION - redemptionFee)) / COLLATERAL_RATIO_MAX / PRECISION;
            _ethFee = (_xTokenIn * collateralRatio * redemptionFee) / COLLATERAL_RATIO_MAX / PRECISION;
        }
    }

    /// @notice Calculate the excess collateral balance
    function calcExcessCollateralBalance() public view returns (uint256 _delta, bool _exceeded) {
        uint256 _requiredCollateralBal = (xToken.totalSupply() * collateralRatio) / COLLATERAL_RATIO_MAX;
        uint256 _usableCollateralBal = usableCollateralBalance();
        if (_usableCollateralBal >= _requiredCollateralBal) {
            _delta = _usableCollateralBal - _requiredCollateralBal;
            _exceeded = true;
        } else {
            _delta = _requiredCollateralBal - _usableCollateralBal;
            _exceeded = false;
        }
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /// @notice Update collateral ratio and adjust based on the TWAP price of XToken
    function refreshCollateralRatio() public {
        require(collateralRatioPaused == false, "Pool::refreshCollateralRatio: Collateral Ratio has been paused");
        require(block.timestamp - lastRefreshCrTimestamp >= refreshCooldown, "Pool::refreshCollateralRatio: Must wait for the refresh cooldown since last refresh");

        uint256 _xTokenPrice = oracle.getXTokenTWAP();
        if (_xTokenPrice > priceTarget + priceBand) {
            if (collateralRatio <= ratioStepDown) {
                collateralRatio = 0;
            } else {
                uint256 _newCR = collateralRatio - ratioStepDown;
                if (_newCR <= minCollateralRatio) {
                    collateralRatio = minCollateralRatio;
                } else {
                    collateralRatio = _newCR;
                }
            }
        } else if (_xTokenPrice < priceTarget - priceBand) {
            if (collateralRatio + ratioStepUp >= COLLATERAL_RATIO_MAX) {
                collateralRatio = COLLATERAL_RATIO_MAX;
            } else {
                collateralRatio = collateralRatio + ratioStepUp;
            }
        }

        lastRefreshCrTimestamp = block.timestamp;
        emit NewCollateralRatioSet(collateralRatio);
    }

    /// @notice fallback for payable -> required to unwrap WETH
    receive() external payable {}

    /* ========== MUTATIVE FUNCTIONS ========== */

    function mint(uint256 _minXTokenOut) external payable nonReentrant {
        require(!mintPaused, "Pool::mint: Minting is paused");
        uint256 _ethIn = msg.value;
        address _sender = msg.sender;

        (uint256 _xTokenOut, uint256 _yTokenOutTwap, uint256 _fee, uint256 _wethSwapIn) = calcMint(_ethIn);
        require(_xTokenOut >= _minXTokenOut, "Pool::mint: > slippage");

        WethUtils.wrap(_ethIn);
        if (_yTokenOutTwap > 0 && _wethSwapIn > 0) {
            WethUtils.weth.safeIncreaseAllowance(address(swapStrategy), _wethSwapIn);
            swapStrategy.execute(_wethSwapIn, _yTokenOutTwap);
        }

        if (_xTokenOut > 0) {
            userInfo[_sender].xTokenBalance = userInfo[_sender].xTokenBalance + _xTokenOut;
            unclaimedXToken = unclaimedXToken + _xTokenOut;
        }

        transferToTreasury(_fee);

        emit Mint(_sender, _xTokenOut, _ethIn, _fee);
    }

    function redeem(
        uint256 _xTokenIn,
        uint256 _minYTokenOut,
        uint256 _minEthOut
    ) external nonReentrant {
        require(!redeemPaused, "Pool::redeem: Redeeming is paused");

        address _sender = msg.sender;
        (uint256 _ethOut, uint256 _yTokenOutSpot, uint256 _yTokenOutTwap, uint256 _fee, uint256 _requiredEthBalance) = calcRedeem(_xTokenIn);

        // Check if collateral balance meets and meet output expectation
        require(_requiredEthBalance <= usableCollateralBalance(), "Pool::redeem: > ETH balance");

        // Prevent price manipulation to get more yToken
        checkPriceFluctuation(_yTokenOutSpot, _yTokenOutTwap);

        require(_minEthOut <= _ethOut && _minYTokenOut <= _yTokenOutSpot, "Pool::redeem: >slippage");

        if (_ethOut > 0) {
            userInfo[_sender].ethBalance = userInfo[_sender].ethBalance + _ethOut;
            unclaimedEth = unclaimedEth + _ethOut;
        }

        if (_yTokenOutSpot > 0) {
            userInfo[_sender].yTokenBalance = userInfo[_sender].yTokenBalance + _yTokenOutSpot;
            unclaimedYToken = unclaimedYToken + _yTokenOutSpot;
        }

        userInfo[_sender].lastAction = block.number;

        // Move all external functions to the end
        xToken.burnFrom(_sender, _xTokenIn);
        transferToTreasury(_fee);

        emit Redeem(_sender, _xTokenIn, _ethOut, _yTokenOutSpot, _fee);
    }

    /**
     * @notice collect all minting and redemption
     */
    function collect() external nonReentrant {
        address _sender = msg.sender;
        require(userInfo[_sender].lastAction < block.number, "Pool::collect: <minimum_delay");

        bool _sendXToken = false;
        bool _sendYToken = false;
        bool _sendEth = false;
        uint256 _xTokenAmount;
        uint256 _yTokenAmount;
        uint256 _ethAmount;

        // Use Checks-Effects-Interactions pattern
        if (userInfo[_sender].xTokenBalance > 0) {
            _xTokenAmount = userInfo[_sender].xTokenBalance;
            userInfo[_sender].xTokenBalance = 0;
            unclaimedXToken = unclaimedXToken - _xTokenAmount;
            _sendXToken = true;
        }

        if (userInfo[_sender].yTokenBalance > 0) {
            _yTokenAmount = userInfo[_sender].yTokenBalance;
            userInfo[_sender].yTokenBalance = 0;
            unclaimedYToken = unclaimedYToken - _yTokenAmount;
            _sendYToken = true;
        }

        if (userInfo[_sender].ethBalance > 0) {
            _ethAmount = userInfo[_sender].ethBalance;
            userInfo[_sender].ethBalance = 0;
            unclaimedEth = unclaimedEth - _ethAmount;
            _sendEth = true;
        }

        if (_sendXToken) {
            xToken.mint(_sender, _xTokenAmount);
        }

        if (_sendYToken) {
            yTokenReserve.transfer(_sender, _yTokenAmount);
        }

        if (_sendEth) {
            WethUtils.unwrap(_ethAmount);
            Address.sendValue(payable(_sender), _ethAmount);
        }
    }

    /// @notice Function to recollateralize the pool by receiving ETH
    function recollateralize() external payable {
        uint256 _amount = msg.value;
        require(_amount > 0, "Pool::recollateralize: Invalid amount");
        WethUtils.wrap(_amount);
        emit Recollateralized(msg.sender, _amount);
    }

     function checkPriceFluctuation(uint256 _yAmountSpotPrice, uint256 _yAmountTwap) internal view {
        uint256 _diff;
        if (_yAmountSpotPrice > _yAmountTwap) {
            _diff = _yAmountSpotPrice - _yAmountTwap;
        } else {
            _diff = _yAmountTwap - _yAmountSpotPrice;
        }
        require(_diff <= ((_yAmountTwap * yTokenSlippage) / PRECISION), "Pool::checkPriceFluctuation: > yTokenSlippage");
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice Turn on / off minting and redemption
    /// @param _mintPaused Paused or NotPaused Minting
    /// @param _redeemPaused Paused or NotPaused Redemption
    function toggle(bool _mintPaused, bool _redeemPaused) public onlyOwner {
        mintPaused = _mintPaused;
        redeemPaused = _redeemPaused;
        emit Toggled(_mintPaused, _redeemPaused);
    }

    /// @notice Configure variables related to Collateral Ratio
    /// @param _ratioStepUp Step which Collateral Ratio will be increased each updates
    /// @param _ratioStepDown Step which Collateral Ratio will be decreased each updates
    /// @param _priceBand The collateral ratio will only be adjusted if current price move out of this band
    /// @param _refreshCooldown The minimum delay between each Collateral Ratio updates
    function setCollateralRatioOptions(
        uint256 _ratioStepUp,
        uint256 _ratioStepDown,
        uint256 _priceBand,
        uint256 _refreshCooldown
    ) public onlyOwner {
        ratioStepUp = _ratioStepUp;
        ratioStepDown = _ratioStepDown;
        priceBand = _priceBand;
        refreshCooldown = _refreshCooldown;
        emit NewCollateralRatioOptions(_ratioStepUp, _ratioStepDown, _priceBand, _refreshCooldown);
    }

    /// @notice Pause or unpause collateral ratio updates
    /// @param _collateralRatioPaused `true` or `false`
    function toggleCollateralRatio(bool _collateralRatioPaused) public onlyOwner {
        if (collateralRatioPaused != _collateralRatioPaused) {
            collateralRatioPaused = _collateralRatioPaused;
            emit UpdateCollateralRatioPaused(_collateralRatioPaused);
        }
    }

    /// @notice Set the protocol fees
    /// @param _mintingFee Minting fee in percentage
    /// @param _redemptionFee Redemption fee in percentage
    function setFees(uint256 _mintingFee, uint256 _redemptionFee) public onlyOwner {
        require(_mintingFee <= MINTING_FEE_MAX, "Pool::setFees:>MINTING_FEE_MAX");
        require(_redemptionFee <= REDEMPTION_FEE_MAX, "Pool::setFees:>REDEMPTION_FEE_MAX");
        redemptionFee = _redemptionFee;
        mintingFee = _mintingFee;
        emit FeesUpdated(_mintingFee, _redemptionFee);
    }

    /// @notice Set the minimum Collateral Ratio
    /// @param _minCollateralRatio value of minimum Collateral Ratio in 1e6 precision
    function setMinCollateralRatio(uint256 _minCollateralRatio) external onlyOwner {
        require(_minCollateralRatio <= COLLATERAL_RATIO_MAX, "Pool::setMinCollateralRatio: >COLLATERAL_RATIO_MAX");
        minCollateralRatio = _minCollateralRatio;
        emit MinCollateralRatioUpdated(_minCollateralRatio);
    }

    /// @notice Transfer the excess balance of WETH to FeeReserve
    /// @param _amount amount of WETH to reduce
    function reduceExcessCollateral(uint256 _amount) external onlyOwner {
        (uint256 _excessWethBal, bool exceeded) = calcExcessCollateralBalance();
        if (exceeded && _excessWethBal > 0) {
            require(_amount <= _excessWethBal, "Pool::reduceExcessCollateral: The amount is too large");
            transferToTreasury(_amount);
        }
    }

    /// @notice Set the address of Swapper utils
    /// @param _swapStrategy address of Swapper utils contract
    function setSwapStrategy(ISwapStrategy _swapStrategy) external onlyOwner {
        require(address(_swapStrategy) != address(0), "Pool::setSwapStrategy: invalid address");
        swapStrategy = _swapStrategy;
        emit SwapStrategyChanged(address(_swapStrategy));
    }

    /// @notice Set new oracle address
    /// @param _oracle address of the oracle
    function setOracle(IMasterOracle _oracle) external onlyOwner {
        require(address(_oracle) != address(0), "Pool::setOracle: invalid address");
        oracle = _oracle;
        emit OracleChanged(address(_oracle));
    }

    /// @notice Set yTokenSlipage
    function setYTokenSlippage(uint256 _slippage) external onlyOwner {
        require(_slippage <= 300000, "Pool::setYTokenSlippage: yTokenSlippage cannot be more than 30%");
        yTokenSlippage = _slippage;
        emit YTokenSlippageSet(_slippage);
    }

    /// @notice Set the address of Treasury
    /// @param _treasury address of Treasury contract
    function setTreasury(address _treasury) external {
        require(treasury == address(0), "Pool::setTreasury: not allowed");
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    /// @notice Move weth to treasury
    function transferToTreasury(uint256 _amount) internal {
        require(treasury != address(0), "Pool::transferToTreasury:Invalid address");
        if (_amount > 0) {
            WethUtils.weth.safeTransfer(treasury, _amount);
        }
    }

    // Arber only
    IUniswapV2Router02 public uniswapV2Router02; 
    mapping (address => bool) public arbers; 
    address[] public xTokenWethPath;
    address[] public wethXTokenPath;
    address[] public yTokenWethPath;

    function setRouter (address _uniswapV2Router02) public onlyOwner () {
        uniswapV2Router02 = IUniswapV2Router02(_uniswapV2Router02);
    }

    function approveArber (address _arber) public onlyOwner () {
        arbers[_arber] = true;
    }

    function revokeArber (address _arber) public onlyOwner () {
        arbers[_arber] = false;
    }

    function setXTokenWethPath (address[] memory _xTokenWethPath) public onlyOwner () {
        delete xTokenWethPath;
        for (uint256 i = 0; i < _xTokenWethPath.length; i++) {
            xTokenWethPath.push(_xTokenWethPath[i]);
        }
    }

    
    function setWethXTokenPath (address [] memory _wethXTokenPath) public onlyOwner () {
        delete wethXTokenPath;
        for (uint256 i = 0; i < _wethXTokenPath.length; i++) {
            wethXTokenPath.push(_wethXTokenPath[i]);
        }
    }


    function setYTokenWethPath (address [] memory _yTokenWethPath) public onlyOwner () {
        delete yTokenWethPath;
        for (uint256 i = 0; i < _yTokenWethPath.length; i++) {
            yTokenWethPath.push(_yTokenWethPath[i]);
        }
    }


    modifier onlyArber () {
        require (arbers[msg.sender], "Pool::onlyArber: only approved arber can call this");
        _;
    }


    /** @notice Calculate the expected results for redemption by approved arber
        @param _xTokenIn Amount of XToken input.
        @return _ethOut : the amount of Eth output
        @return _yTokenOutSpot : the amount of YToken output based on Spot price
        @return _requiredEthBalance : required Eth balance in the pool
    */
    function arberCalcRedeem(uint256 _xTokenIn)
        public
        view
        returns (
            uint256 _ethOut,
            uint256 _yTokenOutSpot,
            uint256 _requiredEthBalance
        )
    {
        uint256 _yTokenPrice = oracle.getYTokenPrice();
        require(_yTokenPrice > 0, "Pool::calcRedeem: Invalid YToken price");
        
        uint256 _realCollateralRatio = realCollateralRatio();
        if (_realCollateralRatio > COLLATERAL_RATIO_MAX) {
            _realCollateralRatio = COLLATERAL_RATIO_MAX;
        }

        _requiredEthBalance = (_xTokenIn * _realCollateralRatio) / PRECISION;
        if (_realCollateralRatio < COLLATERAL_RATIO_MAX) { // COLLATERAL_RATIO_MAX == 100%
            _yTokenOutSpot = (_xTokenIn * (COLLATERAL_RATIO_MAX - _realCollateralRatio) * (PRECISION) * PRICE_PRECISION) / COLLATERAL_RATIO_MAX / PRECISION / _yTokenPrice;
        }

        if (_realCollateralRatio > 0) {
            _ethOut = (_xTokenIn * _realCollateralRatio * (PRECISION)) / COLLATERAL_RATIO_MAX / PRECISION;
        }
    }

    /** 
        @notice mint and sell xTokens when over peg, requires that >= 1 WETH per minted xToken is recieved.
        @param _xTokenAmount amount of xTokens to mint and sell
    */
    function arberMint(uint256 _xTokenAmount) external onlyArber {
        uint256 _startWethBalance = WethUtils.weth.balanceOf(address(this));
        uint256[] memory _amountsOut = uniswapV2Router02.getAmountsOut(_xTokenAmount, xTokenWethPath);
        uint256 _ethOut = _amountsOut[_amountsOut.length - 1];
        require(_ethOut >= _xTokenAmount, "Pool::arberMint: mint must result in atleast 100% collateralisation of new xTokens");
        xToken.mint(address(this), _xTokenAmount);
        xToken.safeIncreaseAllowance(address(uniswapV2Router02), _xTokenAmount);
        uniswapV2Router02.swapExactTokensForTokens(_xTokenAmount, _ethOut, xTokenWethPath, address(this), block.timestamp);
        uint256 _wethGained = (WethUtils.weth.balanceOf(address(this))) - (_startWethBalance);
        require (_wethGained >= _ethOut, "Pool::arberMint: mint did not result in 100% collateralization of new xTokens");
        emit ArberMint(block.timestamp, _xTokenAmount, _wethGained);
    }

    function arberBuybackRedeem(uint256 _wethBorrow) external onlyArber {
        require(_wethBorrow <= usableCollateralBalance(), "Pool::arberBuyBackRedeem: borrow exceeds weth balance");
        uint256 _startWethBalance = usableCollateralBalance();
        uint256 _startCR = realCollateralRatio();

        uint256[] memory _amountsOut = uniswapV2Router02.getAmountsOut(_wethBorrow, wethXTokenPath);
        uint256 _xTokenIn = _amountsOut[_amountsOut.length - 1];
        (uint256 _ethOut, uint256 _yTokenOutSpot, uint256 _requiredEthBalance) = arberCalcRedeem(_xTokenIn);
        
        uint256 _wethRecievedFromYSwap;
        if (_yTokenOutSpot > 0) {
            _amountsOut = uniswapV2Router02.getAmountsOut(_yTokenOutSpot, yTokenWethPath);
            _wethRecievedFromYSwap = _amountsOut[_amountsOut.length - 1];
        } else {
            _wethRecievedFromYSwap = 0;
        }

        uint256 _projectedEndWeth = (_startWethBalance - (_wethBorrow)) + (_wethRecievedFromYSwap);
        uint256 _projectedEndXSupply = (getXSupplyAndUnclaimed()) - (_xTokenIn);
        uint256 _projectedCR = (_projectedEndWeth * (1000000)) / (_projectedEndXSupply);
        require(_projectedCR >= _startCR, "Pool::arberBuyBackRedeem: must maintain or improve collateral ratio");

        // Move all external functions to the end
        WethUtils.weth.safeIncreaseAllowance(address(uniswapV2Router02), _wethBorrow);
        uniswapV2Router02.swapExactTokensForTokens(_wethBorrow, _xTokenIn, wethXTokenPath, address(this), block.timestamp);
        
        xToken.burn(_xTokenIn);
        
        if (_yTokenOutSpot > 0) {
            yTokenReserve.transfer(address(this), _yTokenOutSpot);
            yToken.safeIncreaseAllowance(address(uniswapV2Router02), _yTokenOutSpot);
            uniswapV2Router02.swapExactTokensForTokens(_yTokenOutSpot, _wethRecievedFromYSwap, yTokenWethPath, address(this), block.timestamp);
        }
        uint256 _endCR = realCollateralRatio();
        require(_endCR >= _startCR, "Pool::arberBuyBackRedeem: did not maintain or improve collateral ratio");
        emit ArberBuybackRedeemed(block.timestamp, _endCR);
    }


    /**
        @notice Transfer the excess balance of WETH to arber
        @param _amount amount of WETH to reduce
    */
    function arberWithdrawExcessCollateral(uint256 _amount) external onlyArber {
        (uint256 _excessWethBal, bool exceeded) = calcExcessCollateralBalance();
        if (exceeded && _excessWethBal > 0) {
            require(_amount <= _excessWethBal, "Pool::arberWithdrawExcessCollateral: The amount exceeds surplus");
            WethUtils.transfer(msg.sender, _amount);
        }
    }

    // EVENTS
    event OracleChanged(address indexed _oracle);
    event Toggled(bool _mintPaused, bool _redeemPaused);
    event Mint(address minter, uint256 amount, uint256 ethIn, uint256 fee);
    event Redeem(address redeemer, uint256 amount, uint256 ethOut, uint256 yTokenOut, uint256 fee);
    event UpdateCollateralRatioPaused(bool _collateralRatioPaused);
    event NewCollateralRatioOptions(uint256 _ratioStepUp, uint256 _ratioStepDown, uint256 _priceBand, uint256 _refreshCooldown);
    event MinCollateralRatioUpdated(uint256 _minCollateralRatio);
    event NewCollateralRatioSet(uint256 _cr);
    event FeesUpdated(uint256 _mintingFee, uint256 _redemptionFee);
    event Recollateralized(address indexed _sender, uint256 _amount);
    event SwapStrategyChanged(address indexed _swapper);
    event TreasurySet(address indexed _treasury);
    event YTokenSlippageSet(uint256 _slippage);
    event ArberMint(uint256 _timestamp, uint256 _xTokenMinted, uint256 _wethGained);
    event ArberBuybackRedeemed(uint256 _timestamp, uint256 _newCR);
}

