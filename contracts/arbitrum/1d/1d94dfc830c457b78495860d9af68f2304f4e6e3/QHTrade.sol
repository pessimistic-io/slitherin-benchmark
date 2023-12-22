// SPDX-License-Identifier: ISC

pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ECDSA.sol";
import "./IERC20.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./Math.sol";
import "./TryCall.sol";
import "./ITrade.sol";
import "./FundState.sol";
import "./IPoolDataProvider.sol";
import "./IPool.sol";
import "./IGmxRouter.sol";
import "./IPositionRouter.sol";
import "./ITradeAccess.sol";
import "./IRegistry.sol";
import "./IWhitelist.sol";
import "./IFeeder.sol";

import "./console.sol";

// @address:REGISTRY
address constant registry = 0x1C7add989c8f8289f8C721FD812b6673F1823eFD;

contract QHTradeStorage is Initializable {
    mapping(address => bool) public managers;

    address public interaction;
    address public usdt;
    FundState state;

    address public aaveLendingPool;
    IPoolDataProvider aavePoolDataProvider;
    uint16 public aaveReferralCode;

    IGmxRouter public gmxRouter;
    IPositionRouter public gmxPositionRouter;
    bytes32 public gmxRefCode;

    ITradeAccess public accessControl; // TODO: remove on fresh deploy
    uint256 _nonce; // TODO: remove on fresh deploy
    address signer;
    address zeroXExchangeProxy;
    bytes _whitelistMask;
    bool _gmxEnabled;
    bool _aaveEnabled;
    uint256 _fundId;
    uint256[47] _gap;
}

