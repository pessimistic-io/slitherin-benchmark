// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import { SushiRouter } from "./SushiRouter.sol";
import { IUniswapV3Router } from "./IUniswapV3Router.sol";
import { IERC20 } from "./IERC20.sol";
import { IWETH } from "./IWETH.sol";
import { IHopPool } from "./IHopPool.sol";
import { Ownable } from "./Ownable.sol";

contract ArbitrumBundleBuyerLowTip is Ownable {
    IERC20[] public tokens;
    uint256[] public amounts;

    mapping(address => address[]) public paths;
    mapping(address => bytes) public uniswapPath;

    uint256 public slippage = 100;
    uint256 public constant BASE_UNIT = 10000;
    SushiRouter public sushiRouter = SushiRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IUniswapV3Router public uniswapV3Router = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address public constant WETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address public constant USDC = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address public constant HOP_USDC_ETH_POOL = address(0x10541b07d8Ad2647Dc6cD67abd4c03575dade261);
    uint256 public usdcAmount = 5e5;
    uint256 public ethTip = 0.001 ether;

    constructor() {
        IWETH(WETH).approve(address(sushiRouter), type(uint256).max);
        IWETH(WETH).approve(address(uniswapV3Router), type(uint256).max);
        IERC20(USDC).approve(HOP_USDC_ETH_POOL, type(uint256).max);
        // DBL
        tokens.push(IERC20(0xd3f1Da62CAFB7E7BC6531FF1ceF6F414291F03D3));
        amounts.push(0.01 ether);

        // DPX
        tokens.push(IERC20(0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55));
        amounts.push(0.0001 ether);

        // LPT
        tokens.push(IERC20(0x289ba1701C2F088cf0faf8B3705246331cB8A839));
        amounts.push(0.001 ether);

        // PLS
        tokens.push(IERC20(0x51318B7D00db7ACc4026C88c3952B66278B6A67F));
        amounts.push(0.001 ether);

        // MAGIC
        tokens.push(IERC20(0x539bdE0d7Dbd336b79148AA742883198BBF60342));
        amounts.push(0.001 ether);

        // LINK
        tokens.push(IERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4));
        amounts.push(0.001 ether);

        // UMAMI
        tokens.push(IERC20(0x1622bF67e6e5747b81866fE0b85178a93C7F86e3));
        amounts.push(1000000);

        // MYC
        tokens.push(IERC20(0xC74fE4c715510Ec2F8C61d70D397B32043F55Abe));
        amounts.push(0.01 ether);

        // VSTA
        tokens.push(IERC20(0xa684cd057951541187f288294a1e1C2646aA2d24));
        amounts.push(0.01 ether);

        // JONES
        tokens.push(IERC20(0x10393c20975cF177a3513071bC110f7962CD67da));
        amounts.push(0.001 ether);

        // SPA
        tokens.push(IERC20(0x5575552988A3A80504bBaeB1311674fCFd40aD4B));
        amounts.push(0.01 ether);

        // GMX
        tokens.push(IERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a));
        amounts.push(0.001 ether);

        // SYN
        tokens.push(IERC20(0x080F6AEd32Fc474DD5717105Dba5ea57268F46eb));
        amounts.push(0.01 ether);

        // HOP-LP-USDC
        tokens.push(IERC20(0xB67c014FA700E69681a673876eb8BAFAA36BFf71));
        amounts.push(0.01 ether);

        // BRC
        tokens.push(IERC20(0xB5de3f06aF62D8428a8BF7b4400Ea42aD2E0bc53));
        amounts.push(0.01 ether);
        //DBL path
        uniswapPath[address(tokens[0])] = abi.encodePacked(address(tokens[0]), uint24(3000), WETH);
        //DPX path
        paths[address(tokens[1])] = [WETH, address(tokens[1])];
        //LPT path
        uniswapPath[address(tokens[2])] = abi.encodePacked(address(tokens[2]), uint24(3000), WETH);
        //PLS path
        paths[address(tokens[3])] = [WETH, address(tokens[3])];
        // Magic path
        paths[address(tokens[4])] = [WETH, address(tokens[4])];
        // LINK path
        paths[address(tokens[5])] = [WETH, address(tokens[5])];
        // UMAMI path
        uniswapPath[address(tokens[6])] = abi.encodePacked(address(tokens[6]), uint24(3000), WETH);
        // MYC path
        uniswapPath[address(tokens[7])] = abi.encodePacked(address(tokens[7]), uint24(10000), WETH);
        //VSTA path
        uniswapPath[address(tokens[8])] = abi.encodePacked(address(tokens[8]), uint24(10000), USDC, uint24(500), WETH);
        //JONES path
        paths[address(tokens[9])] = [WETH, address(tokens[9])];
        //SPA path
        uniswapPath[address(tokens[10])] = abi.encodePacked(address(tokens[10]), uint24(3000), WETH);
        //GMX path
        uniswapPath[address(tokens[11])] = abi.encodePacked(address(tokens[11]), uint24(3000), WETH);
        //SYN path
        uniswapPath[address(tokens[12])] = abi.encodePacked(address(tokens[12]), uint24(10000), WETH);
        //BRC path
        uniswapPath[address(tokens[14])] = abi.encodePacked(
            address(tokens[14]),
            uint24(10000),
            USDC,
            uint24(500),
            WETH
        );
    }

    function bundlePurchase() external payable {
        IWETH(WETH).deposit{ value: msg.value }();
        _handleTip();
        for (uint256 i; i < tokens.length; ) {
            if (paths[address(tokens[i])].length != 0) {
                uint256[] memory inputAmount = sushiRouter.getAmountsIn(amounts[i], paths[address(tokens[1])]);
                sushiRouter.swapTokensForExactTokens(
                    amounts[i],
                    (inputAmount[0] * (BASE_UNIT + slippage)) / BASE_UNIT,
                    paths[address(tokens[i])],
                    msg.sender,
                    block.timestamp + 1000
                );
            } else if (uniswapPath[address(tokens[i])].length != 0) {
                uint256 wethBalance = IERC20(WETH).balanceOf(address(this));

                IUniswapV3Router.ExactOutputParams memory params = IUniswapV3Router.ExactOutputParams({
                    path: uniswapPath[address(tokens[i])],
                    recipient: msg.sender,
                    deadline: block.timestamp + 1000,
                    amountOut: amounts[i],
                    amountInMaximum: wethBalance
                });
                uniswapV3Router.exactOutput(params);
            } else {
                uint256 wethBalance = IERC20(WETH).balanceOf(address(this));

                uniswapV3Router.exactOutputSingle(
                    IUniswapV3Router.ExactOutputSingleParams({
                        tokenIn: WETH,
                        tokenOut: USDC,
                        fee: 500,
                        recipient: address(this),
                        deadline: block.timestamp + 1000,
                        amountOut: usdcAmount,
                        amountInMaximum: wethBalance,
                        sqrtPriceLimitX96: 0
                    })
                );
                uint256 usdcBalance = IERC20(USDC).balanceOf(address(this));
                uint256[] memory amountsIn = new uint256[](2);
                amountsIn[0] = usdcBalance;
                uint256 lpReceived = IHopPool(HOP_USDC_ETH_POOL).addLiquidity(amountsIn, 0, block.timestamp + 1000);
                require(lpReceived > amounts[i], "LP amount not enough");
                tokens[i].transfer(msg.sender, lpReceived);
            }

            unchecked {
                ++i;
            }
        }

        uint256 leftOverWeth = IERC20(WETH).balanceOf(address(this));
        if (leftOverWeth > 0) {
            IWETH(WETH).withdraw(leftOverWeth);
            payable(msg.sender).transfer(leftOverWeth);
        }
    }

    function _handleTip() internal {
        payable(address(owner())).transfer(ethTip);
    }

    function changeUniswapPath(address _token, bytes calldata _newPath) external onlyOwner {
        uniswapPath[_token] = _newPath;
    }

    function changeSushiPath(address _token, address[] calldata _newPath) external onlyOwner {
        paths[_token] = _newPath;
    }

    function recoverToken(address _token) external onlyOwner {
        IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this)));
    }

    function changeLiquidityAmount(uint256 _newAmount) external onlyOwner {
        usdcAmount = _newAmount;
    }

    receive() external payable {}
}
