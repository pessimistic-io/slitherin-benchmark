// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Initializable.sol";
import "./IAdapter.sol";
import "./IDefiEdgeStrategy.sol";
import "./IDefiEdgeManager.sol";
import "./IPancakeV3Pool.sol";

contract DeFiEdgeAdapterInitializable is IAdapter, Initializable, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    string public constant PROTOCOL = "DeFiEdge";
    uint8 public constant VERSION = 1;
    uint256 public constant PRECISION = 1e18;

    address public wrapper;
    address public vault;
    address public token0;
    address public token1;
    address public lpToken;

    event SetWrapper(address indexed oldWrapper, address indexed newWrapper);
    event SetVault(address indexed oldVault, address indexed newVault, address token0, address token1, address lpToken);
    event ApproveToken(IERC20 indexed _token, address indexed _spender, uint256 _amount);
    event TransferToken(IERC20 indexed _token, address indexed _recipient, uint256 _amount);

    modifier onlyWrapper() {
        require(wrapper == msg.sender, "onlyWrapper: caller is not the wrapper");
        _;
    }

    /// * INIT *
    constructor() {}

    function initialize(
        address _wrapper,
        address _vault,
        address _admin
    ) external initializer {
        require(_wrapper != address(0) && _vault != address(0) && _admin != address(0), "initialize: address cant be zero");
        wrapper = _wrapper;
        vault = _vault;
        token0 = IPancakeV3Pool(pool()).token0();
        token1 = IPancakeV3Pool(pool()).token1();
        lpToken = vault;
        transferOwnership(_admin);
    }

    receive() external payable {}
    fallback() external {}

    /// * GETTER *
    function totalSupply(
    ) public view returns(uint256) {
        return IDefiEdgeStrategy(vault).totalSupply();
    }

    function tokenPerShare(
    ) public view returns(uint256 _token0PerShare, uint256 _token1PerShare) {
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ > 0) {
            (uint256 amount0, uint256 amount1, , ) = IDefiEdgeStrategy(vault).getAUMWithFees(false);
            _token0PerShare = amount0 * PRECISION / totalSupply_;
            _token1PerShare = amount1 * PRECISION / totalSupply_;
        } else {
            return (0, 0);
        }
    }

    function pool(
    ) public view returns(address) {
        return IDefiEdgeStrategy(vault).pool();
    }

    function manager(
    ) public view returns(address) {
        return IDefiEdgeStrategy(vault).manager();
    }

    function managerFee(
    ) public view returns(uint256) {
        return IDefiEdgeManager(manager()).managementFeeRate();
    }

    /// * OWNER *
    function setWrapper(
        address _newWrapper
    ) external onlyOwner {
        require(_newWrapper != address(0), "setWrapper: address cant be zero");

        address oldWrapper = wrapper;

        wrapper = _newWrapper;

        emit SetWrapper(oldWrapper, wrapper);
    }

    function setVault(
        address _newVault
    ) external onlyOwner {
        require(_newVault != address(0), "setVault: address cant be zero");

        address oldVault = vault;

        vault = _newVault;

        token0 = IPancakeV3Pool(pool()).token0();
        token1 = IPancakeV3Pool(pool()).token1();
        lpToken = vault;

        emit SetVault(oldVault, vault, token0, token1, lpToken);
    }

    function approveToken(
        IERC20 _token, 
        address _spender, 
        uint256 _amount
    ) external onlyOwner {
        _token.approve(_spender, _amount);

        emit ApproveToken(_token, _spender, _amount);
    }

    function transferToken(
        IERC20 _token, 
        address _recipient, 
        uint256 _amount
    ) external onlyOwner {
        uint256 balance = _token.balanceOf(address(this));
        if (balance < _amount) {
            _amount = balance;
        }

        _token.safeTransfer(_recipient, _amount);

        emit TransferToken(_token, _recipient, _amount);
    }

    /// * VAULT *
    function deposit(
        uint256 _amount0,
        uint256 _amount1,
        address _user,
        bytes calldata _data
    ) external nonReentrant onlyWrapper returns(uint256 _share) {
        IERC20(token0).safeTransferFrom(wrapper, address(this), _amount0);
        IERC20(token1).safeTransferFrom(wrapper, address(this), _amount1);
        IERC20(token0).forceApprove(vault, _amount0);
        IERC20(token1).forceApprove(vault, _amount1);
        
        uint256 amount0Used;
        uint256 amount1Used;
        if (_data.length > 0) {
            (uint256 amount0Min, uint256 amount1Min, uint256 minShare) = abi.decode(_data, (uint256, uint256, uint256));
            (amount0Used, amount1Used, _share) = IDefiEdgeStrategy(vault).mint(_amount0, _amount1, amount0Min, amount1Min, minShare);
        } else {
            (amount0Used, amount1Used, _share) = IDefiEdgeStrategy(vault).mint(_amount0, _amount1, 0, 0, 0);
        }

        require(_amount0 >= amount0Used && _amount1 >= amount1Used, "deposit: incorrect token amount");

        IERC20(lpToken).safeTransfer(wrapper, _share);

        if (IERC20(token0).balanceOf(address(this)) > 0) IERC20(token0).safeTransfer(_user, IERC20(token0).balanceOf(address(this)));
        if (IERC20(token1).balanceOf(address(this)) > 0) IERC20(token1).safeTransfer(_user, IERC20(token1).balanceOf(address(this)));
    }

    function withdraw(
        uint256 _share,
        address _user,
        bytes calldata _data
    ) external nonReentrant onlyWrapper returns(uint256 _amount0, uint256 _amount1) {
        IERC20(lpToken).safeTransferFrom(wrapper, address(this), _share);
        IERC20(lpToken).forceApprove(vault, _share);

        if (_data.length > 0) {
            (uint256 amount0Min, uint256 amount1Min) = abi.decode(_data, (uint256, uint256));
            (_amount0, _amount1) = IDefiEdgeStrategy(vault).burn(_share, amount0Min, amount1Min);
        } else {
            (_amount0, _amount1) = IDefiEdgeStrategy(vault).burn(_share, 0, 0);
        }

        IERC20(token0).safeTransfer(_user, _amount0);
        IERC20(token1).safeTransfer(_user, _amount1);

        if (IERC20(lpToken).balanceOf(address(this)) > 0) IERC20(lpToken).safeTransfer(_user, IERC20(lpToken).balanceOf(address(this)));
    }
}
