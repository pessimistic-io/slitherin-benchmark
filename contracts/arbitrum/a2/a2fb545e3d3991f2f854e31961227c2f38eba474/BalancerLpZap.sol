// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./IAsset.sol";
import "./IVault.sol";
import "./WeightedPoolUserData.sol";
import "./IRouter.sol";

contract BalancerLpZap {
    address private multisig;
    address private router;
    address private vault;
    address USDC;
    address WETH;
    address DFX;

    bytes32 USDC_WETH_POOL;
    bytes32 DFX_WETH_POOL;

    constructor(
        address _multisig,
        address _router,
        address _vault,
        address _usdc,
        address _weth,
        address _dfx,
        bytes32 _usdcWethPool,
        bytes32 _dfxWethPool
    ) {
        multisig = _multisig;
        router = _router;
        vault = _vault;
        USDC = _usdc;
        WETH = _weth;
        DFX = _dfx;
        USDC_WETH_POOL = _usdcWethPool;
        DFX_WETH_POOL = _dfxWethPool;
    }

    function _swapToUsdc(address[] memory _assets, uint256[] memory _amounts)
        internal
        returns (uint256[] memory targetAmounts_)
    {
        require(_assets.length == _amounts.length, "num assets and amounts do not match");
        targetAmounts_ = new uint256[](_assets.length);
        for (uint256 i = 0; i < _assets.length; i++) {
            // approve router to spend max token from contract
            if (IERC20(_assets[i]).allowance(address(this), router) < _amounts[i]) {
                IERC20(_assets[i]).approve(router, type(uint256).max);
            }

            // transfer asset from EOA
            require(_amounts[i] != 0, "amount equals 0");
            IERC20(_assets[i]).transferFrom(msg.sender, address(this), _amounts[i]);

            // skip swap for USDC
            if (_assets[i] == USDC) {
                continue;
            }

            // swap balance to USDC
            uint256 thisBalance = IERC20(_assets[i]).balanceOf(address(this));
            targetAmounts_[i] = IRouter(router).originSwap(
                USDC, // _quoteCurrency
                _assets[i], //_origin
                USDC, // _target
                thisBalance, // _originAmount
                0, // _minTargetAmount
                block.timestamp + 60 * 3 //_deadline
            );
        }
    }

    function _singleSwap(bytes32 poolId, address token0, address token1, uint256 amount) internal {
        IVault.SingleSwap memory singleSwap =
            IVault.SingleSwap(poolId, IVault.SwapKind.GIVEN_IN, IAsset(token0), IAsset(token1), amount, new bytes(0));
        IVault.FundManagement memory fundSettings =
            IVault.FundManagement(address(this), false, payable(address(this)), false);
        uint256 deadline = block.timestamp + 60 * 3;

        if (IERC20(token0).allowance(address(this), address(vault)) < amount) {
            IERC20(token0).approve(address(vault), type(uint256).max);
        }
        IVault(vault).swap(singleSwap, fundSettings, amount, deadline);
    }

    function _deposit(bytes32 poolId, address _token0, address _token1) internal {
        address token0;
        address token1;
        if (uint160(_token0) < uint160(_token1)) {
            token0 = _token0;
            token1 = _token1;
        } else {
            token0 = _token1;
            token1 = _token0;
        }

        uint256 token0Bal = IERC20(token0).balanceOf(address(this));
        uint256 token1Bal = IERC20(token1).balanceOf(address(this));

        // approve spending of collaterals to vault
        if (IERC20(token0).allowance(address(this), address(vault)) < token0Bal) {
            IERC20(token0).approve(address(vault), type(uint256).max);
        }
        if (IERC20(token1).allowance(address(this), address(vault)) < token1Bal) {
            IERC20(token1).approve(address(vault), type(uint256).max);
        }
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(token0);
        assets[1] = IAsset(token1);
        uint256[] memory maxAmounts = new uint256[](2);
        maxAmounts[0] = token0Bal;
        maxAmounts[1] = token1Bal;

        // Encode the userData for a multi-token join
        bytes memory userData = abi.encode(WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, maxAmounts, 0);

        IVault.JoinPoolRequest memory joinData = IVault.JoinPoolRequest(assets, maxAmounts, userData, false);
        IVault(vault).joinPool(poolId, address(this), msg.sender, joinData);
    }

    function autoLpExactAmounts(address[] memory _assets, uint256[] memory _amounts)
        public
        returns (uint256, uint256, uint256)
    {
        _swapToUsdc(_assets, _amounts);

        // swap USDC for WETH
        uint256 usdcBal = IERC20(USDC).balanceOf(address(this));
        _singleSwap(USDC_WETH_POOL, USDC, WETH, usdcBal);

        // swap half WETH for DFX
        uint256 wethBal = IERC20(WETH).balanceOf(address(this)) / 2;
        _singleSwap(DFX_WETH_POOL, WETH, DFX, wethBal / 2);

        // deposit to LP
        _deposit(DFX_WETH_POOL, DFX, WETH);

        return (
            IERC20(USDC).balanceOf(address(this)),
            IERC20(WETH).balanceOf(address(this)),
            IERC20(DFX).balanceOf(address(this))
        );
    }

    function autoLp(address[] memory _assets) public returns (uint256, uint256, uint256) {
        uint256[] memory amounts = new uint256[](_assets.length);
        for (uint256 i = 0; i < _assets.length; i++) {
            amounts[i] = IERC20(_assets[i]).balanceOf(msg.sender);
        }

        (uint256 usdcBal, uint256 wethBal, uint256 dfxBal) = autoLpExactAmounts(_assets, amounts);
        return (usdcBal, wethBal, dfxBal);
    }

    function emergencyWithdraw(address token) public {
        require(msg.sender == multisig, "Unauthorized");
        IERC20(token).transfer(multisig, IERC20(token).balanceOf(address(this)));
    }
}

