// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./Ownable.sol";
import "./AccessControl.sol";
import "./BalancerInterfaces.sol";
import "./console.sol";

import "./WeightedMath.sol";

contract BalancerManager is Ownable, AccessControl {
    IVault public immutable BALANCER_VAULT =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    IWeightedPoolFactory public immutable BALANCER_WEIGHTED_POOL_FACTORY =
        IWeightedPoolFactory(0xf1665E19bc105BE4EDD3739F88315cC699cc5b65);

    bytes32 public constant LIQUIDITY_MANAGER_ROLE =
        keccak256("LIQUIDITY_MANAGER_ROLE");

    IERC20 public updoge;
    IERC20 public weth;
    address public poolAddress;

    // BALANCE POOL
    IERC20[] tokens = new IERC20[](2);
    uint256 internal updogeIndex = 0;
    uint256 internal wethIndex = 1;
    bytes32 public poolId;

    modifier onlyLiquidityManager() {
        require(
            hasRole(LIQUIDITY_MANAGER_ROLE, _msgSender()),
            "Not LIQUIDITY_MANAGER_ROLE"
        );
        _;
    }

    constructor(IERC20 updoge_, IERC20 weth_) {
        updoge = updoge_;
        weth = weth_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function grantLiquidityManager(address address_) external onlyOwner {
        grantRole(LIQUIDITY_MANAGER_ROLE, address_);
    }

    function revokeLiquidityManager(address address_) external onlyOwner {
        revokeRole(LIQUIDITY_MANAGER_ROLE, address_);
    }

    function createBalancerPool() external payable onlyOwner {
        require(poolAddress == address(0), "Pool already created");

        uint256[] memory weights = new uint256[](2);
        address[] memory assetManagers = new address[](2);

        if (address(updoge) > address(weth)) {
            updogeIndex = 1;
            wethIndex = 0;
        }

        tokens[updogeIndex] = updoge;
        tokens[wethIndex] = weth;
        weights[updogeIndex] = 0.99 ether;
        weights[wethIndex] = 0.01 ether;

        assetManagers[0] = address(0);
        assetManagers[1] = address(0);

        poolAddress = BALANCER_WEIGHTED_POOL_FACTORY.create(
            "UPDOGE-BPT",
            "UPDOGE-BPT",
            tokens,
            weights,
            assetManagers,
            0.0001 ether,
            msg.sender
        );

        poolId = IWeightedPool(poolAddress).getPoolId();

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[updogeIndex] = updoge.balanceOf(address(this));
        amountsIn[wethIndex] = weth.balanceOf(address(this));

        // Encode the userData for a multi-token join
        bytes memory userData = abi.encode(
            WeightedPoolUserData.JoinKind.INIT,
            amountsIn
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: _asIAsset(tokens),
            maxAmountsIn: amountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        weth.approve(address(BALANCER_VAULT), weth.balanceOf(address(this)));

        updoge.approve(
            address(BALANCER_VAULT),
            updoge.balanceOf(address(this))
        );

        BALANCER_VAULT.joinPool(poolId, address(this), address(this), request);
    }

    function buyUpdoge(
        uint256 wethAmount,
        uint256 slippage
    ) public onlyLiquidityManager {
        weth.transferFrom(msg.sender, address(this), wethAmount);
        weth.approve(address(BALANCER_VAULT), wethAmount);

        uint256 updogeAmount = (wethAmountToUpdogeAmount(wethAmount) *
            (1 ether - slippage)) / 1 ether;

        IVault.FundManagement memory funds = IVault.FundManagement(
            address(this),
            false,
            payable(msg.sender),
            false
        );

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap(
            IWeightedPool(poolAddress).getPoolId(),
            IVault.SwapKind.GIVEN_IN,
            IAsset(address(weth)),
            IAsset(address(updoge)),
            wethAmount,
            "0x"
        );

        BALANCER_VAULT.swap(singleSwap, funds, updogeAmount, block.timestamp);
    }

    function exitPool(uint256 lpAmount) public onlyLiquidityManager {
        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[updogeIndex] = 0;
        amountsOut[wethIndex] = 0;

        bytes memory userData = abi.encode(
            WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
            lpAmount
        );

        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: _asIAsset(tokens),
            minAmountsOut: amountsOut,
            userData: userData,
            toInternalBalance: false
        });

        BALANCER_VAULT.exitPool(
            poolId,
            address(this),
            payable(msg.sender),
            request
        );
    }

    function withdrawLiquidity(address to_, uint256 amount_) public onlyOwner {
        IERC20(poolAddress).transferFrom(address(this), to_, amount_);
    }

    function poolBalance() public view returns (uint256) {
        return IERC20(poolAddress).balanceOf(address(this));
    }

    function updogeInPoolBalance() public view returns (uint256) {
        (, uint256[] memory balances, ) = BALANCER_VAULT.getPoolTokens(poolId);
        return balances[updogeIndex];
    }

    function wethInPoolBalance() public view returns (uint256) {
        (, uint256[] memory balances, ) = BALANCER_VAULT.getPoolTokens(poolId);
        return balances[wethIndex];
    }

    function wethAmountToUpdogeAmount(
        uint256 wethAmount
    ) public view returns (uint256) {
        (, uint256[] memory balances, ) = BALANCER_VAULT.getPoolTokens(poolId);

        uint256[] memory weights = IWeightedPool(poolAddress)
            .getNormalizedWeights();

        uint256 swapFeePercentage = IWeightedPool(poolAddress)
            .getSwapFeePercentage();
        uint256 fee = (wethAmount * swapFeePercentage) / 1 ether;
        uint256 wethAmountWithoutFee = wethAmount - fee;

        return
            WeightedMath._calcOutGivenIn(
                balances[wethIndex],
                weights[wethIndex],
                balances[updogeIndex],
                weights[updogeIndex],
                wethAmountWithoutFee
            );
    }
}

