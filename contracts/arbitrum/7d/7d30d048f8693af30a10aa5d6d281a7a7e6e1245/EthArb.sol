pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;


interface UniswapReserve {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    function token0() external view returns(address);
    function token1() external view returns(address);
    function fee() external view returns(uint); 
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);    
}

interface ERC20Like {
    function approve(address spender, uint value) external returns(bool);
    function transfer(address to, uint value) external returns(bool);
    function balanceOf(address a) external view returns(uint);
}

interface WethLike is ERC20Like {
    function deposit() external payable;
}

interface CurveLike {
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns(uint);
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns(uint);
}

interface BAMMLike {
    function swap(uint lusdAmount, uint minEthReturn, address payable dest) external returns(uint);
}

interface UniRouterLike {
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external;
}

contract Usdc2Gem {
    address constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant FRAX = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
    address constant VST = 0x64343594Ab9b56e99087BfA6F2335Db24c2d1F17;

    CurveLike constant CURV_FRAX_VST = CurveLike(0x59bF0545FCa0E5Ad48E13DA269faCD2E8C886Ba4);
    CurveLike constant CURV_FRAX_USDC = CurveLike(0xC9B8a3FDECB9D5b218d02555a8Baf332E5B740d5);    

    constructor() public {
        ERC20Like(USDC).approve(address(CURV_FRAX_USDC), uint(-1));
        ERC20Like(FRAX).approve(address(CURV_FRAX_VST), uint(-1));        
    }

    function usdc2Gem(uint usdcQty, address bamm) public returns(uint gemAmount) {
        uint fraxReturn = CURV_FRAX_USDC.exchange(1, 0, usdcQty, 1);
        uint vstReturn = CURV_FRAX_VST.exchange(1, 0, fraxReturn, 1);

        ERC20Like(VST).approve(address(bamm), vstReturn);
        return BAMMLike(bamm).swap(vstReturn, 1, address(this));
    }

    receive() external payable {}
}

contract EthArb is Usdc2Gem {
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    UniswapReserve constant USDCETH = UniswapReserve(0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443);
    uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint160 constant MIN_SQRT_RATIO = 4295128739;

    constructor() public Usdc2Gem() {
    }

    function swap(uint ethQty, address bamm) external payable returns(uint) {
        bytes memory data = abi.encode(bamm);
        USDCETH.swap(address(this), true, int256(ethQty), MIN_SQRT_RATIO + 1, data);

        uint retVal = address(this).balance;
        msg.sender.transfer(retVal);

        return retVal;
     }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        uint USDCAmount = uint(-1 * amount1Delta); 

        require(msg.sender == address(USDCETH), "uniswapV3SwapCallback: invalid sender");
        address bamm = abi.decode(data, (address));

        // swap USDC to FRAX to VST to ETH
        usdc2Gem(USDCAmount, bamm);
        
        if(amount0Delta > 0) {
            WethLike(WETH).deposit{value: uint(amount0Delta)}();
            if(amount0Delta > 0) WethLike(WETH).transfer(msg.sender, uint(amount0Delta));            
        }
    }
}

contract GOHMArb is Usdc2Gem {
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    UniswapReserve constant USDCETH = UniswapReserve(0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443);
    uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint160 constant MIN_SQRT_RATIO = 4295128739;

    address constant gOHM = 0x8D9bA570D6cb60C7e3e0F31343Efe75AB8E65FB1;
    UniRouterLike constant SUSHI_ROUTER = UniRouterLike(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    constructor() public Usdc2Gem() {
        ERC20Like(gOHM).approve(address(SUSHI_ROUTER), uint(-1));
    }

    function swap(uint ethQty, address bamm) external payable returns(uint) {
        bytes memory data = abi.encode(bamm);
        USDCETH.swap(address(this), true, int256(ethQty), MIN_SQRT_RATIO + 1, data);

        uint retVal = address(this).balance;
        msg.sender.transfer(retVal);

        return retVal;
     }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        uint USDCAmount = uint(-1 * amount1Delta); 

        require(msg.sender == address(USDCETH), "uniswapV3SwapCallback: invalid sender");     
        address bamm = abi.decode(data, (address));

        // swap USDC to FRAX to VST to gOHM
        uint gOHMAmount = usdc2Gem(USDCAmount, bamm);     

        // swap gOHM to ETH on sushiswap
        dumpGOHM(gOHMAmount);
        
        if(amount0Delta > 0) {
            WethLike(WETH).deposit{value: uint(amount0Delta)}();
            if(amount0Delta > 0) WethLike(WETH).transfer(msg.sender, uint(amount0Delta));            
        }
    }

    function dumpGOHM(uint ohmQty) public {
        address[] memory path = new address[](2);
        path[0] = gOHM;
        path[1] = WETH;
        SUSHI_ROUTER.swapExactTokensForETH(ohmQty, 1, path, address(this), now + 1);
    }
}

