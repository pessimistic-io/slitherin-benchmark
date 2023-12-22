// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

import { Side } from "./IPool.sol";
import {IPoolHook} from "./IPoolHook.sol";
import {IMintableErc20} from "./IMintableErc20.sol";
import {IOracle} from "./IOracle.sol";

interface IReferralController {
    function updatePoint(address _trader, uint256 _value) external;
}

interface IPoolForHook {
    function oracle() external view returns (IOracle);
    function isStableCoin(address) external view returns (bool);
}

interface IFarm {
  function depositFor(uint256, uint256, address) external;
  function withdrawFrom(uint256, uint256, address) external;
}

contract PoolHook is OwnableUpgradeable, IPoolHook {
    using SafeERC20 for IERC20;

    uint256 constant MULTIPLIER_PRECISION = 100;
    uint256 constant MAX_MULTIPLIER = 5 * MULTIPLIER_PRECISION;
    uint8 constant esTokenDecimals = 18;
    uint256 constant VALUE_PRECISION = 1e30;

    address public mainPool;
    IMintableErc20 public esToken;

    uint256 public positionSizeMultiplier = 100;
    uint256 public swapSizeMultiplier = 100;
    uint256 public stableSwapSizeMultiplier = 5;
    IReferralController public referralController;
    IFarm public farm;
    uint256 public pid;
    mapping(address => bool) public pools;

    function initialize(address _esToken, address _pool, address _farm, uint256 _pid) external initializer {
        __Ownable_init();
        require(_esToken != address(0), "PoolHook:invalidAddress");
        esToken = IMintableErc20(_esToken);
        mainPool = _pool;
        farm = IFarm(_farm);
        pid = _pid;
        positionSizeMultiplier = 100;
        swapSizeMultiplier = 100;
        stableSwapSizeMultiplier = 5;
    }

    function validatePool(address sender) internal view {
        require(pools[sender], "PoolHook:!pool");
    }

    modifier onlyPool() {
        validatePool(msg.sender);
        _;
    }

    function postIncreasePosition(
        address _owner,
        address _indexToken,
        address _collateralToken,
        Side _side,
        bytes calldata _extradata
    ) external override onlyPool {
        address pool = msg.sender;
        (,, uint256 _feeValue) = abi.decode(_extradata, (uint256, uint256, uint256));
        _updateReferralData(_owner, _feeValue);
        emit PostIncreasePositionExecuted(pool, _owner, _indexToken, _collateralToken, _side, _extradata);
    }

    function postDecreasePosition(
        address _owner,
        address _indexToken,
        address _collateralToken,
        Side _side,
        bytes calldata _extradata
    ) external override onlyPool {
        (uint256 sizeChange, /* uint256 collateralValue */, uint256 _feeValue) =
            abi.decode(_extradata, (uint256, uint256, uint256));
        _handlePositionClosed(_owner, _indexToken, _collateralToken, _side, sizeChange);
        _updateReferralData(_owner, _feeValue);
        emit PostDecreasePositionExecuted(msg.sender, _owner, _indexToken, _collateralToken, _side, _extradata);
    }

    function postLiquidatePosition(
        address _owner,
        address _indexToken,
        address _collateralToken,
        Side _side,
        bytes calldata _extradata
    ) external override onlyPool {
        (uint256 sizeChange, /* uint256 collateralValue */ ) = abi.decode(_extradata, (uint256, uint256));
        _handlePositionClosed(_owner, _indexToken, _collateralToken, _side, sizeChange);

        emit PostLiquidatePositionExecuted(msg.sender, _owner, _indexToken, _collateralToken, _side, _extradata);
    }

    function postSwap(address _user, address _tokenIn, address _tokenOut, bytes calldata _data) external override onlyPool {
        address pool = msg.sender;
        (uint256 amountIn, /* uint256 amountOut */, uint256 swapFee, bytes memory extradata) =
            abi.decode(_data, (uint256, uint256, uint256, bytes));
        (address benificier) = extradata.length != 0 ? abi.decode(extradata, (address)) : (address(0));
        benificier = benificier == address(0) ? _user : benificier;
        uint256 priceIn = _getPrice(pool, _tokenIn, false);
        uint256 multiplier = _isStableSwap(pool, _tokenIn, _tokenOut) ? stableSwapSizeMultiplier : swapSizeMultiplier;
        uint256 esTokenAmount =
            (amountIn * priceIn * 10 ** esTokenDecimals) * multiplier / MULTIPLIER_PRECISION / VALUE_PRECISION;
        if (esTokenAmount != 0 && benificier != address(0)) {
            _mint(benificier, esTokenAmount);
        }

        _updateReferralData(benificier, swapFee * priceIn);
        emit PostSwapExecuted(msg.sender, _user, _tokenIn, _tokenOut, _data);
    }

    function _mint(address benificier, uint256 amount) internal {
        if (address(farm) != address(0)) {
            esToken.mint(address(this), amount);
            // stake to farm
            IERC20(address(esToken)).safeApprove(address(farm), amount);
            farm.depositFor(pid, amount, benificier);
        } else {
            esToken.mint(benificier, amount);
        }
    }

    // ========= Admin function ========

    function setReferralController(address _referralController) external onlyOwner {
        require(_referralController != address(0), "PoolHook: _referralController invalid");
        referralController = IReferralController(_referralController);
        emit ReferralControllerSet(_referralController);
    }
    function setFarm(address _farm, uint256 _pid) external onlyOwner {
        farm = IFarm(_farm);
        pid = _pid;
    }
    function addPool(address _pool) external onlyOwner {
        pools[_pool] = true;
    }

    function setMultipliers(
        uint256 _positionSizeMultiplier,
        uint256 _swapSizeMultiplier,
        uint256 _stableSwapSizeMultiplier
    ) external onlyOwner {
        require(_positionSizeMultiplier <= MAX_MULTIPLIER, "Multiplier too high");
        require(_swapSizeMultiplier <= MAX_MULTIPLIER, "Multiplier too high");
        require(_stableSwapSizeMultiplier <= MAX_MULTIPLIER, "Multiplier too high");
        positionSizeMultiplier = _positionSizeMultiplier;
        swapSizeMultiplier = _swapSizeMultiplier;
        stableSwapSizeMultiplier = _stableSwapSizeMultiplier;
        emit MultipliersSet(positionSizeMultiplier, swapSizeMultiplier, stableSwapSizeMultiplier);
    }

    // ========= Internal function ========

    function _updateReferralData(address _trader, uint256 _value) internal {
        if (address(referralController) != address(0)) {
            referralController.updatePoint(_trader, _value);
        }
    }

    function _handlePositionClosed(
        address _owner,
        address, /* _indexToken */
        address, /* _collateralToken */
        Side, /* _side */
        uint256 _sizeChange
    ) internal {
        uint256 esTokenAmount =
            (_sizeChange * 10 ** esTokenDecimals) * positionSizeMultiplier / MULTIPLIER_PRECISION / VALUE_PRECISION;

        if (esTokenAmount != 0) {
            _mint(_owner, esTokenAmount);
        }
    }

    function _getPrice(address pool, address token, bool max) internal view returns (uint256) {
        IOracle oracle = IPoolForHook(pool).oracle();
        return oracle.getPrice(token, max);
    }

    function _isStableSwap(address pool, address tokenIn, address tokenOut) internal view returns (bool) {
        IPoolForHook _pool = IPoolForHook(pool);
        return _pool.isStableCoin(tokenIn) && _pool.isStableCoin(tokenOut);
    }

    event ReferralControllerSet(address controller);
    event MultipliersSet(uint256 positionSizeMultiplier, uint256 swapSizeMultiplier, uint256 stableSwapSizeMultiplier);
}

