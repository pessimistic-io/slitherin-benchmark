// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./SafeMath.sol";
import "./SignedSafeMath.sol";
import "./ReentrancyGuard.sol";
import "./SafeCast.sol";
import "./IManager.sol";
import "./IPool.sol";
import "./TransferHelper.sol";
import "./IWrappedCoin.sol";

contract Vault is ReentrancyGuard {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SignedSafeMath for int8;
    using SafeCast for int256;
    using SafeCast for uint256;

    address public manager;
    address public WETH;

    // balance of pool, position fee and remove lp fee
    // pool => token => balance;
    // usdt of vault = usdt of poolBalances + usdt of exchangeFees + usdt of poolRmLpFeeBalances
    // pool array is in manager
    mapping(address => mapping(address => uint256)) public poolBalances;
    mapping(address => uint256) public poolRmLpFeeBalances;
    mapping(address => uint256) public exchangeFees; //pool => exchange fee

    event AddPoolBalance(address _pool, address _token, uint256 _amount);
    event DecreasePoolBalance(address _pool, address _token, uint256 _amount);
    event ReceiveRmLpFee(address _pool, uint256 _feeAmount);
    event ReceiveExchangeFee(address _pool, uint256 _feeAmount);
    event Transfer(address _pool, address _token, address _to, uint256 _amount);
    event CollectPoolRmFee(address _pool, address _token, address _to, uint256 _amount);
    event CollectExchangeFee(address _token, address _to, uint256 _amount);

    constructor(address _manager, address _WETH) {
        require(_manager != address(0) && _WETH != address(0), "Vault: invalid input address");
        manager = _manager;
        WETH = _WETH;
    }

    modifier onlyController() {
        require(IManager(manager).checkController(msg.sender), "Vault: Must be controller");
        _;
    }

    modifier onlyTreasurer() {
        require(IManager(manager).checkTreasurer(msg.sender), "Vault: Must be treasurer");
        _;
    }

    modifier onlyPool() {
        require(IManager(manager).checkPool(msg.sender), "Vault: Must be pool");
        _;
    }

    /// @notice transfer token to vault by pool , only pool can call
    /// @param _balance amount
    function addPoolBalance(uint256 _balance) external nonReentrant onlyPool {
        address _pool = msg.sender;
        address _token = IPool(_pool).getBaseAsset();
        poolBalances[_pool][_token] = poolBalances[_pool][_token].add(_balance);
        emit AddPoolBalance(_pool, _token, _balance);
    }

    /// @notice decrease pool balance by pool
    /// @param _pool pool address
    /// @param _token token address
    /// @param _balance amount
    function decreasePoolBalance(address _pool, address _token, uint256 _balance) internal {
        require(poolBalances[_pool][_token] >= _balance, "Vault: Insufficient balance");
        poolBalances[_pool][_token] = poolBalances[_pool][_token].sub(_balance);
        emit DecreasePoolBalance(_pool, _token, _balance);
    }


    /// @notice transfer fee to vault by pool , only pool can call
    /// @param _feeAmount fee amount
    function addPoolRmLpFeeBalance(uint256 _feeAmount) external nonReentrant onlyPool {
        address _pool = msg.sender;
        address _token = IPool(_pool).getBaseAsset();
        decreasePoolBalance(_pool, _token, _feeAmount);
        poolRmLpFeeBalances[_pool] = poolRmLpFeeBalances[_pool].add(_feeAmount);
        emit ReceiveRmLpFee(_pool, _feeAmount);
    }

    /// @notice transfer fee to vault by pool , only pool can call
    /// @param _feeAmount fee amount
    function addExchangeFeeBalance(uint256 _feeAmount) external nonReentrant onlyPool {
        address _pool = msg.sender;
        address _token = IPool(_pool).getBaseAsset();
        decreasePoolBalance(_pool, _token, _feeAmount);
        exchangeFees[_pool] = exchangeFees[_pool].add(_feeAmount);
        emit ReceiveExchangeFee(_pool, _feeAmount);
    }

    /// @notice transfer token out from vault by pool , only pool can call
    /// @param _to to address
    /// @param _amount amount
    /// @param isOutETH is out eth
    function transfer(address _to, uint256 _amount, bool isOutETH) external nonReentrant onlyPool {
        require(_to != address(this) && _to != address(0), "Vault: to address error");
        address _pool = msg.sender;
        address _token = IPool(_pool).getBaseAsset();
        decreasePoolBalance(_pool, _token, _amount);
        if (isOutETH) {
            require(_token == WETH, "Vault: token is not WETH");
            IWrappedCoin(_token).withdraw(_amount);
            TransferHelper.safeTransferETH(_to, _amount);
        } else {
            TransferHelper.safeTransfer(_token, _to, _amount);
        }
        emit Transfer(_pool, _token, _to, _amount);
    }

    /// @notice transfer remove liquidity fee out
    /// @param _pool pool address
    /// @param to address
    function collectPoolRmFee(address _pool, address to) external nonReentrant onlyTreasurer {
        require(poolRmLpFeeBalances[_pool] > 0, "Vault:remove liquidity fee balance is 0");
        require(to != address(this) && to != address(0), "Vault: to address is invalid");
        address _token = IPool(_pool).getBaseAsset();
        uint256 _fee = poolRmLpFeeBalances[_pool];
        poolRmLpFeeBalances[_pool] = 0;
        if (_token == WETH) {
            IWrappedCoin(_token).withdraw(_fee);
            TransferHelper.safeTransferETH(to, _fee);
        } else {
            TransferHelper.safeTransfer(_token, to, _fee);
        }
        emit CollectPoolRmFee(_pool, _token, to, _fee);
    }

    /// @notice transfer remove liquidity fee out
    /// @param _pool pool address
    /// @param to address
    function collectExchangeFee(address _pool, address to) external nonReentrant onlyTreasurer {
        require(exchangeFees[_pool] > 0, "Vault:exchange fee balance is 0");
        require(to != address(this) && to != address(0), "Vault: to address is invalid");
        address _token = IPool(_pool).getBaseAsset();
        uint256 _fee = exchangeFees[_pool];
        exchangeFees[_pool] = 0;
        if (_token == WETH) {
            IWrappedCoin(_token).withdraw(_fee);
            TransferHelper.safeTransferETH(to, _fee);
        } else {
            TransferHelper.safeTransfer(_token, to, _fee);
        }
        emit CollectExchangeFee(_token, to, _fee);
    }

    fallback() external payable {
    }
}

