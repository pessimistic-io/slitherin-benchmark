// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./SafeERC20.sol";
import "./ERC20_IERC20.sol";
import "./console.sol";

import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./AddressUpgradeable.sol";

import "./IAlluoStrategy.sol";
import "./ICvxBooster.sol";
import "./ICvxBaseRewardPool.sol";
import "./IExchange.sol";
import "./PriceFeedRouterV2.sol";

contract CurveConvexStrategyV2 is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable {

    using AddressUpgradeable for address;
    using SafeERC20 for IERC20;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    ICvxBooster public constant cvxBooster =
        ICvxBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IExchange public constant exchange =
        IExchange(0x29c66CF57a03d41Cfe6d9ecB6883aa0E2AbA21Ec);
    IERC20 public constant cvxRewards =
        IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public constant crvRewards =
        IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    bool public upgradeStatus;
    address public priceFeed;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        address _multiSigWallet, 
        address _voteExecutor,
        address _strategyHandler,
        address _priceFeed
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // require(_multiSigWallet.isContract(), "Executor: Not contract");
        priceFeed = _priceFeed;
        _grantRole(DEFAULT_ADMIN_ROLE, _multiSigWallet);
        _grantRole(DEFAULT_ADMIN_ROLE, _voteExecutor);
        _grantRole(DEFAULT_ADMIN_ROLE, _strategyHandler);
        
        _grantRole(UPGRADER_ROLE, _multiSigWallet);

        // For tests only
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    function invest(bytes calldata data, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        (
            address curvePool,
            IERC20 poolToken,
            IERC20 lpToken,
            uint8 poolSize,
            uint8 tokenIndexInCurve,
            uint256 poolId
        ) = decodeEntryParams(data);

        // prepare amounts array for curve
        uint256[4] memory fourPoolTokensAmount;
        fourPoolTokensAmount[tokenIndexInCurve] = amount;

        // approve tokens to curve pool
        poolToken.safeIncreaseAllowance(curvePool, amount);

        // encode call to curve - this ugly code handles different curve pool
        // sizes and function selectors
        bytes memory curveCall;
        if (poolSize == 2) {
            curveCall = abi.encodeWithSelector(
                0x0b4c7e4d,
                uint256[2]([fourPoolTokensAmount[0], fourPoolTokensAmount[1]]),
                0
            );
        } else if (poolSize == 3) {
            curveCall = abi.encodeWithSelector(
                0x4515cef3,
                uint256[3](
                    [
                        fourPoolTokensAmount[0],
                        fourPoolTokensAmount[1],
                        fourPoolTokensAmount[2]
                    ]
                ),
                0
            );
        } else {
            curveCall = abi.encodeWithSelector(
                0x029b2f34,
                fourPoolTokensAmount,
                0
            );
        }

        // execute call
        curvePool.functionCall(curveCall);

        // skip investment in convex, if poolId is uint256 max value
        if (poolId != type(uint256).max) {
            // invest tokens to convex
            uint256 lpAmount = lpToken.balanceOf(address(this));
            lpToken.safeIncreaseAllowance(address(cvxBooster), lpAmount);
            cvxBooster.deposit(poolId, lpAmount, true);
        }
    }

    function exitAll(
        bytes calldata data,
        uint256 unwindPercent,
        IERC20 outputCoin,
        address receiver,
        bool _withdrawRewards,
        bool swapRewards
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (
            address curvePool,
            IERC20 poolToken,
            IERC20 lpToken,
            bytes memory typeOfTokenIndex,
            uint8 tokenIndexInCurve,
            uint256 convexPoolId
        ) = decodeExitParams(data);

        uint256 lpAmount;
        if (convexPoolId != type(uint256).max) {
            ICvxBaseRewardPool rewards = getCvxRewardPool(convexPoolId);
            lpAmount =
                (rewards.balanceOf(address(this)) * unwindPercent) / 10000;

            // withdraw Curve LPs and all rewards
            rewards.withdrawAndUnwrap(lpAmount, _withdrawRewards);
        } else {
            lpAmount = lpToken.balanceOf(address(this)) * unwindPercent / 10000;
        }

        if (lpAmount == 0) return;

        // exit with coin that we used for entry
        bytes memory curveCall = abi.encodeWithSignature(
            string(bytes.concat("remove_liquidity_one_coin(uint256,", typeOfTokenIndex,",uint256)")),
            lpAmount,
            tokenIndexInCurve,
            0
        );

        curvePool.functionCall(curveCall);

        // execute exchanges and transfer all tokens to receiver
        exchangeAll(poolToken, IERC20(outputCoin));
        if(_withdrawRewards){
            manageRewardsAndWithdraw(swapRewards, IERC20(outputCoin), receiver);
        }
        else{
            outputCoin.safeTransfer(receiver, outputCoin.balanceOf(address(this)));
        }
    }

    function getDeployedAmountAndRewards(
        bytes calldata data
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns(uint256){
        (
            IERC20 lpToken,
            uint256 convexPoolId,
            uint256 assetId
        ) = decodeRewardsParams(data);

        uint256 lpAmount;
        if (convexPoolId != type(uint256).max) {
            ICvxBaseRewardPool rewards = getCvxRewardPool(convexPoolId);
            lpAmount = rewards.balanceOf(address(this));
            rewards.getReward(address(this), true);
        } else {
            lpAmount = lpToken.balanceOf(address(this));
        }

        (uint256 fiatPrice, uint8 fiatDecimals) = PriceFeedRouterV2(priceFeed).getPriceOfAmount(address(lpToken), lpAmount, assetId);

        return PriceFeedRouterV2(priceFeed).decimalsConverter(fiatPrice, fiatDecimals, 18);
    }
    
    function withdrawRewards(address _token) public onlyRole(DEFAULT_ADMIN_ROLE){
        manageRewardsAndWithdraw(true, IERC20(_token), msg.sender);
    }

    function exitOnlyRewards(
        bytes calldata data,
        address outputCoin,
        address receiver,
        bool swapRewards
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (,uint256 convexPoolId,) = decodeRewardsParams(data);
        ICvxBaseRewardPool rewards = getCvxRewardPool(convexPoolId);
        rewards.getReward(address(this), true);
        manageRewardsAndWithdraw(swapRewards, IERC20(outputCoin), receiver);
    }

    function multicall(
        address[] calldata destinations,
        bytes[] calldata calldatas
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 length = destinations.length;
        require(length == calldatas.length, "CurveConvexStrategyV2: lengths");
        for (uint256 i = 0; i < length; i++) {
            destinations[i].functionCall(calldatas[i]);
        }
    }

    function getDeployedAmount(
        bytes calldata data
    ) external view returns(uint256){
        (
            IERC20 lpToken,
            uint256 convexPoolId,
            uint256 assetId
        ) = decodeRewardsParams(data);

        uint256 lpAmount;
        if (convexPoolId != type(uint256).max) {
            ICvxBaseRewardPool rewards = getCvxRewardPool(convexPoolId);
            lpAmount = rewards.balanceOf(address(this));
        } else {
            lpAmount = lpToken.balanceOf(address(this));
        }

        (uint256 fiatPrice, uint8 fiatDecimals) = PriceFeedRouterV2(priceFeed).getPriceOfAmount(address(lpToken), lpAmount, assetId);

        return PriceFeedRouterV2(priceFeed).decimalsConverter(fiatPrice, fiatDecimals, 18);
    }

    function encodeEntryParams(
        address curvePool,
        address poolToken,
        address lpToken,
        uint8 poolSize,
        uint8 tokenIndexInCurve,
        uint256 convexPoolId
    ) external pure returns (bytes memory) {
        return
            abi.encode(
                curvePool,
                poolToken,
                lpToken,
                poolSize,
                tokenIndexInCurve,
                convexPoolId
            );
    }

    function encodeExitParams(
        address curvePool,
        address poolToken,
        address lpToken,
        bytes memory typeOfTokenIndex,
        uint8 tokenIndexInCurve,
        uint256 convexPoolId
    ) public pure returns (bytes memory) {
        return
            abi.encode(
                curvePool,
                poolToken,
                lpToken,
                typeOfTokenIndex,
                tokenIndexInCurve,
                convexPoolId
            );
    }

    function encodeRewardsParams(
        address lpToken,
        uint256 convexPoolId,
        uint256 assetId
    ) public pure returns (bytes memory) {
        return
            abi.encode(
                lpToken,
                convexPoolId,
                assetId
            );
    }

    function decodeEntryParams(bytes calldata data)
        public
        pure
        returns (
            address,
            IERC20,
            IERC20,
            uint8,
            uint8,
            uint256
        )
    {
        require(data.length == 32 * 6, "CurveConvexStrategyV2: length en");
        return
            abi.decode(data, (address, IERC20, IERC20, uint8, uint8, uint256));
    }

    function decodeExitParams(bytes calldata data)
        public
        pure
        returns (
            address,
            IERC20,
            IERC20,
            bytes memory,
            uint8,
            uint256
        )
    {
        require(data.length == 32 * 8, "CurveConvexStrategyV2: length ex");
        return abi.decode(data, (address, IERC20, IERC20, bytes, uint8, uint256));
    }
    
    function decodeRewardsParams(bytes calldata data)
        public
        pure
        returns (
            IERC20,
            uint256,
            uint256
        )
    {
        require(data.length == 32 * 3, "CurveConvexStrategyV2: length ex");
        return abi.decode(data, (IERC20, uint256, uint256));
    }

    function exchangeAll(IERC20 fromCoin, IERC20 toCoin) private {
        if (fromCoin == toCoin) return;
        uint256 amount = IERC20(fromCoin).balanceOf(address(this));
        if (amount == 0) return;

        fromCoin.safeApprove(address(exchange), amount);
        exchange.exchange(address(fromCoin), address(toCoin), amount, 0);
    }

    function manageRewardsAndWithdraw(
        bool swapRewards,
        IERC20 outputCoin,
        address receiver
    ) private {
        if (swapRewards) {
            exchangeAll(cvxRewards, outputCoin);
            exchangeAll(crvRewards, outputCoin);
        } else {
            cvxRewards.safeTransfer(
                receiver,
                cvxRewards.balanceOf(address(this))
            );
            crvRewards.safeTransfer(
                receiver,
                crvRewards.balanceOf(address(this))
            );
        }

        outputCoin.safeTransfer(receiver, outputCoin.balanceOf(address(this)));
    }

    function getCvxRewardPool(uint256 poolId)
        private
        view
        returns (ICvxBaseRewardPool)
    {
        (, , , address pool, , ) = cvxBooster.poolInfo(poolId);
        return ICvxBaseRewardPool(pool);
    }

    function grantRole(bytes32 role, address account)
    public
    override
    onlyRole(getRoleAdmin(role)) {
        // if (role == DEFAULT_ADMIN_ROLE) {
        //     require(account.isContract(), "Handler: Not contract");
        // }
        _grantRole(role, account);
    }

    function changeUpgradeStatus(bool _status)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        upgradeStatus = _status;
    }


    function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(UPGRADER_ROLE)
    override {
        require(upgradeStatus, "Executor: Upgrade not allowed");
        upgradeStatus = false;
    }
}
