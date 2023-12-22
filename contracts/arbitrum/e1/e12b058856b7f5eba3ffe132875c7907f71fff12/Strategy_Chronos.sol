// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./Strategy.sol";
import "./ISolidlyRouter.sol";

interface IMaGauge {
    function depositAll() external returns(uint _tokenId);
    function withdrawAndHarvest(uint _tokenId) external;
    function balanceOfToken(uint tokenId) external view returns (uint256);
}

interface IERC20Extended {
    function decimals() external view returns (uint);
}

contract Strategy_Chronos is Strategy {
    using SafeERC20 for IERC20;

    address public uniProxyAddress;
    bool public isStable;

    ISolidlyRouter.Routes[] public earnedToToken0Route;
    ISolidlyRouter.Routes[] public earnedToToken1Route;
    ISolidlyRouter.Routes[] public token0ToEarnedRoute;
    ISolidlyRouter.Routes[] public token1ToEarnedRoute;

    uint256 public tokenId;

    constructor(
        address[] memory _addresses,
        address[] memory _tokenAddresses,
        bool _isAutoComp,
        bool _isStable,
        ISolidlyRouter.Routes[] memory _earnedToToken0Route,
        ISolidlyRouter.Routes[] memory _earnedToToken1Route,
        ISolidlyRouter.Routes[] memory _token0ToEarnedRoute,
        ISolidlyRouter.Routes[] memory _token1ToEarnedRoute,
        uint256 _withdrawFeeFactor
    ) {
        vault = _addresses[0];
        farmContractAddress = _addresses[1];
        govAddress = _addresses[2];
        uniRouterAddress = _addresses[3];

        wantAddress = _tokenAddresses[0];
        earnedAddress = _tokenAddresses[1];
        token0Address = _tokenAddresses[2];
        token1Address = _tokenAddresses[3];

        isSingleVault = false;
        isAutoComp = _isAutoComp;
        isStable = _isStable;

        for (uint i; i < _earnedToToken0Route.length; ++i) {
            earnedToToken0Route.push(_earnedToToken0Route[i]);
        }
        for (uint i; i < _earnedToToken1Route.length; ++i) {
            earnedToToken1Route.push(_earnedToToken1Route[i]);
        }
        for (uint i; i < _token0ToEarnedRoute.length; ++i) {
            token0ToEarnedRoute.push(_token0ToEarnedRoute[i]);
        }
        for (uint i; i < _token1ToEarnedRoute.length; ++i) {
            token1ToEarnedRoute.push(_token1ToEarnedRoute[i]);
        }

        withdrawFeeFactor = _withdrawFeeFactor;
    }

    function balanceOfStakedWant() public view override returns (uint256) {
        if (tokenId == 0) return 0;
        return IMaGauge(farmContractAddress).balanceOfToken(tokenId);
    }

    function deposit()
        public
        override
        whenNotPaused
    {
        uint256 wantBal = balanceOfWant();
        if (isAutoComp && wantBal > 0) {
            _unfarm(0);
            _farm();
        }
    }

    function _farm() internal override {
        require(isAutoComp, "!isAutoComp");
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);
        tokenId = IMaGauge(farmContractAddress).depositAll();
    }

    function _unfarm(uint256 _ignored) internal override {
        if (balanceOfStakedWant() > 0) {
            IMaGauge(farmContractAddress).withdrawAndHarvest(tokenId);
            tokenId = 0;
        }
    }

    function withdraw(uint256 _wantAmt)
        external
        override
    {
        require(msg.sender == vault, "!vault");
        require(_wantAmt > 0, "_wantAmt <= 0");

        uint256 wantBal = balanceOfWant();
        if (isAutoComp && wantBal < _wantAmt) {
            _unfarm(0);
            wantBal = balanceOfWant();
        }

        if (_wantAmt > wantBal) {
            _wantAmt = wantBal;
        }

        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = _wantAmt * withdrawFeeFactor / withdrawFeeFactorMax;
        }

        IERC20(wantAddress).safeTransfer(vault, _wantAmt);

        if (balanceOfWant() > 0 && tokenId == 0 && !paused()) {
            _farm();
        }
    }

    function _harvest() internal override {
        _unfarm(0);
    }

    // 1. Harvest farm tokens
    // 2. Converts farm tokens into want tokens
    // 3. Deposits want tokens
    function earn() public override whenNotPaused {
        require(isAutoComp, "!isAutoComp");

        // Harvest farm tokens
        _harvest();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        earnedAmt = distributeFees(earnedAmt);
        uint256 earned0Amt = earnedAmt / 2;
        uint256 earned1Amt = earnedAmt - earned0Amt;

        if (isStable) {
            uint256 token0Decimals = 10 ** IERC20Extended(token0Address).decimals();
            uint256 token1Decimals = 10 ** IERC20Extended(token1Address).decimals();
            uint256 out0 = (ISolidlyRouter(uniRouterAddress).getAmountsOut(earned0Amt, earnedToToken0Route)[earnedToToken0Route.length] *
                1e18) / token0Decimals;
            uint256 out1 = (ISolidlyRouter(uniRouterAddress).getAmountsOut(earned1Amt, earnedToToken1Route)[earnedToToken1Route.length] *
                1e18) / token1Decimals;
            (uint256 amountA, uint256 amountB, ) = ISolidlyRouter(uniRouterAddress).quoteAddLiquidity(
                token0Address,
                token1Address,
                isStable,
                out0,
                out1
            );
            amountA = (amountA * 1e18) / token0Decimals;
            amountB = (amountB * 1e18) / token1Decimals;
            uint256 ratio = (((out0 * 1e18) / out1) * amountB) / amountA;
            earned0Amt = (earnedAmt * 1e18) / (ratio + 1e18);
            earned1Amt = earnedAmt - earned0Amt;
        }

        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            earnedAmt
        );
        
        if (earnedAddress != token0Address) {
            ISolidlyRouter(uniRouterAddress).swapExactTokensForTokens(
                earned0Amt,
                0,
                earnedToToken0Route,
                address(this),
                block.timestamp + routerDeadlineDuration
            );
        }

        if (earnedAddress != token1Address) {
            ISolidlyRouter(uniRouterAddress).swapExactTokensForTokens(
                earned1Amt,
                0,
                earnedToToken1Route,
                address(this),
                block.timestamp + routerDeadlineDuration
            );
        }

        // Get want tokens, ie. add liquidity
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token0Amt > 0 && token1Amt > 0) {
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );
            ISolidlyRouter(uniRouterAddress).addLiquidity(
                token0Address,
                token1Address,
                isStable,
                token0Amt,
                token1Amt,
                1,
                1,
                address(this),
                block.timestamp
            );
        }

        lastEarnBlock = block.number;

        _farm();
    }

    function convertDustToEarned() public override whenNotPaused {
        require(isAutoComp, "!isAutoComp");
        require(!isSingleVault, "isSingleVault");

        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().

        // Converts token0 dust (if any) to earned tokens
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Address != earnedAddress && token0Amt > 0) {
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );

            // Swap all dust tokens to earned tokens
            ISolidlyRouter(uniRouterAddress).swapExactTokensForTokens(
                token0Amt,
                0,
                token0ToEarnedRoute,
                address(this),
                block.timestamp + routerDeadlineDuration
            );
        }

        // Converts token1 dust (if any) to earned tokens
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Address != earnedAddress && token1Amt > 0) {
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );

            // Swap all dust tokens to earned tokens
            ISolidlyRouter(uniRouterAddress).swapExactTokensForTokens(
                token1Amt,
                0,
                token1ToEarnedRoute,
                address(this),
                block.timestamp + routerDeadlineDuration
            );
        }
    }

    function updateEarnedRoute(
        ISolidlyRouter.Routes[] memory _earnedToToken0Route,
        ISolidlyRouter.Routes[] memory _earnedToToken1Route,
        ISolidlyRouter.Routes[] memory _token0ToEarnedRoute,
        ISolidlyRouter.Routes[] memory _token1ToEarnedRoute
    ) external onlyAllowGov {
        delete earnedToToken0Route;
        delete earnedToToken1Route;
        delete token0ToEarnedRoute;
        delete token1ToEarnedRoute;

        for (uint i; i < _earnedToToken0Route.length; ++i) {
            earnedToToken0Route.push(_earnedToToken0Route[i]);
        }
        for (uint i; i < _earnedToToken1Route.length; ++i) {
            earnedToToken1Route.push(_earnedToToken1Route[i]);
        }
        for (uint i; i < _token0ToEarnedRoute.length; ++i) {
            token0ToEarnedRoute.push(_token0ToEarnedRoute[i]);
        }
        for (uint i; i < _token1ToEarnedRoute.length; ++i) {
            token1ToEarnedRoute.push(_token1ToEarnedRoute[i]);
        }
    }
}
