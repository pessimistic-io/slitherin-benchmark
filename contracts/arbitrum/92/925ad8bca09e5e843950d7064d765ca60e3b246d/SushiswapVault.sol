// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./Pausable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./Babylonian.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";

import "./IMiniChefV2.sol";
import "./IRewarder.sol";
import "./IVault.sol";
import "./ERC20.sol";


contract SushiVault is IVault, ERC20, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    uint256 public constant FEE = 250;
    uint256 public constant REMAINING_AMOUNT = 9500;
    address public constant miniChef =
        0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3;
    address public constant router = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address public constant sushi = 0xd4d42F0b6DEF4CE0383636770eF773390d85c61A;
    address public constant treasury0 =
        0x723a2e7E926A8AFc5871B8962728Cb464f698A54;
    address public constant treasury1 =
        0x723a2e7E926A8AFc5871B8962728Cb464f698A54;
    address public immutable override asset;
    address public immutable factory;
    uint256 public immutable poolId;
    address[] public route;

    constructor(
        string memory _name,
        string memory _symbol,
        address _asset,
        uint256 _poolId,
        address[] memory _route,
        address[] memory _approveToken,
        address _factory
    ) public ERC20(_name, _symbol, 18) {
        asset = _asset;

        poolId = _poolId;

        route = _route;

        factory = _factory;

        IERC20(_asset).safeApprove(miniChef, uint256(type(uint256).max));
        for (uint256 i; i < _approveToken.length; ++i) {
            IERC20(_approveToken[i]).safeApprove(
                router,
                uint256(type(uint256).max)
            );
        }
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "!Factory");
        _;
    }

    function deposit(
        uint256 amount,
        address receiver
    ) external override whenNotPaused {
        require(amount > 0, "Zero Amount");
        address _miniChef = miniChef;
        uint256 _poolId = poolId;
        address _asset = asset;
        uint256 shares = calculateShareAmount(amount, _miniChef, _poolId);
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), amount);
        IMiniChefV2(_miniChef).deposit(_poolId, amount, address(this));
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, amount, shares);
    }

    function withdraw(
        uint256 amount,
        address receiver
    ) external override returns (uint256 shares) {
        require(amount > 0, "ZA");
        address _miniChef = miniChef;
        uint256 _poolId = poolId;
        shares = calculateWithdrawShare(amount, _miniChef, _poolId);
        require(shares > 0, "Zero Shares");
        IMiniChefV2(_miniChef).withdrawAndHarvest(
            _poolId,
            shares,
            address(this)
        );
        _handleReward(_miniChef, _poolId, receiver);
        IERC20(asset).safeTransfer(
            receiver,
            IERC20(asset).balanceOf(address(this))
        );
        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, receiver, amount, shares);
    }

    function harvest() external override {
        address _miniChef = miniChef;
        uint256 _poolId = poolId;
        address _asset = asset;
        address reward = IMiniChefV2(_miniChef).rewarder(_poolId);
        IMiniChefV2(_miniChef).harvest(_poolId, address(this));
        uint256 amount = reward == address(0) //ETH-DAI   ETH-SUSHI ETH-MAGIC MAGIC-SUSHI
            ? _handleSushiToken(_asset)
            : _handleRewardToken(_asset, IRewarder(reward).rewardToken());
        IMiniChefV2(_miniChef).deposit(_poolId, amount, address(this));
    }

    function pauseAndWithdraw() external override whenNotPaused onlyFactory {
        _pause();
        IMiniChefV2(miniChef).emergencyWithdraw(poolId, address(this));
    }

    function unpauseAndDeposit() external override whenPaused onlyFactory {
        _unpause();
        address _miniChef = miniChef;
        address _asset = asset;
        IMiniChefV2(_miniChef).deposit(
            poolId,
            IERC20(_asset).balanceOf(address(this)),
            address(this)
        );
    }

    function emergencyExit(
        uint256 amount,
        address receiver
    ) external override whenPaused {
        address _asset = asset;
        uint256 assetAmount = IERC20(_asset).balanceOf(address(this));
        require(assetAmount > 0, "Zero Asset Amount");
        require(amount > 0, "Zero Amount");
        uint256 shares = amount.mul(totalSupply).div(assetAmount);
        _burn(msg.sender, amount);
        IERC20(_asset).safeTransfer(receiver, shares);
        emit Withdraw(msg.sender, receiver, amount, shares);
    }

    function pauseVault() external override onlyFactory {
        _pause();
    }

    function unpauseVault() external override onlyFactory {
        _unpause();
    }

    function changeAllowance(
        address token,
        address to
    ) external override onlyFactory {
        IERC20(token).allowance(address(this), to) == 0
            ? IERC20(token).safeApprove(to, uint256(type(uint256).max))
            : IERC20(token).safeApprove(to, 0);
    }

    function _handleReward(
        address _miniChef,
        uint256 _poolId,
        address receiver
    ) internal {
        address rewardToken;
        uint256 rewardBal;
        uint256 sushiBal;
        if (IMiniChefV2(_miniChef).rewarder(_poolId) != address(0)) {
            rewardToken = IRewarder(IMiniChefV2(_miniChef).rewarder(_poolId))
                .rewardToken();
            rewardBal = IERC20(rewardToken).balanceOf(address(this));
            sushiBal = IERC20(sushi).balanceOf(address(this));
            if (rewardBal > 0 && sushiBal > 0) {
                _swap(sushiBal, route, router);
                IERC20(rewardToken).safeTransfer(
                    receiver,
                    _chargeFees(rewardToken, rewardBal)
                );
            } else if (rewardBal > 0) {
                IERC20(rewardToken).safeTransfer(
                    receiver,
                    _chargeFees(rewardToken, rewardBal)
                );
            }
        }
        sushiBal = IERC20(sushi).balanceOf(address(this));
        if (sushiBal > 0) {
            IERC20(sushi).safeTransfer(receiver, _chargeFees(sushi, sushiBal));
        }
    }

    function _handleSushiToken(address _asset) internal returns (uint256) {
        address _sushi = sushi;
        address _router = router;
        address lpToken0 = IUniswapV2Pair(_asset).token0();
        address lpToken1 = IUniswapV2Pair(_asset).token1();
        require(
            IERC20(_sushi).balanceOf(address(this)) > 0,
            "Zero Harvest Amount"
        );

        if (_sushi != lpToken0 && _sushi != lpToken1) {
            //and sushi not match with anyone of token in LP ETH-DAI
            _swap(IERC20(_sushi).balanceOf(address(this)), route, _router); //route sushi-to-lp1/lp0
        }
        _arrangeAddliquidityObject(
            _asset,
            route.length > 0 ? route[route.length - 1] : _sushi, //route[route.length - 1],//or sushi
            lpToken0,
            lpToken1,
            _router
        );
        return _addLiquidity(lpToken0, lpToken1, _router);
    }

    function _handleRewardToken(
        address _asset,
        address reward
    ) internal returns (uint256) {
        address _sushi = sushi;
        address _router = router;
        address lpToken0 = IUniswapV2Pair(_asset).token0();
        address lpToken1 = IUniswapV2Pair(_asset).token1();
        uint256 sushiBal = IERC20(_sushi).balanceOf(address(this));
        if (sushiBal > 0) {
            _swap(sushiBal, route, _router); //convert sushi to reward token
        } else {
            require(
                IERC20(reward).balanceOf(address(this)) > 0,
                "Zero Harvest Amount"
            );
        }
        _arrangeAddliquidityObject(_asset, reward, lpToken0, lpToken1, _router);
        return _addLiquidity(lpToken0, lpToken1, _router);
    }

    function _arrangeAddliquidityObject(
        address _asset,
        address token,
        address lpToken0,
        address lpToken1,
        address _router
    ) internal {
        (uint112 res0, uint112 res1, ) = IUniswapV2Pair(_asset).getReserves();
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = token == lpToken0 ? lpToken1 : lpToken0;
        lpToken0 == token
            ? _swap(
                _calculateSwapInAmount(
                    res0,
                    _chargeFees(token, IERC20(token).balanceOf(address(this)))
                ),
                path,
                _router
            )
            : _swap(
                _calculateSwapInAmount(
                    res1,
                    _chargeFees(token, IERC20(token).balanceOf(address(this)))
                ),
                path,
                _router
            );
    }

    function _swap(
        uint256 amount,
        address[] memory _route,
        address _router
    ) internal {
        IUniswapV2Router02(_router).swapExactTokensForTokens(
            amount,
            0,
            _route,
            address(this),
            block.timestamp
        );
    }

    function _addLiquidity(
        address lpToken0,
        address lpToken1,
        address _router
    ) internal returns (uint256 lpAmount) {
        uint256 token0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 token1Bal = IERC20(lpToken1).balanceOf(address(this));
        if (token0Bal > 0 && token1Bal > 0) {
            (, , lpAmount) = IUniswapV2Router02(_router).addLiquidity(
                lpToken0,
                lpToken1,
                token0Bal,
                token1Bal,
                1,
                1,
                address(this),
                block.timestamp
            );
            uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
            uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
            if (lp0Bal > 0) {
                IERC20(lpToken0).safeTransfer(treasury0, lp0Bal);
            }
            if (lp1Bal > 0) {
                IERC20(lpToken1).safeTransfer(treasury1, lp1Bal);
            }
        } else {
            revert("Not Enough Amount");
        }
    }

    function _chargeFees(
        address token,
        uint256 amount
    ) internal returns (uint256) {
        (uint256 t0, uint256 t1, uint256 remainingAmount) = calculate(amount);
        IERC20(token).safeTransfer(treasury0, t0);
        IERC20(token).safeTransfer(treasury1, t1);
        emit Fees(t0,t1);
        return remainingAmount;
    }

    function calculateShareAmount(
        uint256 amount,
        address _miniChef,
        uint256 _poolId
    ) public view returns (uint256) {
        uint256 supply = totalSupply;
        (uint256 _amount, ) = IMiniChefV2(_miniChef).userInfo(
            _poolId,
            address(this)
        );
        return supply == 0 ? amount : (amount.mul(supply)).div(_amount);
    }

    function calculateWithdrawShare(
        uint256 amount,
        address _miniChef,
        uint256 _poolId
    ) public view returns (uint256) {
        (uint256 _amount, ) = IMiniChefV2(_miniChef).userInfo(
            _poolId,
            address(this)
        );
        return amount.mul(totalSupply).div(_amount);
    }

    function calculate(
        uint256 amount
    ) internal pure returns (uint256, uint256, uint256) {
        require((amount * FEE) >= 10_000);
        return (
            (amount * FEE) / 10_000,
            (amount * FEE) / 10_000,
            (amount * REMAINING_AMOUNT) / 10_000
        );
    }

    function _calculateSwapInAmount(
        uint256 reserveIn,
        uint256 amount
    ) internal pure returns (uint256) {
        return
            Babylonian
                .sqrt(
                    reserveIn.mul(amount.mul(3988000) + reserveIn.mul(3988009))
                )
                .sub(reserveIn.mul(1997)) / 1994;
    }
}

