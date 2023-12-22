// SPDX-License-Identifier: ISC

pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ECDSA.sol";
import "./IERC20.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./Math.sol";
import "./ITrade.sol";
import "./FundState.sol";
import "./IPoolDataProvider.sol";
import "./IPool.sol";
import "./IGmxRouter.sol";
import "./IPositionRouter.sol";
import "./ITradeAccess.sol";

import "./console.sol";

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

    ITradeAccess public accessControl;
    uint256 _nonce;
    address signer;
    address zeroXExchangeProxy;
    uint256[50] _gap;
}

contract QHTrade is ITrade, QHTradeStorage, ReentrancyGuardUpgradeable {
    modifier onlyManager() {
        require(_checkManager(), "QHTrade/only-manager");
        _;
    }

    function _checkManager() internal view returns(bool) {
        if (msg.sender == address(this)) {
            return true;
        }
//        if (accessControl.userState(msg.sender) == 2) {
//            revert("QHTrade/banned");
//        }
//        if (accessControl.userState(msg.sender) != 1) {
            return managers[msg.sender];
//        }
//        return true;
    }

    function initialize(
        address _usdt,
        address _manager,
        address _trigger,
        address _feeder,
        address _interaction,
        address _poolDataProvider,
        address _lendingPool,
        address _tradeAccess,
        address _zeroXExchangeProxy
    ) external initializer {
        __ReentrancyGuard_init();

        interaction = _interaction;
        usdt = _usdt;
        signer = _trigger;

        managers[msg.sender] = true;
        managers[_manager] = true;
        managers[_trigger] = true;
        managers[_interaction] = true;
        managers[_feeder] = true;
        state = FundState.Opened;
        zeroXExchangeProxy = _zeroXExchangeProxy;

        aavePoolDataProvider = IPoolDataProvider(_poolDataProvider);
        aaveLendingPool = _lendingPool;

        accessControl = ITradeAccess(_tradeAccess);
    }

    function setGMXData(address _gmxRouter, address _gmxPositionRouter) external override {
        gmxRouter = IGmxRouter(_gmxRouter);
        gmxPositionRouter = IPositionRouter(_gmxPositionRouter);

        gmxRouter.approvePlugin(address(gmxPositionRouter));
    }

//    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
//
//    }

    function usdtAmount() public view returns(uint256) {
        return IERC20(usdt).balanceOf(address(this));
    }

    function status() public view returns(FundState) {
        return state;
    }

    function nonce() public override view returns(uint256) {
        return _nonce;
    }

    function transferToFeeder(uint256 amount, address feeder) external onlyManager {
//        require(msg.sender == interaction, "QHTrade/not-interaction");

        IERC20(usdt).transfer(feeder, amount);
    }

    function setUSDT(address newUSDT) external onlyManager {
        usdt = newUSDT;
    }

    function setState(FundState newState) external onlyManager {
        state = newState;
    }

    function multiSwap(
        bytes[] calldata data
    ) external override nonReentrant onlyManager {
        for (uint i; i < data.length; i++) {
            (, address tokenA, address tokenB, uint256 amountA, bytes memory payload) = abi.decode(data[i],
                (address, address, address, uint256, bytes)
            );
            _swap(tokenA, tokenB, amountA, payload);
        }
        _nonce += 1;
    }

    function swap(address swapper, address tokenA, address tokenB, uint256 amountA, bytes memory payload) public override nonReentrant onlyManager returns(uint256) {
        uint256 result = _swap(tokenA, tokenB, amountA, payload);
        _nonce += 1;
        return result;
    }

    function _swap(address tokenA, address tokenB, uint256 amountA, bytes memory payload) internal returns(uint256) {
        (bytes memory data, bytes memory signature) = abi.decode(payload, (bytes, bytes));
        bytes32 hash = keccak256(abi.encode(tokenA, tokenB, amountA, data, _nonce));
        require(ECDSA.recover(hash, signature) == signer, "QHTrade/signature-invalid");
        IERC20(tokenA).approve(zeroXExchangeProxy, amountA);
        uint256 balanceStart = IERC20(tokenB).balanceOf(address(this));

        if (tokenB != usdt) {
            require(state == FundState.Opened, "QHTrade/fund-is-closed");
        }

        (bool success, bytes memory returnBytes) = zeroXExchangeProxy.call(data);
        if (!success) {
            revert(_getRevertMsg(returnBytes));
        } else {
            uint256 diff = IERC20(tokenB).balanceOf(address(this)) - balanceStart;
            emit SwapSuccess(tokenA, tokenB, amountA, diff);
            return diff;
        }
    }

    function setManager(address manager, bool enable) external onlyManager {
        managers[manager] = enable;

        if (enable) {
            emit ManagerAdded(manager);
        } else {
            emit ManagerRemoved(manager);
        }
    }

    function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) return 'Transaction reverted silently';

        assembly {
        // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }

    ///////AAVE

    function setAaveReferralCode(uint16 refCode) external override onlyManager {
        aaveReferralCode = refCode;
    }

    function aaveSupply(
        address _asset,
        uint256 _amount,
        bytes memory payload
    ) external override onlyManager {
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

    function aaveBorrow(address borrowAsset, uint256 amount, uint16 borrowRate) public override onlyManager {
        revert("QHTrade/borrow-not-supported");
        if (borrowAsset == address(0x0)) {
            revert("QhTrade/aave-native-not-supported");
//            IDebtTokenBase(wavaxVariableDebtToken).approveDelegation(
//                address(wethGateway),
//                amount
//            );
//            wethGateway.borrowETH(
//                address(aaveLendingPool),
//                amount,
//                borrowRate,
//                aaveReferralCode
//            );
        } else {
            IPool(aaveLendingPool).borrow(
                address(borrowAsset),
                amount,
                borrowRate,
                aaveReferralCode,
                address(this)
            );
        }
        emit AaveBorrowEvent(borrowAsset, amount);
    }

    /**
     * @notice Repays a loan (partially or fully)
     * @dev using default Fixed rates
     */
    function aaveRepay(address asset, uint256 amount, uint16 borrowRate) public payable override onlyManager {
        revert("QHTrade/repay-not-supported");
        if (asset == address(0x0)) {
            revert("QhTrade/aave-native-not-supported");
//            require(
//                msg.value == amount,
//                "QHTrade::repay: mismatch of msg.value and amount"
//            );
//            wethGateway.repayETH{value: msg.value}(
//                address(aaveLendingPool),
//                amount,
//                borrowRate,
//                address(this)
//            );
        } else {
            IERC20(asset).approve(address(aaveLendingPool), amount);
            IPool(aaveLendingPool).repay(
                asset,
                amount,
                borrowRate,
                address(this)
            );
        }
        emit AaveRepayEvent(asset, amount);
    }

    function setCollateralAsset(address collateralAsset) public override onlyManager {
        if (collateralAsset == address(0)) {
            revert("QhTrade/aave-native-not-supported");
//            collateralAsset = wethGateway.getWETHAddress();
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
        uint256 executionFee,
        bytes memory signature
    ) external payable override onlyManager {
        bytes32 hash = keccak256(abi.encode(tokenFrom, indexToken, isLong, _nonce));
        require(ECDSA.recover(hash, signature) == signer, "QHTrade/signature-invalid");
        _nonce += 1;

        _gmxIncreasePosition(
            tokenFrom,
            indexToken,
            collateralAmount,
            usdDelta,
            isLong,
            acceptablePrice,
            executionFee
        );
    }

    function _gmxIncreasePosition(
        address tokenFrom,
        address indexToken,
        uint256 collateralAmount,
        uint256 usdDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee
    ) internal {
        require(indexToken != address(0), "QHTrade/gmxIncrease/invalid-index-token");
        require(collateralAmount > 0, "QHTrade/gmxIncrease/negative-amount");
        require(acceptablePrice > 0, "QHTrade/gmxIncrease/negative-acceptable-price");

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
        uint256 executionFee,
        bytes memory signature
    ) external payable override onlyManager {
        bytes32 hash = keccak256(abi.encode(receiveToken, _nonce));
        require(ECDSA.recover(hash, signature) == signer, "QHTrade/signature-invalid");
        _nonce += 1;

        _gmxDecreasePosition(
            collateralToken,
            indexToken,
            receiveToken,
            collateralDelta,
            usdDelta,
            isLong,
            acceptablePrice,
            executionFee
        );
    }

    function _gmxDecreasePosition(
        address collateralToken,
        address indexToken,
        address receiveToken,
        uint256 collateralDelta,
        uint256 usdDelta,
        bool isLong,
        uint256 acceptablePrice, // usd amount [1e6]
        uint256 executionFee
    ) internal {
        require(indexToken != address(0), "QHTrade/gmxDecrease/invalid-index-token");
        require(acceptablePrice > 0, "QHTrade/gmxDecrease/negative-acceptable-price");

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
}

