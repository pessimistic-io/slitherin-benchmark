pragma solidity ^0.8.0;

interface IFrySwapTool
{
    function convertExactEthToFry() 
        external 
        payable;
}

interface IDaiSwapTool
{
    function convertExactEthToDai() 
        external 
        payable;
}

interface IDEthSwapTool
{
    function convertExactEthToDEth() 
        external 
        payable;
}

interface IERC20
{
    function transfer(address _to, uint256 _value) external;
    function balanceOf(address) external view returns (uint256);
}

interface IWETH 
{
    function deposit() 
        payable 
        external;
}

contract Splitter
{
    // This contract recieved Eth and LEVR tokens and sends them to their respective gulper contracts.

    IERC20 public levrErc20;
    IERC20 public daiErc20;
    IERC20 public fryErc20;
    IERC20 public dEthErc20;

    address public ethGulper;
    address public daiGulper;
    address public dEthGulper;

    IDaiSwapTool public daiSwapTool;
    IFrySwapTool public frySwapTool;
    IDEthSwapTool public dEthSwapTool;

    constructor (
        address _levrErc20,
        address _daiErc20,
        address _fryErc20,
        address _dEthErc20,
        address _ethGulper,
        address _daiGulper,
        address _dEthGulper,
        IDaiSwapTool _daiSwapTool,
        IFrySwapTool _frySwapTool,
        IDEthSwapTool _dEthSwapTool)
    {
        levrErc20 = IERC20(_levrErc20);
        daiErc20 = IERC20(_daiErc20);
        fryErc20 = IERC20(_fryErc20);
        dEthErc20 = IERC20(_dEthErc20);

        ethGulper = _ethGulper;
        daiGulper = _daiGulper;
        dEthGulper = _dEthGulper;

        daiSwapTool = _daiSwapTool;
        frySwapTool = _frySwapTool;
        dEthSwapTool = _dEthSwapTool;
    }
    
    function Split() 
        public
    { 
        uint ethBalance = address(this).balance;
        uint levrBalance = levrErc20.balanceOf(address(this));
        uint ethGulperAmount = (ethBalance*950/1000)/3; // one 3rd of 95% 
        GulpEth(ethGulperAmount, levrBalance/3);
        GulpDai(ethGulperAmount, levrBalance/3);
        GulpDeth(ethGulperAmount, levrBalance/3);
        BurnFry(ethBalance*50/1000);
    }

    function GulpEth(uint _ethBalance, uint _levrBalance)
        private
    {
        (bool success,) = ethGulper.call{ value:_ethBalance }(""); 
        require(success, "ethGulper transfer failed");
        levrErc20.transfer(ethGulper, _levrBalance);
    }

    function GulpDai(uint _ethBalance, uint _levrBalance)
        private
    {
        SwapWethForDai(_ethBalance);
        daiErc20.transfer(daiGulper, daiErc20.balanceOf(address(this)));
        levrErc20.transfer(daiGulper, _levrBalance);
    }

    function SwapWethForDai(uint _ethBalance)
        private
    {
        daiSwapTool.convertExactEthToDai{ value:_ethBalance }();
    }

    function GulpDeth(uint _ethBalance, uint _levrBalance)
        private
    {
        SwapWethForDEth(_ethBalance);
        dEthErc20.transfer(dEthGulper, dEthErc20.balanceOf(address(this)));
        levrErc20.transfer(dEthGulper, _levrBalance);
    }

    function SwapWethForDEth(uint _ethBalance)
        private
    {
        dEthSwapTool.convertExactEthToDEth{ value:_ethBalance }();
    }

    function BurnFry(uint _ethBalance)
        private
    {
        SwapWethForFry(_ethBalance);
        fryErc20.transfer(address(1), fryErc20.balanceOf(address(this)));
    }

    function SwapWethForFry(uint _ethBalance)
        private
    {
        frySwapTool.convertExactEthToFry{ value:_ethBalance }();
    }

    receive()
        payable
        external
    { }
}

contract ArbitrumSplitter is Splitter
{
    constructor() Splitter(
        // erc20s 
        address(0x77De4df6F2d87Cc7708959bCEa45d58B0E8b8315),                 // levrErc20.
        address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1),                 // daiErc20.
        address(0x633A3d2091dc7982597A0f635d23Ba5EB1223f48),                 // fryErc20.
        address(0xBA98da6EF5EeB1a66B91B6608E0e2Bb6E9020607),

        // gulpers
        address(0xbe3a1490153Ae6f497852e75E8d022562CAb71C7),                 // ethGulper.
        address(0x78c33207e8E1ddd7634062C3b198266756b30Ba4),                 // daiGulper.
        address(0xf339039197592067f6a5F69cBFF6d8235643942D),                 // dEthGulper.

        // swap tools
        IDaiSwapTool(payable(0x1AD1d774973fD00d6da88cBb2cE944832760fa51)),   // daiSwapTool.
        IFrySwapTool(payable(0x894e8B2E229Ceb55a3DAB49C15DFb1C10E545F8d)),   // frySwapTool.
        IDEthSwapTool(payable(0x19f03b0bc8AF6522bb8Ac4d975C6E0Bd1ce32245)))  // dethSwapTool.  
    {}
}