contract DPXArb is Usdc2Gem {
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    UniswapReserve constant USDCETH = UniswapReserve(0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443);
    uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint160 constant MIN_SQRT_RATIO = 4295128739;

    address constant DPX = 0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55;
    UniRouterLike constant SUSHI_ROUTER = UniRouterLike(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    constructor() public Usdc2Gem() {
        ERC20Like(DPX).approve(address(SUSHI_ROUTER), uint(-1));
    }

    function swap(uint ethQty, address bamm) external payable returns(uint) {
        bytes memory data = abi.encode(bamm);
        USDCETH.swap(address(this), true, int256(ethQty), MIN_SQRT_RATIO + 1, data);

        uint retVal = address(this).balance;
        msg.sender.transfer(retVal);

        return retVal;
     }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        uint USDCAmount = uint(-1 * amount1Delta); 

        require(msg.sender == address(USDCETH), "uniswapV3SwapCallback: invalid sender");     
        address bamm = abi.decode(data, (address));

        // swap USDC to FRAX to VST to DPX
        uint dpxAmount = usdc2Gem(USDCAmount, bamm);     

        // swap gOHM to ETH on sushiswap
        dumpDPX(dpxAmount);
        
        if(amount0Delta > 0) {
            WethLike(WETH).deposit{value: uint(amount0Delta)}();
            if(amount0Delta > 0) WethLike(WETH).transfer(msg.sender, uint(amount0Delta));            
        }
    }

    function dumpDPX(uint dpxQty) public {
        address[] memory path = new address[](2);
        path[0] = DPX;
        path[1] = WETH;
        SUSHI_ROUTER.swapExactTokensForETH(dpxQty, 1, path, address(this), now + 1);
    }
}
//import "hardhat/console.sol";
contract GMXArb is Usdc2Gem {
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    UniswapReserve constant USDCETH = UniswapReserve(0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443);
    uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint160 constant MIN_SQRT_RATIO = 4295128739;

    address constant GMX = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
    ISwapRouter constant UNI_ROUTER = ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    UniswapReserve constant GMXETH = UniswapReserve(0x80A9ae39310abf666A87C743d6ebBD0E8C42158E);

    constructor() public Usdc2Gem() {
        ERC20Like(GMX).approve(address(UNI_ROUTER), uint(-1));
    }

    function swap(uint ethQty, address bamm) external payable returns(uint) {
        bytes memory data = abi.encode(bamm);
        USDCETH.swap(address(this), true, int256(ethQty), MIN_SQRT_RATIO + 1, data);

        uint retVal = address(this).balance;
        msg.sender.transfer(retVal);

        return retVal;
     }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        if(msg.sender == address(USDCETH)) {
            uint USDCAmount = uint(-1 * amount1Delta); 

            address bamm = abi.decode(data, (address));

            // swap USDC to FRAX to VST to DPX
            uint gmxAmount = usdc2Gem(USDCAmount, bamm);     

            // swap gOHM to ETH on sushiswap
            dumpGMX(gmxAmount);

            if(amount0Delta > 0) {
                //console.log(uint(amount0Delta));                
                //console.log(ERC20Like(WETH).balanceOf(address(this)));
                //console.log(address(this).balance);                
                //WethLike(WETH).deposit{value: uint(amount0Delta)}();
                if(amount0Delta > 0) WethLike(WETH).transfer(msg.sender, uint(amount0Delta));            
            }            
        }
        else if(msg.sender == address(GMXETH)) {
            //console.log(uint(amount0Delta));
            //console.log(uint(amount1Delta));

            if(amount1Delta > 0) {
                ERC20Like(GMX).transfer(msg.sender, uint(amount1Delta));
            }            
        }
    }

    function dumpGMX(uint gmxQty) public {
        
        ERC20Like(GMX).approve(address(GMXETH), gmxQty);
        //console.log(uint(GMXETH.token0()));
        //console.log(uint(GMXETH.token1()));        
        GMXETH.swap(address(this), false, int256(gmxQty), MAX_SQRT_RATIO - 1, bytes(""));

/*
        console.log(gmxQty);
       ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: GMX,
                tokenOut: WETH,
                fee: 10000,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: gmxQty,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: MAX_SQRT_RATIO - 1
            });

        // The call to `exactInputSingle` executes the swap.
        UNI_ROUTER.exactInputSingle(params);*/
    }
}

// renbtc => btc (curvfi). btc => eth (sushi)

contract BTCArb is Usdc2Gem {
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    UniswapReserve constant USDCETH = UniswapReserve(0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443);
    UniRouterLike constant SUSHI_ROUTER = UniRouterLike(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);    
    uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint160 constant MIN_SQRT_RATIO = 4295128739;
    CurveLike constant CURV_WBTC_RENBTC = CurveLike(0x3E01dD8a5E1fb3481F0F589056b428Fc308AF0Fb);

    address constant REN_BTC = 0xDBf31dF14B66535aF65AaC99C32e9eA844e14501;
    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    constructor() public Usdc2Gem() {
        ERC20Like(WBTC).approve(address(SUSHI_ROUTER), uint(-1));
        ERC20Like(REN_BTC).approve(address(CURV_WBTC_RENBTC), uint(-1));        
    }

    function swap(uint ethQty, address bamm) external payable returns(uint) {
        bytes memory data = abi.encode(bamm);
        USDCETH.swap(address(this), true, int256(ethQty), MIN_SQRT_RATIO + 1, data);

        uint retVal = address(this).balance;
        msg.sender.transfer(retVal);

        return retVal;
     }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        uint USDCAmount = uint(-1 * amount1Delta); 

        require(msg.sender == address(USDCETH), "uniswapV3SwapCallback: invalid sender");
        address bamm = abi.decode(data, (address));

        // swap USDC to FRAX to VST to ETH
        uint btcAmount = usdc2Gem(USDCAmount, bamm);
        dumpBTC(btcAmount);

        if(amount0Delta > 0) {
            WethLike(WETH).deposit{value: uint(amount0Delta)}();
            if(amount0Delta > 0) WethLike(WETH).transfer(msg.sender, uint(amount0Delta));            
        }
    }

    function dumpBTC(uint renBTCAmount) public {
        uint wbtcAmount = CURV_WBTC_RENBTC.exchange(1, 0, renBTCAmount, 1);

        address[] memory path = new address[](2);
        path[0] = WBTC;
        path[1] = WETH;
        SUSHI_ROUTER.swapExactTokensForETH(wbtcAmount, 1, path, address(this), now + 1);
    }    
}