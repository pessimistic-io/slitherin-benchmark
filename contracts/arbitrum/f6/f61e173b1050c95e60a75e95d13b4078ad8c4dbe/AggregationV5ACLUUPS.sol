// c077ffa5099a4bfaa04669bbc798b1408ec6fa3e
pragma solidity ^0.8.0;
import "./DEXBase.sol";

interface IPool {
    function token0() external returns(address);
    function token1() external returns(address);
}

contract OneInchAggregationV5ACLUUPS is DEXBase{
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    

    string public constant override NAME = "1inchAggreatorV5ACL";
    uint public constant override VERSION = 1;

    //aggreator related
    address public weth;
    uint256 private constant _REVERSE_MASK =   0x8000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant _ADDRESS_MASK =   0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;
    uint256 private constant _ONE_FOR_ZERO_MASK = 1 << 255;

    function setWETH(address _weth) external onlySafe {
        weth = _weth;   
    }

    function getToken(address _token) internal returns(address) {
        return (_token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE || _token == address(0)) ? weth : _token;
    }

    function swap(address, SwapDescription calldata _desc, bytes calldata, bytes calldata) external onlySelf{
        checkRecipient(_desc.dstReceiver);
        address srcToken = getToken(_desc.srcToken);
        address dstToken = getToken(_desc.dstToken);
        swapInOutTokenCheck(srcToken, dstToken);
    }

    //already restrict recipient must be msg.sender in 1inch contract
    function unoswap(address _srcToken, uint256, uint256, uint256[] calldata pools) external onlySelf{
        uint256 lastPool = pools[pools.length-1];
        IPool lastPair = IPool(address(uint160(lastPool & _ADDRESS_MASK)));
        address srcToken = getToken(_srcToken);
        bool isReversed = lastPool & _REVERSE_MASK == 0;
        address tokenOut = isReversed ? lastPair.token1() : lastPair.token0();
        swapInOutTokenCheck(srcToken, tokenOut);

    }

    function uniswapV3Swap(uint256 amount,uint256 minReturn,uint256[] calldata pools) external onlySelf{
        uint256 lastPoolUint = pools[pools.length-1];
        uint256 firstPoolUint = pools[0];
        IPool firstPool = IPool(address(uint160(firstPoolUint)));
        IPool lastPool = IPool(address(uint160(lastPoolUint)));
        bool zeroForOneFirstPool = firstPoolUint & _ONE_FOR_ZERO_MASK == 0;
        bool zeroForOneLastPool = lastPoolUint & _ONE_FOR_ZERO_MASK == 0;
        address srcToken =  zeroForOneFirstPool ? firstPool.token0() : firstPool.token1();     
        address dstToken = zeroForOneLastPool ? lastPool.token1() : firstPool.token0();
        swapInOutTokenCheck(srcToken, dstToken);

    }
}
