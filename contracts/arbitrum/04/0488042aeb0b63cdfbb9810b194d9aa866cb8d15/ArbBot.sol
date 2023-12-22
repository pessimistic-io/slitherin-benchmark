// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >0.7.6;
pragma abicoder v2;

import "./ISwapRouter.sol";
import "./TransferHelper.sol";
import "./IWETH.sol";
// to get arbitrum dicord 16 roles in one click
// created by yiyi,https://github.com/orochi1972
contract ArbBot {
    bool entered =false;
    address public owner;
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address public constant WETH = 0x8b194bEae1d3e0788A1a35173978001ACDFba668;
    // tokens
    address public constant MAGIC =0x539bdE0d7Dbd336b79148AA742883198BBF60342;
    address public constant LINK =0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;
    address public constant GMX =0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
    address public constant DPX =0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55;
    address public constant LPT =0x289ba1701C2F088cf0faf8B3705246331cB8A839;
    address public constant UMAMI =0x1622bF67e6e5747b81866fE0b85178a93C7F86e3;
    address public constant JONES =0x10393c20975cF177a3513071bC110f7962CD67da;
    address public constant SPA =0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant MYC =0xC74fE4c715510Ec2F8C61d70D397B32043F55Abe;
    address public constant PLS =0x51318B7D00db7ACc4026C88c3952B66278B6A67F;
    address public constant VSTA =0xa684cd057951541187f288294a1e1C2646aA2d24;
    address public constant SYN =0x080F6AEd32Fc474DD5717105Dba5ea57268F46eb;
    address public constant DBL =0xd3f1Da62CAFB7E7BC6531FF1ceF6F414291F03D3;
    address public constant BRC =0xB5de3f06aF62D8428a8BF7b4400Ea42aD2E0bc53;
    address public constant ELK =0xeEeEEb57642040bE42185f49C52F7E9B38f8eeeE;
    address public constant SWPR =0xdE903E2712288A1dA82942DDdF2c20529565aC30;

    IWETH public constant ETH9 = IWETH(WETH);
    IERC20 public constant Eth9_20 = IERC20(WETH);
    uint public balance = address(this).balance;
    //pool fee to 0.3%.
    uint24 public constant poolFee = 3000;
    constructor() {
        owner=msg.sender;
    }
    receive() external payable {
    }
    modifier entrancyGuard(){
        require(entered==false,"you cannot do this now");
        entered =true;
        _;
        entered=false;
    }
    
    function swapETHForExactOutput(uint amountInMaximum,uint amountOut, address token) internal returns(uint WETHLeft){
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams(
        WETH,
        token,
        poolFee,
        msg.sender,
        block.timestamp,
        amountOut,
        amountInMaximum,
        0
        );
        //do swap
        swapRouter.exactOutputSingle(params);
        return Eth9_20.balanceOf(address(this));
    }
    function execute() external payable entrancyGuard{
        require(msg.value>=5*1e15,'not enough ETH');
        wrapETH();
        uint balanceNow = Eth9_20.balanceOf(address(this));
        balanceNow = swapETHForExactOutput(balanceNow, 1e15, MAGIC);
        balanceNow = swapETHForExactOutput(balanceNow, 1e15, LINK);
        balanceNow = swapETHForExactOutput(balanceNow, 1e15, GMX);
        balanceNow = swapETHForExactOutput(balanceNow, 1e14, DPX);
        balanceNow = swapETHForExactOutput(balanceNow, 1e15, LPT);
        balanceNow = swapETHForExactOutput(balanceNow, 1e15, UMAMI);
        balanceNow = swapETHForExactOutput(balanceNow, 1e15, JONES);
        balanceNow = swapETHForExactOutput(balanceNow, 1e16, SPA);
        balanceNow = swapETHForExactOutput(balanceNow, 1e16, MYC);
        balanceNow = swapETHForExactOutput(balanceNow, 1e15, PLS);
        balanceNow = swapETHForExactOutput(balanceNow, 1e16, VSTA);
        balanceNow = swapETHForExactOutput(balanceNow, 1e16, SYN);
        balanceNow = swapETHForExactOutput(balanceNow, 1e16, DBL);
        balanceNow = swapETHForExactOutput(balanceNow, 1e16, BRC);
        balanceNow = swapETHForExactOutput(balanceNow, 1e16, ELK);
        balanceNow = swapETHForExactOutput(balanceNow, 1e16, SWPR);
        unwrapETH();
        refund();
    }
    function wrapETH() internal{
        //wrapp to WETH
        TransferHelper.safeTransferETH(WETH,msg.value);
        //approve
        TransferHelper.safeApprove(WETH, address(swapRouter),msg.value);
    }
    function unwrapETH() internal{
        //unwrap
        ETH9.withdraw(Eth9_20.balanceOf(address(this)));
    }
    function refund() internal{
        TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }
    function withdraw() public {
        // in case someone send ether to this contract
        require(msg.sender==owner,'not owner');
        TransferHelper.safeTransferETH(msg.sender,address(this).balance);
    }
}
