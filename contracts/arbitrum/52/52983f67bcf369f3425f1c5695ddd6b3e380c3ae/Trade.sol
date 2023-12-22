// SPDX-License-Identifier: ISC

pragma solidity ^0.8.0;

import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./TryCall.sol";
import "./ITrade.sol";
import "./FundState.sol";
import "./IRegistry.sol";

// @address:REGISTRY
IRegistry constant registry = IRegistry(0xD4DEa29C068ea13EfA6E4Dd2FADB14aE2353A541);

contract TradeStorage is Initializable {
    mapping(address => bool) public managers;
    FundState state;
    uint16 public aaveReferralCode;
    bytes32 public gmxRefCode;
    bytes _whitelistMask;
    bool _gmxEnabled;
    bool _aaveEnabled;
    uint256 _fundId;
    uint256 _debt;
    uint256[46] _gap;
}

contract Trade is ITrade, TradeStorage, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

    modifier onlyManager() {
        require(_checkManager(), "T/OM"); // only manager
        _;
    }

    modifier saveDebt() {
        if (msg.sender != registry.triggerServer()) {
            _;
            return;
        }
        uint256 gasLeft = gasleft();
        _;
        gasLeft = gasLeft - gasleft();
        IPriceFeed ethPriceFeed = registry.ethPriceFeed();
        _debt += gasLeft * tx.gasprice
            / 10**uint256(ethPriceFeed.decimals())
            * 10**(registry.usdt()).decimals()
            * uint256(ethPriceFeed.latestAnswer())
            / 10**18;
    }

    modifier notExceededDebt(address token, uint256 amount) {
        if (token == address(registry.usdt())) {
            require(amount <= usdtAmount() - _debt, "T/DEB"); // debt exceeded balance
        }
        _;
    }

    function _checkManager() internal view returns(bool) {
        if (msg.sender == address(this)) {
            return true;
        }
        return managers[msg.sender];
    }

    function initialize(
        address _manager,
        bytes calldata whitelistMask,
        uint256 serviceMask,
        uint256 fundId
    ) external initializer {
        __ReentrancyGuard_init();
        _fundId = fundId;
        managers[_manager] = true;
        state = FundState.Opened;
        _setWhitelistMask(whitelistMask);
        _setServiceMask(serviceMask);

        if (address(registry.gmxRouter()) != address(0) && address(registry.gmxPositionRouter()) != address(0)) {
            registry.gmxRouter().approvePlugin(address(registry.gmxPositionRouter()));
        }
    }

    function setTradingScope(bytes memory whitelistMask, uint256 serviceMask) external {
        require(msg.sender == address(registry.tradeParamsUpdater()), "T/AD"); // access denied
        require(registry.feeder().fundTotalWithdrawals(_fundId) == 0, "T/UW"); // has unprocessed withdrawals
        _setWhitelistMask(whitelistMask);
        _setServiceMask(serviceMask);
    }

    function chargeDebt() external override {
        registry.usdt().safeApprove(address(registry.fees()), _debt);
        registry.fees().gatherEf(_fundId, _debt, address(registry.usdt()));
        _debt = 0;
    }

    function setFundId(uint256 fundId) external {
        require(registry.feeder().getFund(fundId).trade == address(this), "T/WID"); // wrong fund id
        _fundId = fundId;
    }

    function usdtAmount() public view returns(uint256) {
        return registry.usdt().balanceOf(address(this));
    }

    function status() public view returns(FundState) {
        return state;
    }

    function debt() public view returns(uint256) {
        return _debt;
    }

    function transferToFeeder(uint256 amount) external {
        require(msg.sender == address(registry.feeder()) || msg.sender == address(registry.interaction()), "T/AD"); // access denied
        registry.usdt().safeTransfer(address(registry.feeder()), amount);
    }

    function setState(FundState newState) external {
        require(msg.sender == address(registry.interaction()), "T/AD"); // access denied
        state = newState;
    }

    function multiSwap(bytes[] calldata data) external override {
        for (uint i; i < data.length; i++) {
            (, address tokenA, address tokenB, uint256 amountA, bytes memory payload) = abi.decode(data[i],
                (address, address, address, uint256, bytes)
            );
            swap(tokenA, tokenB, amountA, payload);
        }
    }

    function swap(
        address tokenA,
        address tokenB,
        uint256 amountA,
        bytes memory payload
    ) public override nonReentrant saveDebt notExceededDebt(tokenA, amountA) returns(uint256) {
        address usdt = address(registry.usdt());
        if (tokenB != usdt) {
            require(state == FundState.Opened, "T/FC"); // fund is closed
            _checkToken(tokenB);
            require(_checkManager(), "T/OM"); // only manager
        } else {
            require(_checkManager() || msg.sender == address(registry.triggerServer()), "T/OM"); // only manager
        }
        address swapper = registry.swapper();
        IERC20Upgradeable(tokenA).safeApprove(swapper, amountA);
        uint256 balanceStart = IERC20(tokenB).balanceOf(address(this));
        TryCall.call(swapper, payload);
        IERC20Upgradeable(tokenA).safeApprove(swapper, 0);
        uint256 diff = IERC20(tokenB).balanceOf(address(this)) - balanceStart;
        require(diff > 0, "T/TF");
        emit SwapSuccess(tokenA, tokenB, amountA, diff);
        return diff;
    }

    function setManager(address manager, bool enable) external onlyManager {
        managers[manager] = enable;

        if (enable) {
            emit ManagerAdded(manager);
        } else {
            emit ManagerRemoved(manager);
        }
    }

    function setAaveReferralCode(uint16 refCode) external override onlyManager {
        aaveReferralCode = refCode;
    }

    function setGmxRefCode(bytes32 _gmxRefCode) external override onlyManager {
        gmxRefCode = _gmxRefCode;
    }

    function aaveSupply(
        address _asset,
        uint256 _amount
    ) external override onlyManager notExceededDebt(_asset, _amount) {
        require(state == FundState.Opened, "T/FC"); // fund is closed
        require(_aaveEnabled, "T/FS"); // forbidden service
        require(_amount <= IERC20(_asset).balanceOf(address(this)), "T/ANA"); // not enough amount for staking in aave
        IERC20Upgradeable(_asset).safeApprove(address(registry.aavePool()), _amount);

        registry.aavePool().supply(
            _asset,
            _amount,
            address(this),
            aaveReferralCode
        );

        emit AaveSupply(_asset, _amount);
    }

    function aaveWithdraw(
        address _asset,
        uint256 _amount
    ) external override saveDebt {
        require(_checkManager() || msg.sender == address(registry.triggerServer()), "T/OM"); // only manager
        registry.aavePool().withdraw(_asset, _amount, address(this));

        emit AaveWithdraw(_asset, _amount);
    }

    function getAavePositionSizes(address[] calldata _assets) external view override
    returns (uint256[] memory assetPositions)
    {
        assetPositions = new uint256[](_assets.length);
        for (uint256 i; i < _assets.length; i++) {
            (uint256 currentATokenBalance, , , , , , , , ) = registry.aavePoolDataProvider()
                .getUserReserveData(_assets[i], address(this));
            assetPositions[i] = currentATokenBalance;
        }
    }

    function setCollateralAsset(address collateralAsset) public override onlyManager {
        if (collateralAsset == address(0)) {
            revert("T/ANNS"); // AAVE native not supported
        }
        registry.aavePool().setUserUseReserveAsCollateral(
            collateralAsset,
            true
        );
        emit AaveSetCollateralEvent(collateralAsset);
    }

    function getAssetsSizes(address[] calldata assets) external override view returns(uint256[] memory) {
        uint256[] memory sizes = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            sizes[i] = IERC20(assets[i]).balanceOf(address(this));
        }

        return sizes;
    }

    function gmxIncreasePosition(
        address tokenFrom,
        address indexToken,
        uint256 collateralAmount,
        uint256 usdDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee
    ) external payable override onlyManager notExceededDebt(tokenFrom, collateralAmount) {
        require(state == FundState.Opened, "T/FC"); // fund is closed
        require(_gmxEnabled, "T/FS"); // forbidden service
        _checkToken(indexToken);
        require(collateralAmount > 0, "T/NC"); // negative collateral
        
        IERC20Upgradeable(tokenFrom).safeApprove(address(registry.gmxRouter()), collateralAmount);
        address usdt = address(registry.usdt());
        address[] memory path;
        if (isLong) {
            if (indexToken != tokenFrom) {
                path = new address[](2);
                path[0] = tokenFrom;
                path[1] = indexToken;
            } else {
                path = new address[](1);
                path[0] = tokenFrom;
            }
        } else {
            if (tokenFrom != usdt) {
                path = new address[](2);
                path[0] = tokenFrom;
                path[1] = usdt;
            } else {
                path = new address[](1);
                path[0] = tokenFrom;
            }
        }
        registry.gmxPositionRouter().createIncreasePosition{value: msg.value}(
            path,
            indexToken,
            collateralAmount,
            0,
            usdDelta,
            isLong,
            acceptablePrice,
            executionFee,
            gmxRefCode,
            address(0)
        );

        emit GmxIncreasePosition(tokenFrom, indexToken, collateralAmount, usdDelta);
    }

    function gmxDecreasePosition(
        // always indexToken (LONG) or USDT (SHORT), therefore ignored
        address collateralToken,
        address indexToken,
        address receiveToken,
        uint256 collateralDelta,
        uint256 usdDelta,
        bool isLong,
        uint256 acceptablePrice, // usd amount [1e6]
        uint256 executionFee
    ) external payable saveDebt override {
        address usdt = address(registry.usdt());
        if (receiveToken != usdt) {
            require(_checkManager(), "T/OM"); // only manager
            _checkToken(receiveToken);
        } else {
            require(_checkManager() || msg.sender == address(registry.triggerServer()), "T/OM"); // only manager
        }
        require(acceptablePrice > 0, "T/DPN"); // decrease position for nothing

        address[] memory path;
        if (isLong) {
            path = new address[](2);
            path[0] = indexToken;
            path[1] = receiveToken;
        } else {
            if (receiveToken != usdt) {
                path = new address[](2);
                path[0] = usdt;
                path[1] = receiveToken;
            } else {
                path = new address[](1);
                path[0] = receiveToken;
            }
        }
        
        registry.gmxPositionRouter().createDecreasePosition{value: msg.value}(
            path,
            indexToken,
            collateralDelta,
            usdDelta,
            isLong,
            address(this),
            acceptablePrice,
            0,
            executionFee,
            false,
            address(0)
        );

        emit GmxDecreasePosition(collateralToken, indexToken, collateralDelta, usdDelta);
    }

    function _checkToken(address _token) internal view {
        (uint256 index, bool found) = registry.whitelist().getTokenIndex(_token);
        require(found, "T/TF"); // forbidden token
        uint256 maskIndex = index / 8;
        uint8 tokenIndex = uint8(index % 8);
        require(uint8(_whitelistMask[_whitelistMask.length - maskIndex - 1]) & (1 << tokenIndex) == (1 << tokenIndex), "T/TF");
    }

    function _setServiceMask(uint256 _serviceMask) private {
        _gmxEnabled = _serviceMask & 1 == 1;
        _aaveEnabled = _serviceMask & 1 << 1 == 1 << 1;
        emit AllowedServicesUpdated(_serviceMask);
    }

    function _setWhitelistMask(bytes memory whitelistMask) private {
        uint256 tokenCount = registry.whitelist().tokenCount();
        if (tokenCount < whitelistMask.length * 8) {
            // cannot be more than 1 byte longer than maximum capacity
            require(whitelistMask.length * 8 - tokenCount < 8, "T/UT");
            bytes1 lastByte = whitelistMask[0];
            // mask that allows all tokens of the last byte of whitelistMask
            bytes1 allowedTokensMask = bytes1(uint8((1 << tokenCount % 8) - 1));
            require(lastByte | allowedTokensMask == allowedTokensMask, "T/UT");
        }
        _whitelistMask = whitelistMask;
        emit WhitelistMaskUpdated(_whitelistMask);
    }

    function whitelistMask() external view returns (bytes memory) {
        return _whitelistMask;
    }

    function fundId() external view returns (uint256) {
        return _fundId;
    }

    function servicesEnabled() external view returns (bool[] memory) {
        bool[] memory result = new bool[](2);
        result[0] = _gmxEnabled;
        result[1] = _aaveEnabled;
        return result;
    }

    function isManager(address _address) public view returns (bool) {
        return managers[_address];
    }
}

