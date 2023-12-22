// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./Ownable.sol";
import "./AccessControl.sol";
import "./PoolController.sol";
import "./BalancerInterfaces.sol";
import "./console.sol";

import "./WeightedMath.sol";

contract BalancerManager is Ownable, AccessControl {
    // IERC20 public immutable WETH =
    //     IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public immutable WETH =
        IERC20(0x5979D7b546E38E414F7E9822514be443A4800529);
    address public immutable ETH = address(0);
    IVault public immutable BALANCER_VAULT =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IWeightedPoolFactory public immutable BALANCER_WEIGHTED_POOL_FACTORY =
        IWeightedPoolFactory(0xf1665E19bc105BE4EDD3739F88315cC699cc5b65);

    IManagedPoolFactory public immutable BALANCER_MANAGED_POOL_FACTORY =
        IManagedPoolFactory(0x956CCab09898C0AF2aCa5e6C229c3aD4E93d9288);

    bytes32 public constant LIQUIDITY_MANAGER_ROLE =
        keccak256("LIQUIDITY_MANAGER_ROLE");

    IERC20 public UPDOGE;
    address public poolAddress;
    address public poolControllerAddress;

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

    constructor(address updogeAddress_) {
        UPDOGE = IERC20(updogeAddress_);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function grantLiquidityManager(address address_) external onlyOwner {
        grantRole(LIQUIDITY_MANAGER_ROLE, address_);
    }

    function revokeLiquidityManager(address address_) external onlyOwner {
        revokeRole(LIQUIDITY_MANAGER_ROLE, address_);
    }

    function createBalancerPool(
        address poolControllerAddress_
    ) external payable onlyOwner {
        require(poolAddress == address(0), "Pool already created");
        poolControllerAddress = poolControllerAddress_;

        uint256[] memory weights = new uint256[](2);
        address[] memory assetManagers = new address[](2);

        if (address(UPDOGE) > address(WETH)) {
            updogeIndex = 1;
            wethIndex = 0;
        }

        tokens[updogeIndex] = UPDOGE;
        tokens[wethIndex] = WETH;
        weights[updogeIndex] = 0.99 ether;
        weights[wethIndex] = 0.01 ether;

        assetManagers[0] = address(0);
        assetManagers[1] = address(0);

        // poolAddress = BALANCER_WEIGHTED_POOL_FACTORY.create(
        //     "lpUPDOGE",
        //     "lpUPDOGE",
        //     tokens,
        //     weights,
        //     assetManagers,
        //     50000000000000000,
        //     msg.sender
        // );

        ManagedPoolSettings.NewPoolParams
            memory poolParams = ManagedPoolSettings.NewPoolParams({
                name: "UPDOGE BPT",
                symbol: "BPT-UPDOGE",
                tokens: tokens,
                normalizedWeights: weights,
                assetManagers: assetManagers,
                swapFeePercentage: 0.0001 ether,
                swapEnabledOnStart: true,
                mustAllowlistLPs: true,
                managementAumFeePercentage: 0.1 ether,
                aumFeeId: 3
            });

        poolAddress = BALANCER_MANAGED_POOL_FACTORY.create(
            poolParams,
            poolControllerAddress
        );
        PoolController(poolControllerAddress).init(poolAddress);

        poolId = IManagedPool(poolAddress).getPoolId();

        uint256[] memory amountsIn2 = new uint256[](2);
        amountsIn2[updogeIndex] = UPDOGE.balanceOf(address(this));
        amountsIn2[wethIndex] = WETH.balanceOf(address(this));

        uint256[] memory amountsIn3 = new uint256[](3);
        amountsIn3[
            0
        ] = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        amountsIn3[updogeIndex + 1] = amountsIn2[updogeIndex];
        amountsIn3[wethIndex + 1] = amountsIn2[wethIndex];

        IERC20[] memory tokens3 = new IERC20[](3);
        tokens3[0] = IERC20(poolAddress);
        tokens3[updogeIndex + 1] = tokens[updogeIndex];
        tokens3[wethIndex + 1] = tokens[wethIndex];

        // Encode the userData for a multi-token join
        bytes memory userData = abi.encode(
            WeightedPoolUserData.JoinKind.INIT,
            amountsIn2
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: _asIAsset(tokens3),
            maxAmountsIn: amountsIn3,
            userData: userData,
            fromInternalBalance: false
        });

        WETH.approve(address(BALANCER_VAULT), WETH.balanceOf(address(this)));

        UPDOGE.approve(
            address(BALANCER_VAULT),
            UPDOGE.balanceOf(address(this))
        );

        BALANCER_VAULT.joinPool(poolId, address(this), address(this), request);
    }

    function buyUpdoge(uint256 wethAmount) public onlyLiquidityManager {
        WETH.transferFrom(msg.sender, address(this), wethAmount);
        WETH.approve(address(BALANCER_VAULT), wethAmount);

        uint256 updogeAmount = wethAmountToUpdogeAmount(wethAmount);

        IVault.FundManagement memory funds = IVault.FundManagement(
            address(this),
            false,
            payable(msg.sender),
            false
        );

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap(
            IManagedPool(poolAddress).getPoolId(),
            IVault.SwapKind.GIVEN_IN,
            IAsset(address(WETH)),
            IAsset(address(UPDOGE)),
            wethAmount,
            "0x"
        );

        BALANCER_VAULT.swap(singleSwap, funds, updogeAmount, block.timestamp);
    }

    function exitPool(uint256 lpAmount) public onlyLiquidityManager {
        uint256[] memory amountsOut3 = new uint256[](3);
        amountsOut3[0] = 0;
        amountsOut3[updogeIndex + 1] = 0;
        amountsOut3[wethIndex + 1] = 0;

        IERC20[] memory tokens3 = new IERC20[](3);
        tokens3[0] = IERC20(poolAddress);
        tokens3[updogeIndex + 1] = tokens[updogeIndex];
        tokens3[wethIndex + 1] = tokens[wethIndex];

        bytes memory userData = abi.encode(
            WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
            lpAmount
        );

        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: _asIAsset(tokens3),
            minAmountsOut: amountsOut3,
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
        return balances[updogeIndex + 1];
    }

    function wethInPoolBalance() public view returns (uint256) {
        (, uint256[] memory balances, ) = BALANCER_VAULT.getPoolTokens(poolId);
        return balances[wethIndex + 1];
    }

    function wethAmountToUpdogeAmount(
        uint256 wethAmount
    ) public view returns (uint256) {
        (, uint256[] memory balances, ) = BALANCER_VAULT.getPoolTokens(poolId);

        uint256[] memory weights = IManagedPool(poolAddress)
            .getNormalizedWeights();

        uint256 swapFeePercentage = IManagedPool(poolAddress)
            .getSwapFeePercentage();
        uint256 fee = (wethAmount * swapFeePercentage) / 1 ether;
        uint256 wethAmountWithoutFee = wethAmount - fee;

        return
            WeightedMath._calcOutGivenIn(
                balances[wethIndex + 1],
                weights[wethIndex],
                balances[updogeIndex + 1],
                weights[updogeIndex],
                wethAmountWithoutFee
            );
    }
}

