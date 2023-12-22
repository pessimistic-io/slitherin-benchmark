// SPDX-License-Identifier: GPL-3.0

/// @notice This contract is responsible for Vault for LP and vault for CDX-core.

pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {TransferHelper} from "./TransferHelper.sol";
import {Address} from "./Address.sol";
import {SafeMath} from "./SafeMath.sol";
import {ILPPool} from "./ILPPool.sol";
import {BokkyPooBahsDateTimeLibrary} from "./BokkyPooBahsDateTimeLibrary.sol";
import {Initializable} from "./Initializable.sol";
import {DataTypes} from "./DataTypes.sol";
import {ConfigurationParam} from "./ConfigurationParam.sol";
import {VaultFeeCalculation} from "./VaultFeeCalculation.sol";
import {Ownable} from "./Ownable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ISwap} from "./ISwap.sol";

import {IRouter} from "./IRouter.sol";
import {IPositionRouter} from "./IPositionRouter.sol";
import {GVault} from "./GVault.sol";
import {ConvertDecimals} from "./ConvertDecimals.sol";
import "./SafeCast.sol";

contract Vault is Ownable, Initializable, ReentrancyGuard {
    using SafeCast for uint256;
    using SafeMath for uint256;
    /// @dev approve target for GMX position router
    IRouter public router;
    /// @dev GMX position router
    IPositionRouter public positionRouter;
    /// @dev GMX vault
    GVault public gmxvault;

    ILPPool public lPPoolAddress;
    ISwap public swap;
    address public cdxAddress;
    uint256 public totalAsset;
    address public ownerAddress;
    bool public notFreezeStatus;
    address public guardianAddress;
    bool public locked;
    address public stableC;
    uint256 public manageFee;
    uint256 public profitFee;
    uint256 public coolDown;

    bytes32 public referralCode;
    bytes32 public pendingOrderKey;
    uint256 public lastOrderTimestamp;
    DataTypes.DecreaseHedgingPool decreaseHedging;
    DataTypes.IncreaseHedgingPool IncreaseHedging;

    uint256 public constant GMX_PRICE_PRECISION = 10 ** 30;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 leverage;

    /// @dev Initialise important addresses for the contract
    function initialize(address _positionRouter, address _router) external initializer {
        _transferOwnership(_msgSender());
        _initNonReentrant();
        referralCode = bytes32("CDX");
        positionRouter = IPositionRouter(_positionRouter);
        router = IRouter(_router);
        gmxvault = GVault(positionRouter.vault());
        router.approvePlugin(address(positionRouter));
        leverage = 1;
        totalAsset = 1;
        ownerAddress = msg.sender;
        notFreezeStatus = true;
        manageFee = 20000;
        profitFee = 100000;
        coolDown = 2;
        stableC = ConfigurationParam.USDT;
        guardianAddress = ConfigurationParam.GUARDIAN;
    }

    fallback() external payable {
        emit Log(msg.sender, msg.value);
    }

    function setLeverage(uint256 _leverage) external onlyOwner {
        leverage = _leverage;
    }

    //  * @dev create increase position order on GMX router
    //  * @param _path  [collateralToken] or [tokenIn, collateralToken ] if a swap
    //  * @param _indexToken
    //  * @param _amountIn
    //  * @param _sizeDelta
    //  * @param _acceptablePrice:
    function _createIncreasePosition(uint256 acceptablePrice) external onlyOwner nonReentrant {
        DataTypes.IncreaseHedgingPool memory _hedging = IncreaseHedging;
        delete IncreaseHedging;
        require(acceptablePrice > 0, "Value cannot be zero");
        _hedging.acceptablePrice = acceptablePrice;
        TransferHelper.safeApprove(_hedging.path[0], address(router), _hedging.amountIn);
        uint256 executionFee = _getExecutionFee();
        positionRouter.createIncreasePosition{value: executionFee}(
            _hedging.path,
            _hedging.indexToken,
            _hedging.amountIn,
            0,
            _hedging.sizeDelta,
            false,
            _hedging.acceptablePrice,
            executionFee,
            referralCode,
            address(this)
        );
        //pendingOrderKey = key;
        lastOrderTimestamp = block.timestamp;
        emit CreateIncreasePosition(
            _hedging.path,
            _hedging.indexToken,
            _hedging.amountIn,
            _hedging.sizeDelta,
            _hedging.acceptablePrice,
            lastOrderTimestamp
        );
    }

    //  * @dev create decrease position order on GMX router
    //  * @param _path  [collateralToken] or [tokenIn, collateralToken ] if a swap
    //  * @param _indexToken
    //  * @param _sizeDelta
    //  * @param _acceptablePrice:
    //  * @param _collateralDelta:
    function _createDecreasePosition(uint256 _collateralDelta) external payable onlyOwner nonReentrant {
        DataTypes.DecreaseHedgingPool memory _hedging = decreaseHedging;
        require(_collateralDelta > 0, "Value cannot be zero");
        delete decreaseHedging;
        uint256 executionFee = _getExecutionFee();
        positionRouter.createDecreasePosition{value: executionFee}(
            _hedging.path,
            _hedging.indexToken,
            _hedging.collateralDelta,
            _hedging.sizeDelta,
            false,
            address(this),
            _hedging.acceptablePrice,
            0,
            executionFee,
            false,
            address(this)
        );
        //pendingOrderKey = key;
        lastOrderTimestamp = block.timestamp;
        emit CreateDecreasePosition(
            _hedging.path,
            _hedging.indexToken,
            _hedging.sizeDelta,
            _hedging.acceptablePrice,
            _hedging.collateralDelta,
            lastOrderTimestamp
        );
    }

    /// @dev Update swap contract addresses for the contract.
    function updateSwapExactAddress(address _swapAddress) external onlyOwner {
        require(Address.isContract(_swapAddress), "BasePositionManager: the parameter is not the contract address");
        swap = ISwap(_swapAddress);
    }

    /// @dev Update StableC addresses for the contract.
    function updateStableC(address _stableC) external onlyOwner {
        require(
            _stableC == ConfigurationParam.USDC || _stableC == ConfigurationParam.USDT,
            "BasePositionManager: the parameter is error address"
        );
        stableC = _stableC;
    }

    function updateManageFee(uint256 _manageFee) external onlyOwner {
        require(_manageFee > 0, "manageFee is zero");
        manageFee = _manageFee;
    }

    function updateProfitFee(uint256 _profitFee) external onlyOwner {
        require(_profitFee > 0, "profitFee is zero");
        profitFee = _profitFee;
    }

    function updateCoolDown(uint256 _coolDown) external onlyOwner {
        require(_coolDown > 0, "coolDown is zero");
        coolDown = _coolDown;
    }

    /// @dev update locked value.
    function updateLocked(bool _locked) external onlyOwner {
        locked = _locked;
    }

    /// @dev update freezeStatus value.
    function updateFreezeStatus(bool _notFreezeStatus) external onlyOwner {
        notFreezeStatus = _notFreezeStatus;
    }

    /**
     * Returns bool
     * notice To the third party platform for hedging processing.
     * @param _isSell Hedge type, buy or sell.
     * @param _token Hedge token address.
     * @param _amount Hedge quantity.
     * @param _releaseHeight Specified height hedge.
     */
    function hedgeTreatment(
        bool _isSell,
        address _token,
        uint256 _amount,
        uint256 _releaseHeight
    ) external onlyCDXOrOwner synchronized returns (bool) {
        require(notFreezeStatus, "BasePositionManager: this operation cannot be performed.");
        require(_amount > 0, "BasePositionManager: must be greater than zero");
        require(Address.isContract(_token), "BasePositionManager: the parameter is not the contract address");
        IERC20 ERC20TOKEN = IERC20(_token);

        address[] memory collateralToken = new address[](1);
        collateralToken[0] = stableC;

        if (_isSell) {
            uint256 price = ERC20TOKEN.balanceOf(address(this));

            if (price == 0) {
                uint256 usdcAmount = tokenToUsd(_token, _amount);
                uint256 acceptablePrice = getTokenPrice(_token);
                acceptablePrice = acceptablePrice - ((acceptablePrice * 2) / 100);
                _createIncreasePosition(collateralToken, _token, usdcAmount, acceptablePrice);
            } else {
                if (price < _amount) {
                    uint256 surplusPrice = _amount - price;
                    _swapExactInputSingle(_token, price);
                    uint256 surplusUSDCAmount = tokenToUsd(_token, surplusPrice);
                    uint256 acceptablePrice = getTokenPrice(_token);
                    acceptablePrice = acceptablePrice - ((acceptablePrice * 2) / 100);
                    _createIncreasePosition(collateralToken, _token, surplusUSDCAmount, acceptablePrice);
                } else {
                    _swapExactInputSingle(_token, _amount);
                }
            }
        } else {
            uint256 usdcAmount = tokenToUsd(_token, _amount);
            DataTypes.PositionDetails memory position = this.getPosition(stableC, _token);
            uint256 size = usdToToken(
                _token,
                (position.size * ConfigurationParam.STABLEC_DECIMAL) / GMX_PRICE_PRECISION
            );
            if (size == 0) {
                _swapExactOutputSingle(usdcAmount, _amount, _token);
            } else {
                if (size < _amount) {
                    uint256 surplusValue = (_amount - size);
                    uint256 usdcPrice = tokenToUsd(_token, surplusValue);
                    _swapExactOutputSingle(usdcPrice, surplusValue, _token);
                    uint256 usdcPriceGmx = (position.size * ConfigurationParam.STABLEC_DECIMAL) / GMX_PRICE_PRECISION;
                    uint256 acceptablePrice = getTokenPrice(_token);
                    acceptablePrice = acceptablePrice + ((acceptablePrice * 2) / 100);
                    _createDecreasePosition(collateralToken, _token, usdcPriceGmx, true, acceptablePrice);
                } else {
                    uint256 acceptablePrice = getTokenPrice(_token);
                    acceptablePrice = acceptablePrice + ((acceptablePrice * 2) / 100);
                    _createDecreasePosition(collateralToken, _token, usdcAmount, false, acceptablePrice);
                }
            }
        }
        bool deleteHedgingAggregator = lPPoolAddress.deleteHedgingAggregator(_releaseHeight);
        require(deleteHedgingAggregator, "CustomerManager: deleteHedgingAggregator failed");
        return true;
    }

    function _swapExactInputSingle(address _token, uint256 _amount) internal {
        TransferHelper.safeApprove(_token, address(swap), _amount);
        (bool result, ) = swap.swapExactInputSingle(_amount, _token, stableC, address(this));
        require(result, "UniswapManager: uniswap failed");
    }

    function getTokenPrice(address _token) public view returns (uint256) {
        uint256 price;
        if (_token == ConfigurationParam.WETH) {
            price = swap.getTokenPrice(ConfigurationParam.ETHAddress);
        } else {
            price = swap.getTokenPrice(ConfigurationParam.BTCAddress);
        }
        return price;
    }

    function getDecreaseHedging() public view returns (DataTypes.DecreaseHedgingPool memory) {
        return decreaseHedging;
    }

    function getIncreaseHedging() public view returns (DataTypes.IncreaseHedgingPool memory) {
        return IncreaseHedging;
    }

    function usdToToken(address _token, uint256 _amount) public view returns (uint256) {
        uint256 changeAmount;
        if (_token == ConfigurationParam.WETH) {
            uint256 price = swap.getTokenPrice(ConfigurationParam.ETHAddress);
            changeAmount =
                (_amount * ConfigurationParam.WETH_DECIMAL * ConfigurationParam.ORACLE_DECIMAL) /
                (price * ConfigurationParam.STABLEC_DECIMAL);
        } else {
            uint256 price = swap.getTokenPrice(ConfigurationParam.BTCAddress);
            changeAmount =
                (_amount * ConfigurationParam.WBTC_DECIMAL * ConfigurationParam.ORACLE_DECIMAL) /
                (price * ConfigurationParam.STABLEC_DECIMAL);
        }
        return changeAmount;
    }

    function tokenToUsd(address _token, uint256 _amount) public view returns (uint256) {
        uint256 usdcAmount;
        if (_token == ConfigurationParam.WETH) {
            uint256 price = swap.getTokenPrice(ConfigurationParam.ETHAddress);
            usdcAmount =
                (_amount * price * ConfigurationParam.STABLEC_DECIMAL) /
                (ConfigurationParam.WETH_DECIMAL * ConfigurationParam.ORACLE_DECIMAL);
        } else {
            uint256 price = swap.getTokenPrice(ConfigurationParam.BTCAddress);
            usdcAmount =
                (_amount * price * ConfigurationParam.STABLEC_DECIMAL) /
                (ConfigurationParam.WBTC_DECIMAL * ConfigurationParam.ORACLE_DECIMAL);
        }
        return usdcAmount;
    }

    function _swapExactOutputSingle(uint256 surplusValue, uint256 _amount, address _token) internal {
        surplusValue = surplusValue + surplusValue / 10;
        TransferHelper.safeApprove(stableC, address(swap), surplusValue);
        (bool result, ) = swap.swapExactOutputSingle(
            _amount, //etc
            surplusValue, //usdc
            stableC,
            _token,
            address(this)
        );
        require(result, "UniswapManager: uniswap failed");
    }

    function _createIncreasePosition(
        address[] memory collateralToken,
        address _token,
        uint256 amount,
        uint256 acceptablePrice
    ) internal {
        uint256 sizeDelta = (amount * GMX_PRICE_PRECISION) / ConfigurationParam.STABLEC_DECIMAL;
        uint256 amountIn = amount.div(leverage);
        IncreaseHedging = DataTypes.IncreaseHedgingPool({
            path: collateralToken,
            indexToken: _token,
            amountIn: amountIn,
            sizeDelta: sizeDelta,
            acceptablePrice: (acceptablePrice * GMX_PRICE_PRECISION) / ConfigurationParam.ORACLE_DECIMAL
        });
    }

    function _createDecreasePosition(
        address[] memory collateralToken,
        address _token,
        uint256 collateralDelta,
        bool _isClose,
        uint256 acceptablePrice
    ) internal {
        if (_isClose) {
            DataTypes.PositionDetails memory position = this.getPosition(stableC, _token);
            decreaseHedging = DataTypes.DecreaseHedgingPool({
                path: collateralToken,
                indexToken: _token,
                sizeDelta: position.size,
                acceptablePrice: (acceptablePrice * GMX_PRICE_PRECISION) / ConfigurationParam.ORACLE_DECIMAL,
                collateralDelta: 0
            });
        } else {
            uint256 sizeDelta = (collateralDelta * GMX_PRICE_PRECISION) / ConfigurationParam.STABLEC_DECIMAL;
            DataTypes.PositionDetails memory currentPosition = this.getPosition(stableC, _token);
            uint256 amountOut;
            if (currentPosition.size <= sizeDelta) {
                amountOut = sizeDelta.div(leverage);
            } else {
                amountOut = currentPosition.size.div(leverage) - (currentPosition.size - sizeDelta).div(leverage);
            }
            decreaseHedging = DataTypes.DecreaseHedgingPool({
                path: collateralToken,
                indexToken: _token,
                sizeDelta: sizeDelta,
                acceptablePrice: (acceptablePrice * GMX_PRICE_PRECISION) / ConfigurationParam.ORACLE_DECIMAL,
                collateralDelta: amountOut
            });
        }
    }

    /// @dev Update LPPool contract addresses for the contract.
    function updateLPPoolAddress(address _lPPoolAddress) external onlyOwner {
        require(Address.isContract(_lPPoolAddress), "BasePositionManager: illegal contract address");
        lPPoolAddress = ILPPool(_lPPoolAddress);
    }

    /// @dev Update CDX-core contract addresses for the contract.
    function updateCDXAddress(address _cdxAddress) external onlyOwner {
        require(Address.isContract(_cdxAddress), "BasePositionManager: illegal contract address");
        cdxAddress = _cdxAddress;
    }

    /**
     * notice Accept the bonus calculated by the robot and transfer the bonus to cdx through this contract.
     * @param _token_address Bonus token address.
     * @param _amount Bonus quantity.
     * @param _customerId Customer id.
     * @param _pid Product id.
     * @param _purchaseProductAmount Purchase amount.
     * @param _releaseHeight Specified height.
     */
    function transferToCDX(
        address _token_address,
        uint256 _amount,
        uint256 _customerId,
        uint256 _pid,
        uint256 _purchaseProductAmount,
        uint256 _releaseHeight
    ) external onlyCDXOrOwner nonReentrant {
        require(notFreezeStatus, "BasePositionManager: this operation cannot be performed.");
        require(_amount > 0, "TransferManager: transfer amount must be greater than zero");
        require(getBalanceOf(_token_address) >= _amount, "TransferManager: your credit is running low");
        DataTypes.HedgingAggregatorInfo memory hedgingAggregator = DataTypes.HedgingAggregatorInfo({
            customerId: _customerId,
            productId: _pid,
            amount: _purchaseProductAmount,
            releaseHeight: _releaseHeight
        });
        bool result = lPPoolAddress.addHedgingAggregator(hedgingAggregator);
        require(result, "LPPoolManager: deleteHedgingAggregator failed");
        TransferHelper.safeTransfer(_token_address, cdxAddress, _amount);
        emit TransferHelperEvent(
            address(this),
            cdxAddress,
            _amount,
            _token_address,
            DataTypes.TransferHelperStatus.TOCDXCORE
        );
        emit TransferToCDX(_token_address, _amount);
    }

    /**
     * notice Updated net worth change.
     * @param optionsHoldingPrice Value of all options.
     */
    function updateAsset(uint256 optionsHoldingPrice) external onlyOwner returns (bool) {
        if (optionsHoldingPrice == 0 && getBalanceOf(stableC) == 0 && totalAsset == 1) {
            return true;
        }
        DataTypes.PositionDetails memory positionWETH = this.getPosition(stableC, ConfigurationParam.WETH);
        DataTypes.PositionDetails memory positionWBTC = this.getPosition(stableC, ConfigurationParam.WBTC);
        uint256 wethValue = tokenToUsd(ConfigurationParam.WETH, getBalanceOf(ConfigurationParam.WETH));
        uint256 wbtcValue = tokenToUsd(ConfigurationParam.WBTC, getBalanceOf(ConfigurationParam.WBTC));
        uint256 latestTotalAsset = optionsHoldingPrice +
            getBalanceOf(stableC) +
            uint256(positionWETH.unrealisedPnl) +
            uint256(positionWBTC.unrealisedPnl) +
            positionWETH.collateral +
            positionWBTC.collateral +
            wethValue +
            wbtcValue;
        uint256 manageFeeValue = (latestTotalAsset * manageFee) / (ConfigurationParam.PERCENTILE * 365);
        totalAsset = latestTotalAsset - manageFeeValue;
        bool result = lPPoolAddress.dealLPPendingInit(totalAsset);
        require(result, "LPPoolManager: failed to process initialization value");
        TransferHelper.safeTransfer(stableC, guardianAddress, manageFeeValue);
        emit TransferHelperEvent(
            address(this),
            guardianAddress,
            manageFeeValue,
            stableC,
            DataTypes.TransferHelperStatus.TOMANAGE
        );
        return true;
    }

    /**
     * notice LP investment.
     * @param ercToken Token address.
     * @param amount Amount of investment
     */
    function applyVault(address ercToken, uint256 amount) external nonReentrant synchronized returns (bool) {
        require(notFreezeStatus, "BasePositionManager: this operation cannot be performed.");
        require(amount > 0, "BasePositionManager: credit amount cannot be zero");
        require(ercToken != address(0), "TokenManager: the ercToken address cannot be empty");
        bool result = lPPoolAddress.addLPAmountInfo(amount, msg.sender);
        require(result, "LPPoolManager: add LPAmountInfo fail");
        TransferHelper.safeTransferFrom(ercToken, msg.sender, address(this), amount);
        emit TransferHelperEvent(msg.sender, address(this), amount, ercToken, DataTypes.TransferHelperStatus.TOTHIS);
        emit ApplyVault(ercToken, amount, msg.sender);
        return result;
    }

    /**
     * notice Make an appointment to withdraw money, after the appointment cooling-off period can be withdrawn directly.
     * @param lPAddress Wallet address of the person withdrawing the money.
     * @param purchaseHeightInfo Deposit height record.
     */
    function applyWithdrawal(address lPAddress, uint256 purchaseHeightInfo) external returns (bool) {
        require(notFreezeStatus, "BasePositionManager: this operation cannot be performed.");
        bool result = lPPoolAddress.reservationWithdrawal(lPAddress, purchaseHeightInfo);
        require(result, "LPPoolManager: failure to apply for withdrawal");
        emit ApplyWithdrawal(lPAddress, purchaseHeightInfo);
        return result;
    }

    /**
     * notice LP withdrawal.
     * @param lPAddress Wallet address of the person withdrawing the money.
     * @param purchaseHeightInfo Deposit height record.
     */
    function lPwithdrawal(address lPAddress, uint256 purchaseHeightInfo) external nonReentrant returns (bool) {
        //The first step is to verify the withdrawal information.
        require(notFreezeStatus, "BasePositionManager: this operation cannot be performed.");
        DataTypes.LPAmountInfo memory lPAmountInfo = lPPoolAddress.getLPAmountInfoByParams(
            lPAddress,
            purchaseHeightInfo
        );
        require(lPAmountInfo.amount > 0, "LPPollManager: the withdrawal information is abnormal");
        //The second step is to determine whether the cooling-off period has been reached.
        require(lPAmountInfo.reservationTime > 0, "LPPollManager: withdrawals are not scheduled");
        //uint256 day = uint256(BokkyPooBahsDateTimeLibrary.diffDays(lPAmountInfo.createTime, block.timestamp));
        require(
            uint256(BokkyPooBahsDateTimeLibrary.diffDays(lPAmountInfo.reservationTime, block.timestamp)) >= coolDown,
            "LPPollManager: coolDown periods are often inadequate"
        );
        uint256 withdrawalAmount;
        //The third step deals with profit calculation
        if (totalAsset > lPAmountInfo.initValue) {
            uint256 grossProfit = VaultFeeCalculation.profitCalculation(
                lPAmountInfo.initValue,
                totalAsset,
                lPAmountInfo.amount
            );
            //uint256 managementFee = VaultFeeCalculation.ManagementFeeCalculation(lPAmountInfo.amount, day);
            uint256 profitFeeValue = VaultFeeCalculation.ProfitFeeCalculation(
                grossProfit,
                lPAmountInfo.amount,
                profitFee
            );
            //withdrawalAmount = SafeMath.sub(SafeMath.sub(grossProfit, managementFee), profitFee);
            withdrawalAmount = SafeMath.sub(grossProfit, profitFeeValue);
            TransferHelper.safeTransfer(stableC, guardianAddress, profitFeeValue);
            emit TransferHelperEvent(
                address(this),
                guardianAddress,
                profitFee,
                stableC,
                DataTypes.TransferHelperStatus.TOMANAGE
            );
        } else {
            uint256 lossProfit = VaultFeeCalculation.profitCalculation(
                lPAmountInfo.initValue,
                totalAsset,
                lPAmountInfo.amount
            );
            withdrawalAmount = lossProfit;
        }
        //Final withdrawal
        bool result = lPPoolAddress.deleteLPAmountInfoByParam(lPAddress, purchaseHeightInfo);
        require(result, "LPPollManager: failure to withdrawal");
        TransferHelper.safeTransfer(stableC, lPAmountInfo.lPAddress, withdrawalAmount);
        emit TransferHelperEvent(
            address(this),
            lPAmountInfo.lPAddress,
            withdrawalAmount,
            stableC,
            DataTypes.TransferHelperStatus.TOLP
        );
        emit LPwithdrawal(lPAddress, purchaseHeightInfo);
        return result;
    }

    function withdraw(
        address token,
        address recipient,
        uint256 amount
    ) external onlyGuardian nonReentrant returns (bool) {
        require(recipient != address(0), "BasePositionManager: the recipient address cannot be empty");
        require(token != address(0), "TokenManager: the token address cannot be empty");
        uint256 balance = getBalanceOf(token);
        require(balance > 0, "BasePositionManager: insufficient balance");
        require(balance >= amount, "TransferManager: excess balance");
        TransferHelper.safeTransfer(token, recipient, amount);
        emit Withdraw(address(this), recipient, token, amount);
        return true;
    }

    /**
     * @dev get position detail that includes unrealised PNL
     * @param _collatToken  [collateralToken] or [tokenIn, collateralToken] if a swap
     * @param _indexToken The address of the token you want to go long or short
     */
    function getPosition(
        address _collatToken,
        address _indexToken
    ) external view returns (DataTypes.PositionDetails memory position) {
        bool isLong = false;
        (
            uint256 size,
            uint256 collateral,
            uint256 averagePrice,
            uint256 entryFundingRate,
            ,
            ,
            ,
            uint256 lastIncreasedTime
        ) = gmxvault.getPosition(address(this), _collatToken, _indexToken, false);

        int256 unrealisedPnl = 0;
        if (averagePrice > 0) {
            // getDelta will revert if average price == 0;
            (bool hasUnrealisedProfit, uint256 absUnrealisedPnl) = gmxvault.getDelta(
                _indexToken,
                size,
                averagePrice,
                isLong,
                lastIncreasedTime
            );

            if (hasUnrealisedProfit) {
                unrealisedPnl = _convertFromGMXPrecision(absUnrealisedPnl).toInt256();
            } else {
                unrealisedPnl = -_convertFromGMXPrecision(absUnrealisedPnl).toInt256();
            }

            return
                DataTypes.PositionDetails({
                    size: size,
                    collateral: collateral,
                    averagePrice: averagePrice,
                    entryFundingRate: entryFundingRate,
                    unrealisedPnl: unrealisedPnl,
                    lastIncreasedTime: lastIncreasedTime,
                    isLong: isLong
                });
        }
    }

    function gmxPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease) external onlyGMXKeeper {
        emit GMXPositionCallback(positionKey, isExecuted, isIncrease);
    }

    function _convertFromGMXPrecision(uint256 amt) internal pure returns (uint256) {
        return ConvertDecimals.normaliseTo18(amt, GMX_PRICE_PRECISION);
    }

    receive() external payable {}

    function getBalanceOf(address token) public view returns (uint256) {
        IERC20 tokenInToken = IERC20(token);
        return tokenInToken.balanceOf(address(this));
    }

    /// @dev returns the execution fee plus the cost of the gas callback
    function _getExecutionFee() internal view returns (uint256) {
        return positionRouter.minExecutionFee();
    }

    modifier onlyCDXOrOwner() {
        require(cdxAddress == msg.sender || ownerAddress == msg.sender, "Ownable: caller is not the CDX or owner");
        _;
    }

    modifier onlyGuardian() {
        require(guardianAddress == msg.sender, "Ownable: caller is not the Guardian");
        _;
    }

    modifier synchronized() {
        require(!locked, "BasePositionManager: Please wait");
        locked = true;
        _;
        locked = false;
    }
    modifier onlyGMXKeeper() {
        require(msg.sender == address(positionRouter), "GMXFuturesPoolHedger: only GMX keeper can trigger callback");
        _;
    }
    event Log(address from, uint256 value);
    event ApplyVault(address ercToken, uint256 amount, address msgSender);
    event UpdateLatestAmountValue(uint256 blockTime, uint256 latestAmountValue);
    event ApplyWithdrawal(address msgSender, uint256 purchaseHeightInfo);
    event LPwithdrawal(address lPAddress, uint256 purchaseHeightInfo);
    event TransferToCDX(address tokenAddress, uint256 amount);
    event CreateIncreasePosition(
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 sizeDelta,
        uint256 acceptablePrice,
        uint256 lastOrderTimestamp
    );
    event CreateDecreasePosition(
        address[] path,
        address indexToken,
        uint256 sizeDelta,
        uint256 acceptablePrice,
        uint256 collateralDelta,
        uint256 lastOrderTimestamp
    );
    event GMXPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease);
    event TransferHelperEvent(
        address from,
        address to,
        uint256 amount,
        address tokenAddress,
        DataTypes.TransferHelperStatus typeValue
    );
    event Withdraw(address from, address to, address cryptoAddress, uint256 amount);
}

