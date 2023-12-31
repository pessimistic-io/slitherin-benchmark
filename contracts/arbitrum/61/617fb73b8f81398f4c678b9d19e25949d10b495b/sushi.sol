pragma solidity >=0.6.6;

import "./IUniswapV2Router02.sol";
import "./ERC20.sol";
import "./IUniswapV2Pair.sol";


library SafeMathSushi {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
}


library SushiswapLibrary {
    using SafeMathSushi for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'SushiswapLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'SushiswapLibrary: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);

        pair = address(
                    uint160(uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"ff",
                                factory,
                                keccak256(abi.encodePacked(token0, token1)),
                                hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303" // init code hash
                            )
                        )
                    )
            )
        );
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'SushiswapLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'SushiswapLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'SushiswapLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'SushiswapLibrary: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'SushiswapLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'SushiswapLibrary: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'SushiswapLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'SushiswapLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}


contract ArbitrumSushiScamCheckBot {

    address internal constant ROUTER_ADDRESS = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address internal constant FACTORY_ADDRESS = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;

    uint constant MAX_UINT = 2**256 - 1 - 100;
    mapping (address => bool) private authorizations;

    address payable owner;

    event Received(address sender, uint amount);
    IUniswapV2Router02 internal immutable router;

    constructor() {
        router = IUniswapV2Router02(ROUTER_ADDRESS);
        owner = payable(msg.sender);
        authorizations[owner] = true;
    }

    modifier onlyOwner {
       require(
           msg.sender == owner, "Only owner can call this function."
       );
       _;
   }

    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }

    modifier authorized() {
        require(isAuthorized(msg.sender));
        _;
    }

    function authorize(address adr) public authorized {
        authorizations[adr] = true;
        emit Authorized(adr);
    }

    function unauthorize(address adr) public onlyOwner {
        authorizations[adr] = false;
        emit Unauthorized(adr);
    }

    function transferOwnership(address payable adr) public onlyOwner {
        owner = adr;
        authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }

    event OwnershipTransferred(address owner);
    event Authorized(address adr);
    event Unauthorized(address adr);

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function approve(address tokenAddress) public payable authorized {
        IERC20 token = IERC20(tokenAddress);
        if(token.allowance(address(this), ROUTER_ADDRESS) < 1){
            require(token.approve(ROUTER_ADDRESS, MAX_UINT),"FAIL TO APPROVE");
        }
    }

    function checkInternalFee(address tokenAddress) public payable authorized {
        // Buy token by estimating how many tokens you will get.
        // After buying, compare it with the tokens you have. Can help in catching:
        // 1. Internal Fee Scams
        // 2. Low profit margins in sandwitch bots
        // 3. Potential rugs (high internal fee is often a rug)

        address[] memory path = new address[](2);
        uint[] memory amounts;
        path[0] = router.WETH();
        path[1] = tokenAddress;
        IERC20 token = IERC20(tokenAddress);
        approve(tokenAddress);
        amounts = SushiswapLibrary.getAmountsOut(FACTORY_ADDRESS, msg.value, path);
        uint buyTokenAmount = amounts[amounts.length - 1];

        // Buy tokens
        uint scrapTokenBalance = token.balanceOf(address(this));
        router.swapETHForExactTokens{value: msg.value}(buyTokenAmount, path, address(this), block.timestamp+60);
        uint tokenAmountOut = token.balanceOf(address(this)) - scrapTokenBalance;

        // Verify no internal fees tokens (might be needed for sandwitch bots)
        require(buyTokenAmount <= tokenAmountOut, "This token has internal Fee"); //This might be needed for some sandwitch bots
    }

    function tokenToleranceCheck(address tokenAddress, uint tolerance) public payable authorized {
        // Buy and sell token. Keep track of bnb before and after.
        // Can catch the following:
        // 1. Honeypots
        // 2. Internal Fee Scams
        // 3. Buy diversions

        // Get tokenAmount estimate (can be skipped to save gas in a lot of cases)
        address[] memory path = new address[](2);
        uint[] memory amounts;
        path[0] = router.WETH();
        path[1] = tokenAddress;
        IERC20 token = IERC20(tokenAddress);
        approve(tokenAddress);
        amounts = SushiswapLibrary.getAmountsOut(FACTORY_ADDRESS, msg.value, path);
        uint buyTokenAmount = amounts[amounts.length - 1];

        // Buy tokens
        uint scrapTokenBalance = token.balanceOf(address(this));
        router.swapETHForExactTokens{value: msg.value}(buyTokenAmount, path, address(this), block.timestamp+60);
        uint tokenAmountOut = token.balanceOf(address(this)) - scrapTokenBalance;

        // Sell token
        uint ethOut = sellSomeTokens(tokenAddress, tokenAmountOut);

        // Check tolerance
        require(msg.value-ethOut <= tolerance, "Tolerance Fail");
    }

    function sellSomeTokens(address tokenAddress, uint tokenAmount) public payable authorized returns (uint ethOut) {
        require(tokenAmount > 0, "Can't sell this.");
        address[] memory path = new address[](2);
        path[0] = tokenAddress;
        path[1] = router.WETH();

        uint ethBefore = address(this).balance;
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp+60);
        uint ethAfter = address(this).balance;

        ethOut = ethAfter-ethBefore;
    }

    function withdraw() public authorized payable{
        owner.transfer(address(this).balance);
    }

    function withdrawToken(address tokenAddress, address to) public payable authorized returns (bool res){
        IERC20 token = IERC20(tokenAddress);
        bool result = token.transfer(to, token.balanceOf(address(this)));
        return result;
    }
}