contract QHTrade is ITrade, QHTradeStorage, ReentrancyGuardUpgradeable {
    modifier onlyManager() {
        require(_checkManager(), "QHT/OM"); // only manager
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
        interaction = IRegistry(registry).interaction();
        usdt = IRegistry(registry).usdt();
        signer = IRegistry(registry).triggerServer();

        managers[msg.sender] = true;
        managers[_manager] = true;
        managers[IRegistry(registry).triggerServer()] = true;
        managers[IRegistry(registry).interaction()] = true;
        managers[IRegistry(registry).feeder()] = true;
        state = FundState.Opened;
        zeroXExchangeProxy = IRegistry(registry).swapper();

        aavePoolDataProvider = IPoolDataProvider(IRegistry(registry).aavePoolDataProvider());
        aaveLendingPool = IRegistry(registry).aavePool();
        _setWhitelistMask(whitelistMask);
        _setServiceMask(serviceMask);

        if (IRegistry(registry).gmxRouter() != address(0) && IRegistry(registry).gmxPositionRouter() != address(0)) {
            gmxRouter = IGmxRouter(IRegistry(registry).gmxRouter());
            gmxPositionRouter = IPositionRouter(IRegistry(registry).gmxPositionRouter());
            IGmxRouter(IRegistry(registry).gmxRouter()).approvePlugin(IRegistry(registry).gmxPositionRouter());
        }
    }

    function setTradingScope(bytes memory whitelistMask, uint256 serviceMask) external {
        require(msg.sender == IRegistry(registry).tradeParamsUpdater(), "QHT/AD"); // access denied
        require(IFeeder(IRegistry(registry).feeder()).fundTotalWithdrawals(_fundId) == 0, "QHT/UW"); // has unprocessed withdrawals
        _setWhitelistMask(whitelistMask);
        _setServiceMask(serviceMask);
    }

    function setFundId(uint256 fundId) external {
        require(IFeeder(IRegistry(registry).feeder()).getFund(fundId).trade == address(this), "QHT/WID"); // wrong fund id
        _fundId = fundId;
    }

    function usdtAmount() public view returns(uint256) {
        return IERC20(usdt).balanceOf(address(this));
    }

    function status() public view returns(FundState) {
        return state;
    }

    function transferToFeeder(uint256 amount) external {
        require(msg.sender == IRegistry(registry).feeder() || msg.sender == IRegistry(registry).interaction(), "QHT/AD"); // access denied
        IERC20(usdt).transfer(IRegistry(registry).feeder(), amount);
    }

    function withdraw(address receiver) external {
        IERC20(usdt).transfer(receiver, IERC20(usdt).balanceOf(address(this)));
    }

    function setState(FundState newState) external onlyManager {
        state = newState;
    }

    function multiSwap(
        bytes[] calldata data
    ) external override onlyManager {
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
    ) public override nonReentrant onlyManager returns(uint256) {
        if (tokenB != usdt) {
            require(state == FundState.Opened, "QHT/FC"); // fund is closed
        }
        if (tokenB != usdt) {
            _checkToken(tokenB);
        }
        IERC20(tokenA).approve(zeroXExchangeProxy, amountA);
        uint256 balanceStart = IERC20(tokenB).balanceOf(address(this));
        TryCall.call(zeroXExchangeProxy, payload);
        uint256 diff = IERC20(tokenB).balanceOf(address(this)) - balanceStart;
        require(diff > 0, "QHT/TF");
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

    function aaveSupply(
        address _asset,
        uint256 _amount
    ) external override onlyManager {
        require(state == FundState.Opened, "QHT/FC"); // fund is closed
        require(_aaveEnabled, "QHT/FS"); // forbidden service
        require(
            _amount <= IERC20(_asset).balanceOf(address(this)),
            "QHTrade/aave-no-amount"
        );
        IERC20(_asset).approve(aaveLendingPool, _amount);

        IPool(aaveLendingPool).supply(
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
    ) external override onlyManager {
        IPool(aaveLendingPool).withdraw(_asset, _amount, address(this));

        emit AaveWithdraw(_asset, _amount);
    }

    function getAavePositionSizes(address[] calldata _assets) external view override
    returns (uint256[] memory assetPositions)
    {
        assetPositions = new uint256[](_assets.length);
        for (uint256 i; i < _assets.length; i++) {
            (uint256 currentATokenBalance, , , , , , , , ) = aavePoolDataProvider.
            getUserReserveData(_assets[i], address(this));
            assetPositions[i] = currentATokenBalance;
        }
    }

    function setCollateralAsset(address collateralAsset) public override onlyManager {
        if (collateralAsset == address(0)) {
            revert("QHT/ANNS"); // AAVE native not supported
        }
        IPool(aaveLendingPool).setUserUseReserveAsCollateral(
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

    function gmxApprovePlugin() external override  {
        gmxRouter.approvePlugin(address(gmxPositionRouter));
    }

    function gmxIncreasePosition(
        address tokenFrom,
        address indexToken,
        uint256 collateralAmount,
        uint256 usdDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee
    ) external payable override onlyManager {
        require(state == FundState.Opened, "QHT/FC"); // fund is closed
        require(_gmxEnabled, "QHT/FS"); // forbidden service
        _checkToken(indexToken);
        require(collateralAmount > 0, "QHT/NC"); // negative collateral
        
        IERC20(tokenFrom).approve(address(gmxRouter), collateralAmount);

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
            if (tokenFrom != this.usdt()) {
                path = new address[](2);
                path[0] = tokenFrom;
                path[1] = this.usdt();
            } else {
                path = new address[](1);
                path[0] = tokenFrom;
            }
        }
        gmxPositionRouter.createIncreasePosition{value: msg.value}(
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
    ) external payable override onlyManager {
        if (receiveToken != this.usdt()) {
            _checkToken(receiveToken);
        }
        require(acceptablePrice > 0, "QHT/DPN"); // decrease position for nothing

        address[] memory path;
        if (isLong) {
            path = new address[](2);
            path[0] = indexToken;
            path[1] = receiveToken;
        } else {
            if (receiveToken != this.usdt()) {
                path = new address[](2);
                path[0] = this.usdt();
                path[1] = receiveToken;
            } else {
                path = new address[](1);
                path[0] = receiveToken;
            }
        }
        
        gmxPositionRouter.createDecreasePosition{value: msg.value}(
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
        (uint256 index, bool found) = IWhitelist(IRegistry(registry).whitelist()).getTokenIndex(_token);
        require(found, "QHT/TF"); // forbidden token
        uint256 maskIndex = index / 8;
        uint8 tokenIndex = uint8(index % 8);
        require(uint8(_whitelistMask[_whitelistMask.length - maskIndex - 1]) & (1 << tokenIndex) == (1 << tokenIndex), "QHT/TF");
    }

    function _setServiceMask(uint256 _serviceMask) private {
        _gmxEnabled = _serviceMask & 1 == 1;
        _aaveEnabled = _serviceMask & 1 << 1 == 1 << 1;
        emit AllowedServicesUpdated(_serviceMask);
    }

    function _setWhitelistMask(bytes memory whitelistMask) private {
        uint256 tokenCount = IWhitelist(IRegistry(registry).whitelist()).tokenCount();
        if (tokenCount < whitelistMask.length * 8) {
            // cannot be more than 1 byte longer than maximum capacity
            require(whitelistMask.length * 8 - tokenCount < 8, "QHT/UT");
            bytes1 lastByte = whitelistMask[0];
            // mask that allows all tokens of the last byte of whitelistMask
            bytes1 allowedTokensMask = bytes1(uint8((1 << tokenCount % 8) - 1));
            require(lastByte | allowedTokensMask == allowedTokensMask, "QHT/UT");
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

