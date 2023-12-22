pragma solidity >=0.7.0 <0.8.0;
pragma abicoder v2;

import "./SafeERC20.sol";

import "./ICurve.sol";
import "./IUniswapV2Router02.sol";

// Flash related start
import "./CallbackValidation.sol";

import "./IUniswapV3FlashCallback.sol";
import "./LowGasSafeMath.sol";

import "./PoolAddress.sol";
// flash related end


contract Arbitrageur is IUniswapV3FlashCallback {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;

    using SafeERC20 for IERC20;

    // UNIV3 START
    address constant public factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    // UNIV3 END

    // dex address -> token address -> token id
    mapping(address => mapping(address => uint32)) internal dexToTokenMap;

    address public ownerAddress;
    address public collectorAddress;

    uint256 internal bigApproveAmount = 999888777666e18;

    // Uniswap
    address constant internal uniswapV3Router02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    // DEX addresses
    address constant internal curve2Crv = 0x7f90122BF0700F9E7e1F688fe926940E8839F353;
    address constant internal curveMim2Crv = 0x30dF229cefa463e991e29D42DB0bae2e122B2AC7;
    address constant internal curveTricrypto = 0x960ea3e3C7FB317332d990873d354E18d7645590;
    address constant internal curveFrax2Crv = 0xf07d553B195080F84F582e88ecdD54bAa122b279;
    address constant internal curveRen = 0x3E01dD8a5E1fb3481F0F589056b428Fc308AF0Fb;
    address constant internal sushiswapV2Router02 = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

    // Token addresses
    address constant internal usdcAddress = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant internal usdtAddress = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant internal wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant internal daiAddress = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address constant internal mimAddress = 0xFEa7a6a0B346362BF88A9e4A88416B77a57D6c2A;
    address constant internal fraxAddress = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
    address constant internal wbtcAddress = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address constant internal renAddress = 0xDBf31dF14B66535aF65AaC99C32e9eA844e14501;

    struct BackrunParams {
        uint256 deadline;
        uint256 entryAmount;
        address[] tokens;
        address[] dexes;
        address uniswapCounterToken;
        uint24 uniswapPoolfee;
    }

    struct CallbackData {
        address[] tokens;
        address[] dexes;
        uint256 amount0;
        uint256 amount1;
        PoolAddress.PoolKey poolKey;
    }

    constructor(
        address _owner,
        address _collector
    ) {
        ownerAddress = _owner;
        collectorAddress = _collector;

        dexToTokenMap[curve2Crv][usdcAddress] = 0;
        dexToTokenMap[curve2Crv][usdtAddress] = 1;

        dexToTokenMap[curveMim2Crv][mimAddress] = 0;
        dexToTokenMap[curveMim2Crv][usdcAddress] = 1;
        dexToTokenMap[curveMim2Crv][usdtAddress] = 2;

        dexToTokenMap[curveTricrypto][usdtAddress] = 0;
        dexToTokenMap[curveTricrypto][wbtcAddress] = 1;
        dexToTokenMap[curveTricrypto][wethAddress] = 2;

        dexToTokenMap[curveFrax2Crv][fraxAddress] = 0;
        dexToTokenMap[curveFrax2Crv][usdcAddress] = 1;
        dexToTokenMap[curveFrax2Crv][usdtAddress] = 2;

        dexToTokenMap[curveRen][wbtcAddress] = 0;
        dexToTokenMap[curveRen][renAddress] = 1;
    }

    receive() external payable {}

    function setOwner(address _owner) external {
        require(msg.sender == ownerAddress);
        ownerAddress = _owner;
    }

    function setCollector(address _collector) external {
        require(msg.sender == ownerAddress);
        collectorAddress = _collector;
    }

    function withdrawToken(
        address _token,
        address _to
    ) external {
        require(msg.sender == ownerAddress);

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_to, _balance);
    }

    function withdrawEth(
        address _to
    ) external {
        require(msg.sender == ownerAddress);

        payable(_to).transfer(address(this).balance);
    }

    function _execBackrunLogic(
        address[] memory _tokens,
        address[] memory _dexes
    ) internal {
        uint256 giveAmount = 0;

        for (uint8 i=0; i < _dexes.length; i++) {
            giveAmount = IERC20(_tokens[i]).balanceOf(address(this));

            IERC20(_tokens[i]).safeApprove(_dexes[i], bigApproveAmount);

            if (_dexes[i] == sushiswapV2Router02) {
                address[] memory path = new address[](2);
                path[0] = _tokens[i];
                path[1] = _tokens[i + 1];

                IUniswapV2Router02(sushiswapV2Router02).swapExactTokensForTokens(
                    giveAmount, 1, path, address(this), 1869667086
                );
            } else if (_dexes[i] == curve2Crv || _dexes[i] == curveTricrypto || _dexes[i] == curveRen) {
                ICurve(_dexes[i]).exchange(
                    dexToTokenMap[_dexes[i]][_tokens[i]],
                    dexToTokenMap[_dexes[i]][_tokens[i + 1]],
                    giveAmount, 1
                );
            } else if (_dexes[i] == curveMim2Crv || _dexes[i] == curveFrax2Crv) {
                ICurve(_dexes[i]).exchange_underlying(
                    dexToTokenMap[_dexes[i]][_tokens[i]],
                    dexToTokenMap[_dexes[i]][_tokens[i + 1]],
                    giveAmount, 1
                );
            } else {
                revert("BD");
            }
        }
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external override {
        CallbackData memory decoded = abi.decode(data, (CallbackData));
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        // poolkey tokens should be ordered
        address token0 = decoded.poolKey.token0;
        address token1 = decoded.poolKey.token1;

        // SWAP LOGIC START
        _execBackrunLogic(decoded.tokens, decoded.dexes);
        // SWAP LOGIC END

        uint256 amount0Owed = LowGasSafeMath.add(decoded.amount0, fee0);
        uint256 amount1Owed = LowGasSafeMath.add(decoded.amount1, fee1);

        if (amount0Owed > 0) {
            IERC20(token0).safeTransfer(msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            IERC20(token1).safeTransfer(msg.sender, amount1Owed);
        }
    }

    function initiateBackrun(BackrunParams memory params) external {
        require(msg.sender == ownerAddress);

        require(params.deadline >= block.timestamp, "TP");
        require(params.dexes.length >= 2, "DS");
        require(params.tokens.length >= 3, "TL");

        // We dont know the order of tokens, so get them sorted
        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(
            params.tokens[0],
            params.uniswapCounterToken,
            params.uniswapPoolfee
        );

        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
        // recipient of borrowed amounts
        // amount of token0 requested to borrow
        // amount of token1 requested to borrow
        // need amount 0 and amount1 in callback to pay back pool
        // recipient of flash should be THIS contract

        if (poolKey.token0 == params.tokens[0]) {
            pool.flash(
                address(this),
                params.entryAmount,
                0,
                abi.encode(
                    CallbackData({
                        tokens: params.tokens,
                        dexes: params.dexes,
                        amount0: params.entryAmount,
                        amount1: 0,
                        poolKey: poolKey
                    })
                )
            );
        } else if (poolKey.token1 == params.tokens[0]) {
            pool.flash(
                address(this),
                0,
                params.entryAmount,
                abi.encode(
                    CallbackData({
                        tokens: params.tokens,
                        dexes: params.dexes,
                        amount0: 0,
                        amount1: params.entryAmount,
                        poolKey: poolKey
                    })
                )
            );
        } else {
            revert("ET");
        }

        uint256 profit = IERC20(params.tokens[params.tokens.length - 1]).balanceOf(address(this));

        if (profit > 0) {
            IERC20(params.tokens[params.tokens.length - 1]).safeTransfer(collectorAddress, profit);
        }
    }
}

