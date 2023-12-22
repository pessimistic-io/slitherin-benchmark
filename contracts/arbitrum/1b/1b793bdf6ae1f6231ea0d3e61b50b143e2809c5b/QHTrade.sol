// SPDX-License-Identifier: ISC

pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./IERC20.sol";

import "./Math.sol";
import "./ITrade.sol";
import "./IPoolDataProvider.sol";
import "./IPool.sol";
import "./IGmxRouter.sol";
import "./IPositionRouter.sol";

contract QHTrade is ITrade, Initializable {

    mapping(address => bool) public managers;

    address public interaction;
    address public usdt;

    address public aaveLendingPool;
    IPoolDataProvider aavePoolDataProvider;
    uint16 public aaveReferralCode;

    IGmxRouter public gmxRouter;
    IPositionRouter public gmxPositionRouter;
    bytes32 public gmxRefCode;

    modifier onlyManager() {
        require(managers[msg.sender], "QHTrade/only-manager");
        _;
    }

    function initialize(
        address _usdt,
        address _manager,
        address _trigger,
        address _interaction,
        address _poolDataProvider,
        address _lendingPool
    ) external initializer {
        interaction = _interaction;
        usdt = _usdt;

        managers[msg.sender] = true;
        managers[_manager] = true;
        managers[_trigger] = true;

        aavePoolDataProvider = IPoolDataProvider(_poolDataProvider);
        aaveLendingPool = _lendingPool;
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

    function transferToFeeder(uint256 amount, address feeder) external {
//        require(msg.sender == interaction, "QHTrade/not-interaction");

        IERC20(usdt).transfer(feeder, amount);
    }

    function setUSDT(address newUSDT) external onlyManager {
        usdt = newUSDT;
    }

    function swap(address swapper,
        address tokenA,
        address tokenB,
        uint256 amountA,
        bytes memory payload
    ) public override onlyManager returns(uint256) {
        IERC20(tokenA).approve(swapper, type(uint256).max);
        uint256 balanceStart = IERC20(tokenB).balanceOf(address(this));

        (bytes32 hash, bytes memory sig, bytes memory data) = abi.decode(
            payload, (bytes32, bytes, bytes)
        );
//        require(hash == keccak256(data), "QHTrade/hash-mismatch");
        address signer = ecrecovery(hash, sig);
        require(managers[signer], "QHTrade/signature-invalid");

        (bool success, bytes memory returnBytes) = swapper.call(data);
        if (!success) {
            revert(_getRevertMsg(returnBytes));
        } else {
            uint256 diff = IERC20(tokenB).balanceOf(address(this)) - balanceStart;
            emit SwapSuccess(tokenA, tokenB, amountA, diff);
            return diff;
        }
    }

    function setManager(address manager, bool enable) external {
        managers[manager] = enable;

        if (enable) {
            emit ManagerAdded(manager);
        } else {
            emit ManagerRemoved(manager);
        }
    }

    function ecrecovery(bytes32 hash, bytes memory sig) private pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        if (sig.length != 65) {
            return address(0);
        }

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := and(mload(add(sig, 65)), 255)
        }

        if (v < 27) {
            v += 27;
        }

        if (v != 27 && v != 28) {
            return address(0);
        }

        return ecrecover(hash, v, r, s);
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

    function aaveSupply(address _asset, uint256 _amount) external override onlyManager {
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

    function aaveWithdraw(address _asset, uint256 _amount) external override onlyManager {
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

    function gmxMinExecutionFee() external view override returns(uint256) {
        return gmxPositionRouter.minExecutionFee();
    }

    function gmxIncreasePosition(
        address collateralToken,
        address indexToken,
        uint256 collateralAmount,
        uint256 usdDelta,
        bool isLong,
        uint256 acceptablePrice
    ) external payable override onlyManager {
        require(collateralToken != address(0), "QHTrade/gmxIncrease/invalid-token");
        require(indexToken != address(0), "QHTrade/gmxIncrease/invalid-index-token");
        require(collateralAmount > 0, "QHTrade/gmxIncrease/negative-amount");
        require(acceptablePrice > 0, "QHTrade/gmxIncrease/negative-acceptable-price");

        IERC20(collateralToken).approve(address(gmxRouter), collateralAmount);

        address[] memory path;
        if (indexToken != collateralToken) {
            path = new address[](2);
            path[0] = collateralToken;
            path[1] = indexToken;
        } else {
            path = new address[](1);
            path[0] = collateralToken;
        }
        gmxPositionRouter.createIncreasePosition{value: msg.value}(
            path,
            indexToken,
            collateralAmount,
            0,
            usdDelta,
            isLong,
            acceptablePrice,
            gmxPositionRouter.minExecutionFee(),
            gmxRefCode,
            address(0)
        );

        emit GmxIncreasePosition(collateralToken, indexToken, collateralAmount, usdDelta);
    }

    function gmxDecreasePosition(
        address collateralToken,
        address indexToken,
        address receiveToken,
        uint256 collateralDelta, //usd amount [1e6]
        uint256 usdDelta,
        bool isLong,
        uint256 acceptablePrice // usd amount [1e6]
    ) external payable override onlyManager {
        require(collateralToken != address(0), "QHTrade/gmxDecrease/invalid-token");
        require(indexToken != address(0), "QHTrade/gmxDecrease/invalid-index-token");
//        require(collateralDelta > 0, "QHTrade/gmxDecrease/negative-amount");
        require(acceptablePrice > 0, "QHTrade/gmxDecrease/negative-acceptable-price");

        address[] memory path;
        if (indexToken != collateralToken) {
            path = new address[](2);
            path[0] = collateralToken;
            path[1] = receiveToken;
        } else {
            path = new address[](1);
            path[0] = collateralToken;
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
            gmxPositionRouter.minExecutionFee(),
            false,
            address(0)
        );

        emit GmxDecreasePosition(collateralToken, indexToken, collateralDelta, usdDelta);
    }
}

